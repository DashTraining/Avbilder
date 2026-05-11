[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$Location,
    [string]$DeploymentName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'Location',
    'DeploymentName'
)

Set-Location $RootPath
az bicep build --file .\main.bicep
az deployment sub create `
    --name $DeploymentName `
    --location $Location `
    --template-file .\main.bicep `
    --parameters .\main.bicepparam
