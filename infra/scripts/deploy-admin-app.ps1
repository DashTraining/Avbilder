[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$AdminAppServiceName,
    [string]$ProjectPath = (Resolve-Path "$PSScriptRoot\..\..\site-admin").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'AdminAppServiceName'
)

$publishPath = Join-Path ([System.IO.Path]::GetTempPath()) 'avbilder-admin-publish'
$packagePath = Join-Path ([System.IO.Path]::GetTempPath()) 'avbilder-admin.zip'

Remove-Item -LiteralPath $publishPath, $packagePath -Recurse -Force -ErrorAction SilentlyContinue

dotnet publish $ProjectPath `
    --configuration Release `
    --output $publishPath

Compress-Archive `
    -Path (Join-Path $publishPath '*') `
    -DestinationPath $packagePath `
    -Force

az webapp deploy `
    --resource-group $ResourceGroupName `
    --name $AdminAppServiceName `
    --src-path $packagePath `
    --type zip | Out-Null

[pscustomobject]@{
    AdminAppServiceName = $AdminAppServiceName
    PackagePath = $packagePath
}
