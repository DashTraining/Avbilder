[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$ZoneName,
    [string]$StaticWebAppName,
    [string]$AdminAppServiceName,
    [string]$EmailServiceName,
    [string]$DomainName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'ZoneName',
    'StaticWebAppName',
    'AdminAppServiceName',
    'EmailServiceName',
    'DomainName'
) -Aliases @{
    ZoneName = 'DomainName'
}

function Has-Setting {
    param(
        [Parameter(Mandatory)] $Settings,
        [Parameter(Mandatory)] [string] $Name
    )

    [bool]($Settings.PSObject.Properties.Name -contains $Name) -or [bool]($Settings | Where-Object name -eq $Name)
}

$swaSettings = az staticwebapp appsettings list `
    --name $StaticWebAppName `
    --resource-group $ResourceGroupName `
    --query properties `
    --output json | ConvertFrom-Json

$adminSettings = az webapp config appsettings list `
    --name $AdminAppServiceName `
    --resource-group $ResourceGroupName `
    --output json | ConvertFrom-Json

$authEnabled = az webapp auth show `
    --name $AdminAppServiceName `
    --resource-group $ResourceGroupName `
    --query enabled `
    --output tsv

$dmarc = az network dns record-set txt show `
    --resource-group $ResourceGroupName `
    --zone-name $ZoneName `
    --name _dmarc `
    --query "TXTRecords[0].value[0]" `
    --output tsv 2>$null

$domainState = az communication email domain show `
    --resource-group $ResourceGroupName `
    --email-service-name $EmailServiceName `
    --domain-name $DomainName `
    --query "verificationStates" `
    --output json 2>$null | ConvertFrom-Json

[pscustomobject]@{
    StaticWebAppName = $StaticWebAppName
    SwaHasDataStorage = Has-Setting -Settings $swaSettings -Name 'DATA_STORAGE_CONNECTION_STRING'
    SwaHasAcsConnection = Has-Setting -Settings $swaSettings -Name 'ACS_CONNECTION_STRING'
    SwaHasAcsSender = Has-Setting -Settings $swaSettings -Name 'ACS_EMAIL_SENDER'
    AdminAppServiceName = $AdminAppServiceName
    AdminHasDataStorage = Has-Setting -Settings $adminSettings -Name 'DATA_STORAGE_CONNECTION_STRING'
    AdminHasAcsConnection = Has-Setting -Settings $adminSettings -Name 'ACS_CONNECTION_STRING'
    AdminHasAcsSender = Has-Setting -Settings $adminSettings -Name 'ACS_EMAIL_SENDER'
    AdminAuthEnabled = $authEnabled
    DmarcRecord = $dmarc
    DomainVerified = $domainState.Domain.status
    SpfVerified = $domainState.SPF.status
    DkimVerified = $domainState.DKIM.status
    Dkim2Verified = $domainState.DKIM2.status
    DmarcVerified = $domainState.DMARC.status
}
