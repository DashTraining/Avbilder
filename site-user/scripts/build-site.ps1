#Requires -Module Hyde

[CmdletBinding()]
param(
    [string]$SourcePath = (Resolve-Path "$PSScriptRoot\..\site_source").Path,
    [string]$DestinationPath = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'site'),
    [string]$Environment = 'production'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$publish = Get-Command Publish-StaticSite -ErrorAction Stop
Write-Host "Using $($publish.Source) $($publish.Version) to build the static site."

if (-not (Test-Path -LiteralPath $DestinationPath)) {
    New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
}
else {
    $destinationItem = Get-Item -LiteralPath $DestinationPath
    $repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
    if (-not $destinationItem.FullName.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean destination outside the site-user workspace: $($destinationItem.FullName)"
    }

    Get-ChildItem -LiteralPath $DestinationPath -Force | Remove-Item -Recurse -Force
}

Push-Location $SourcePath
try {
    Publish-StaticSite -Source $SourcePath -Destination $DestinationPath -Environment $Environment
}
finally {
    Pop-Location
}

$configPath = Join-Path $DestinationPath 'staticwebapp.config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "The build did not produce $configPath. staticwebapp.config.json must be present in the deployed site output."
}

Write-Host "Built site output at $DestinationPath"
