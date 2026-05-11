param(
    [string]$StorageAccountName = 'stavbilderdataweu01',
    [string]$ContainerName = 'previews',
    [int]$RetentionDays = 90,
    [bool]$DryRun = $true,
    [bool]$CleanOrphans = $true
)

$ErrorActionPreference = 'Stop'
$storageVersion = '2023-11-03'
$tableVersion = '2019-02-02'
$cutoffUtc = [DateTimeOffset]::UtcNow.AddDays(-1 * $RetentionDays)

function Get-StorageToken {
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity | Out-Null
    $token = Get-AzAccessToken -ResourceUrl 'https://storage.azure.com/'
    if ($token.Token -is [securestring]) {
        return [System.Net.NetworkCredential]::new('', $token.Token).Password
    }

    return $token.Token
}

function New-StorageHeaders {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [string] $Version = $storageVersion,
        [hashtable] $Extra = @{}
    )

    $headers = @{
        Authorization = "Bearer $Token"
        'x-ms-date' = (Get-Date).ToUniversalTime().ToString('R')
        'x-ms-version' = $Version
    }

    foreach ($key in $Extra.Keys) {
        $headers[$key] = $Extra[$key]
    }

    return $headers
}

function Invoke-StorageRequest {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Token,
        [string] $Version = $storageVersion,
        [hashtable] $ExtraHeaders = @{},
        [string] $Body
    )

    $headers = New-StorageHeaders -Token $Token -Version $Version -Extra $ExtraHeaders
    $arguments = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $arguments.Body = $Body
        $arguments.ContentType = 'application/json'
    }

    Invoke-RestMethod @arguments
}

function Get-ResponseStatusCode {
    param(
        [Parameter(Mandatory)] [object] $ErrorRecord
    )

    $statusCode = $ErrorRecord.Exception.Response.StatusCode
    if ($null -eq $statusCode) {
        return $null
    }

    if ($statusCode.PSObject.Properties.Name -contains 'value__') {
        return [int]$statusCode.value__
    }

    return [int]$statusCode
}

function ConvertTo-XmlDocument {
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $Value
    )

    process {
        if ($Value -is [System.Xml.XmlDocument]) {
            return $Value
        }

        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw 'Storage service returned an empty XML response.'
        }

        # Azure Automation can surface UTF-8 BOM bytes as the literal string "ï»¿".
        # Strip both that mojibake prefix and the real BOM character before LoadXml().
        $text = $text.Trim()
        $text = $text.TrimStart([char]0xFEFF)
        if ($text.StartsWith('ï»¿')) {
            $text = $text.Substring(3).TrimStart()
        }

        $firstElement = $text.IndexOf('<')
        if ($firstElement -gt 0) {
            $text = $text.Substring($firstElement)
        }

        $document = [System.Xml.XmlDocument]::new()
        $document.PreserveWhitespace = $false
        $document.LoadXml($text)
        return $document
    }
}

function Ensure-TableExists {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [Parameter(Mandatory)] [string] $TableName
    )

    $uri = "https://$StorageAccountName.table.core.windows.net/Tables"
    $body = @{
        TableName = $TableName
    } | ConvertTo-Json -Compress

    try {
        Invoke-StorageRequest `
            -Method 'POST' `
            -Uri $uri `
            -Token $Token `
            -Version $tableVersion `
            -ExtraHeaders @{
                Accept = 'application/json;odata=nometadata'
                Prefer = 'return-no-content'
            } `
            -Body $body | Out-Null
    }
    catch {
        if ((Get-ResponseStatusCode -ErrorRecord $_) -ne 409) {
            throw
        }
    }
}

function Get-PreviewBlobs {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [string] $Prefix = 'reg/'
    )

    $blobs = @()
    $marker = ''
    do {
        $uri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName`?restype=container&comp=list&prefix=$([uri]::EscapeDataString($Prefix))"
        if ($marker) {
            $uri += "&marker=$([uri]::EscapeDataString($marker))"
        }

        $response = Invoke-StorageRequest -Method 'GET' -Uri $uri -Token $Token | ConvertTo-XmlDocument
        foreach ($blob in @($response.EnumerationResults.Blobs.Blob)) {
            if ($null -eq $blob) {
                continue
            }

            $name = [string]$blob.Name
            $parts = $name.Split('/')
            if ($parts.Length -lt 3 -or $parts[0] -ne 'reg') {
                continue
            }

            $blobs += [pscustomobject]@{
                Name = $name
                RegistrationId = $parts[1]
                LastModified = [DateTimeOffset]::Parse([string]$blob.Properties.'Last-Modified').ToUniversalTime()
            }
        }

        $marker = ([string]$response.EnumerationResults.NextMarker).Trim()
    } while (-not [string]::IsNullOrWhiteSpace($marker))

    return $blobs
}

function Get-Registration {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [Parameter(Mandatory)] [string] $RegistrationId
    )

    $filter = [uri]::EscapeDataString("RowKey eq 'REG_$RegistrationId'")
    $uri = "https://$StorageAccountName.table.core.windows.net/SessionRegistrations()?`$filter=$filter"
    $response = Invoke-StorageRequest `
        -Method 'GET' `
        -Uri $uri `
        -Token $Token `
        -Version $tableVersion `
        -ExtraHeaders @{ Accept = 'application/json;odata=nometadata' }

    return @($response.value) | Select-Object -First 1
}

function Remove-PreviewSet {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [Parameter(Mandatory)] [string] $RegistrationId
    )

    $uri = "https://$StorageAccountName.table.core.windows.net/PreviewSets(PartitionKey='REG_$RegistrationId',RowKey='PREVIEW')"
    try {
        Invoke-StorageRequest `
            -Method 'DELETE' `
            -Uri $uri `
            -Token $Token `
            -Version $tableVersion `
            -ExtraHeaders @{ 'If-Match' = '*' } | Out-Null
    }
    catch {
        if ((Get-ResponseStatusCode -ErrorRecord $_) -ne 404) {
            throw
        }
    }
}

