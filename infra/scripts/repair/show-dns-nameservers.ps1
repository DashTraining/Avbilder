[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$ZoneName
)

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'ZoneName'
) -Aliases @{
    ZoneName = 'DomainName'
}

az network dns zone show `
    --resource-group $ResourceGroupName `
    --name $ZoneName `
    --query nameServers `
    --output table
