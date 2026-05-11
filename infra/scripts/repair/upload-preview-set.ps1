[CmdletBinding()]
param(
    [string]$DataStorageAccountName,
    [Parameter(Mandatory)] [string]$RegistrationId,
    [Parameter(Mandatory)] [string]$SourceFolder,
    [string]$ContainerName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'DataStorageAccountName',
    'ContainerName'
) -Aliases @{
    ContainerName = 'PreviewContainerName'
}

$resolvedSource = Resolve-Path -LiteralPath $SourceFolder
$key = az storage account keys list --account-name $DataStorageAccountName --query '[0].value' -o tsv
$destination = "reg/$RegistrationId"

az storage blob upload-batch `
    --account-name $DataStorageAccountName `
    --account-key $key `
    --destination $ContainerName `
    --destination-path $destination `
    --source $resolvedSource.Path `
    --pattern "*.jpg" `
    --overwrite true

az storage blob upload-batch `
    --account-name $DataStorageAccountName `
    --account-key $key `
    --destination $ContainerName `
    --destination-path $destination `
    --source $resolvedSource.Path `
    --pattern "*.jpeg" `
    --overwrite true

Write-Host "Uploaded preview JPEGs to $ContainerName/$destination"
Write-Host "Publish from the portal admin page or POST /api/admin/previews/$RegistrationId/publish while signed in as an allowlisted admin."
