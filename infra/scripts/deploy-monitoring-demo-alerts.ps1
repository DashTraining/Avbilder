[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$ResourceGroupName,
    [string]$DeploymentName = 'avbilder-monitoring-demo-alerts',
    [switch]$Disabled
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName'
)

Set-Location $RootPath

az bicep build --file .\monitoring-demo-alerts.bicep

$alertsEnabled = if ($Disabled) { 'false' } else { 'true' }

az deployment group create `
    --resource-group $ResourceGroupName `
    --name $DeploymentName `
    --template-file .\monitoring-demo-alerts.bicep `
    --parameters alertsEnabled=$alertsEnabled
