[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$ZoneName,
    [string]$StaticWebAppName,
    [string]$WwwRecordName = 'www',
    [string]$DmarcRecordName = '_dmarc',
    [string]$DmarcValue = 'v=DMARC1; p=none; adkim=s; aspf=s; pct=100',
    [int]$WwwTtl = 300,
    [int]$DmarcTtl = 3600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'ZoneName',
    'StaticWebAppName'
) -Aliases @{
    ZoneName = 'DomainName'
}

function Invoke-AzRestJson {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [object] $Payload
    )

    $bodyPath = Join-Path ([System.IO.Path]::GetTempPath()) "avbilder-dns-$([guid]::NewGuid().ToString('n')).json"
    try {
        $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bodyPath -Encoding UTF8
        $json = az rest --only-show-errors --method $Method --uri $Uri --headers 'Content-Type=application/json' --body "@$bodyPath" --output json
        if ($LASTEXITCODE -ne 0) {
            throw "az rest $Method failed for $Uri"
        }

        if ([string]::IsNullOrWhiteSpace($json)) {
            return $null
        }

        return ($json | ConvertFrom-Json)
    }
    finally {
        Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-AzCliTsvValue {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $Description
    )

    $value = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query $Description."
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Azure CLI returned an empty value for $Description."
    }

    return ($value -join "`n").Trim()
}

$subscriptionId = Get-AzCliTsvValue `
    -Description 'active subscription id' `
    -Arguments @('account', 'show', '--only-show-errors', '--query', 'id', '--output', 'tsv')

$swaHostName = Get-AzCliTsvValue `
    -Description "default hostname for '$StaticWebAppName'" `
    -Arguments @(
        'staticwebapp', 'show',
        '--only-show-errors',
        '--resource-group', $ResourceGroupName,
        '--name', $StaticWebAppName,
        '--query', 'defaultHostname',
        '--output', 'tsv'
    )

$dnsApiVersion = '2018-05-01'
$zoneBaseUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/dnsZones/$ZoneName"

# Keep DNS record creation idempotent so rerunning the setup script is harmless.
$wwwPayload = @{
    properties = @{
        TTL = $WwwTtl
        CNAMERecord = @{
            cname = $swaHostName
        }
    }
}
Invoke-AzRestJson `
    -Method 'put' `
    -Uri "$zoneBaseUri/CNAME/$WwwRecordName`?api-version=$dnsApiVersion" `
    -Payload $wwwPayload | Out-Null

# DMARC starts in monitor-only mode for the demo. It improves email trust without rejecting mail.
$dmarcPayload = @{
    properties = @{
        TTL = $DmarcTtl
        TXTRecords = @(
            @{
                value = @($DmarcValue)
            }
        )
    }
}
Invoke-AzRestJson `
    -Method 'put' `
    -Uri "$zoneBaseUri/TXT/$DmarcRecordName`?api-version=$dnsApiVersion" `
    -Payload $dmarcPayload | Out-Null

[pscustomobject]@{
    ZoneName = $ZoneName
    WwwRecord = "$WwwRecordName.$ZoneName"
    WwwTarget = $swaHostName
    DmarcRecord = "$DmarcRecordName.$ZoneName"
    DmarcValue = $DmarcValue
}
