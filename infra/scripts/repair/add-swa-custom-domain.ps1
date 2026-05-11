[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$StaticWebAppName,
    [string]$Hostname
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'StaticWebAppName',
    'Hostname'
) -Aliases @{
    Hostname = 'CustomHostname'
}

az staticwebapp hostname set `
    --resource-group $ResourceGroupName `
    --name $StaticWebAppName `
    --hostname $Hostname
