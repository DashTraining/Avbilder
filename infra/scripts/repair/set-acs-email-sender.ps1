[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$CommunicationServiceName,
    [string]$EmailServiceName,
    [string]$DomainName,
    [string]$StaticWebAppName,
    [string]$SenderUsername,
    [string]$DisplayName,
    [switch]$CreateDomain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'CommunicationServiceName',
    'EmailServiceName',
    'DomainName',
    'StaticWebAppName',
    'SenderUsername',
    'DisplayName'
) -Aliases @{
    DisplayName = 'SenderDisplayName'
}

function Invoke-AzRestJson {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [string] $Body
    )

    $arguments = @(
        'rest',
        '--only-show-errors',
        '--method', $Method,
        '--uri', $Uri,
        '--output', 'json'
    )

    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $arguments += @('--body', $Body)
    }

    $json = & az @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "az rest $Method failed for $Uri"
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    try {
        return ($json | ConvertFrom-Json)
    }
    catch {
        throw "az rest $Method returned non-JSON output for $Uri. Output was: $json"
    }
}

function Get-NestedPropertyValue {
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [string[]] $Path
    )

    $current = $InputObject
    foreach ($segment in $Path) {
        if (-not $current) {
            return $null
        }

        $property = $current.PSObject.Properties[$segment]
        if (-not $property) {
            return $null
        }

        $current = $property.Value
    }

    return $current
}

$senderAddress = "$SenderUsername@$DomainName"
$subscriptionId = az account show --query id --output tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'No active Azure subscription was found. Run az login and az account set first.'
}

$domainResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Communication/emailServices/$EmailServiceName/domains/$DomainName"
$domainUri = "https://management.azure.com$domainResourceId`?api-version=2023-03-31"
$senderResourceId = "$domainResourceId/senderUsernames/$SenderUsername"
$senderUri = "https://management.azure.com$senderResourceId`?api-version=2023-03-31"

if ($CreateDomain) {
    $domainBody = @{
        location = 'global'
        properties = @{
            domainManagement = 'CustomerManaged'
            userEngagementTracking = 'Disabled'
        }
    } | ConvertTo-Json -Depth 5

    Invoke-AzRestJson `
        -Method 'put' `
        -Uri $domainUri `
        -Body $domainBody | Out-Null

    Write-Warning "Created or updated the ACS Email domain '$DomainName'. Complete DNS verification in Azure before continuing."
}

$domain = Invoke-AzRestJson `
    -Method 'get' `
    -Uri $domainUri

if (-not $domain) {
    throw "Email domain '$DomainName' was not found under Email Service '$EmailServiceName'. Run with -CreateDomain, then verify the required DNS records."
}

$verificationStates = @(
    Get-NestedPropertyValue -InputObject $domain -Path @('properties', 'verificationStates', 'Domain', 'status')
    Get-NestedPropertyValue -InputObject $domain -Path @('properties', 'verificationStates', 'SPF', 'status')
    Get-NestedPropertyValue -InputObject $domain -Path @('properties', 'verificationStates', 'DKIM', 'status')
    Get-NestedPropertyValue -InputObject $domain -Path @('properties', 'verificationStates', 'DKIM2', 'status')
    Get-NestedPropertyValue -InputObject $domain -Path @('properties', 'verificationStates', 'DMARC', 'status')
) | Where-Object { $_ }

if ($verificationStates -contains 'Failed' -or $verificationStates -contains 'NotStarted' -or $verificationStates -contains 'VerificationRequested') {
    Write-Warning "Domain '$DomainName' does not look fully verified yet. Sender creation/linking may fail until ACS Email verification is complete."
}

$senderBody = @{
    properties = @{
        username = $SenderUsername
        displayName = $DisplayName
    }
} | ConvertTo-Json -Depth 5

Invoke-AzRestJson `
    -Method 'put' `
    -Uri $senderUri `
    -Body $senderBody | Out-Null

$communicationServiceUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Communication/CommunicationServices/$CommunicationServiceName`?api-version=2023-03-31"
$body = @{
    properties = @{
        linkedDomains = @($domainResourceId)
    }
} | ConvertTo-Json -Depth 5

Invoke-AzRestJson `
    -Method 'patch' `
    -Uri $communicationServiceUri `
    -Body $body | Out-Null

az staticwebapp appsettings set `
    --name $StaticWebAppName `
    --resource-group $ResourceGroupName `
    --setting-names "ACS_EMAIL_SENDER=$senderAddress" | Out-Null

[pscustomobject]@{
    EmailServiceName = $EmailServiceName
    DomainName = $DomainName
    CommunicationServiceName = $CommunicationServiceName
    LinkedDomainId = $domainResourceId
    SenderAddress = $senderAddress
    StaticWebAppName = $StaticWebAppName
    StaticWebAppSetting = 'ACS_EMAIL_SENDER'
}