function Set-RegistrationPreviewExpired {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [Parameter(Mandatory)] $Registration
    )

    $partitionKey = [uri]::EscapeDataString([string]$Registration.PartitionKey)
    $rowKey = [uri]::EscapeDataString([string]$Registration.RowKey)
    $uri = "https://$StorageAccountName.table.core.windows.net/SessionRegistrations(PartitionKey='$partitionKey',RowKey='$rowKey')"
    $body = @{
        previewStatus = 'PreviewExpired'
        previewCount = 0
        updatedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    } | ConvertTo-Json -Compress

    Invoke-StorageRequest `
        -Method 'MERGE' `
        -Uri $uri `
        -Token $Token `
        -Version $tableVersion `
        -ExtraHeaders @{
            'If-Match' = '*'
            Accept = 'application/json;odata=nometadata'
        } `
        -Body $body | Out-Null
}

function Remove-Blob {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [Parameter(Mandatory)] [string] $BlobName
    )

    $encodedName = ($BlobName.Split('/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $uri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$encodedName"
    Invoke-StorageRequest -Method 'DELETE' -Uri $uri -Token $Token | Out-Null
}

function Write-Audit {
    param(
        [Parameter(Mandatory)] [string] $Token,
        [Parameter(Mandatory)] [object] $Summary
    )

    $rowId = [guid]::NewGuid().ToString('n')
    $tableName = 'MaintenanceLog'
    $uri = "https://$StorageAccountName.table.core.windows.net/$tableName"
    $body = @{
        PartitionKey = 'PREVIEW_CLEANUP'
        RowKey = "RUN_$rowId"
        createdUtc = [DateTimeOffset]::UtcNow.ToString('o')
        retentionDays = $RetentionDays
        dryRun = $DryRun
        expiredBlobCandidates = $Summary.ExpiredBlobCandidates
        deletedBlobs = $Summary.DeletedBlobs
        orphanBlobCandidates = $Summary.OrphanBlobCandidates
        removedPreviewSets = $Summary.RemovedPreviewSets
        expiredRegistrations = $Summary.ExpiredRegistrations
        message = $Summary.Message
    } | ConvertTo-Json -Compress

    try {
        Ensure-TableExists -Token $Token -TableName $tableName

        Invoke-StorageRequest `
            -Method 'POST' `
            -Uri $uri `
            -Token $Token `
            -Version $tableVersion `
            -ExtraHeaders @{
                Accept = 'application/json;odata=nometadata'
                Prefer = 'return-no-content'
            } `
            -Body $body | Out-Null
    }
    catch {
        Write-Warning "Could not write MaintenanceLog audit row: $($_.Exception.Message)"
    }
}

$token = Get-StorageToken
$blobs = @(Get-PreviewBlobs -Token $token)
$groups = $blobs | Group-Object RegistrationId

$summary = [ordered]@{
    ExpiredBlobCandidates = 0
    DeletedBlobs = 0
    OrphanBlobCandidates = 0
    RemovedPreviewSets = 0
    ExpiredRegistrations = 0
    Message = ''
}

foreach ($group in $groups) {
    $registrationId = $group.Name
    $registration = Get-Registration -Token $token -RegistrationId $registrationId
    $isOrphan = $null -eq $registration
    $oldBlobs = @($group.Group | Where-Object LastModified -lt $cutoffUtc)
    $remainingBlobs = @($group.Group | Where-Object LastModified -ge $cutoffUtc)

    if ($isOrphan -and $CleanOrphans) {
        $summary.OrphanBlobCandidates += $oldBlobs.Count
    }

    $summary.ExpiredBlobCandidates += $oldBlobs.Count

    foreach ($blob in $oldBlobs) {
        if (-not $DryRun) {
            Remove-Blob -Token $token -BlobName $blob.Name
            $summary.DeletedBlobs++
        }
    }

    if (-not $DryRun -and -not $isOrphan -and $oldBlobs.Count -gt 0 -and $remainingBlobs.Count -eq 0) {
        Remove-PreviewSet -Token $token -RegistrationId $registrationId
        Set-RegistrationPreviewExpired -Token $token -Registration $registration
        $summary.RemovedPreviewSets++
        $summary.ExpiredRegistrations++
    }
}

$summary.Message = "Preview cleanup completed. DryRun=$DryRun RetentionDays=$RetentionDays Groups=$($groups.Count)"
Write-Audit -Token $token -Summary ([pscustomobject]$summary)
[pscustomobject]$summary
