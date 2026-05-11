[CmdletBinding()]
param(
    [string]$DataStorageAccountName,
    [Parameter(Mandatory)] [string]$AdminEmail,
    [string]$TableName = 'AdminAllowlist'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'DataStorageAccountName'
)

$normalizedEmail = $AdminEmail.Trim().ToLowerInvariant()
$key = az storage account keys list --account-name $DataStorageAccountName --query '[0].value' -o tsv

az storage entity insert `
    --account-name $DataStorageAccountName `
    --account-key $key `
    --table-name $TableName `
    --if-exists replace `
    --entity PartitionKey=ADMIN RowKey=$normalizedEmail Email=$normalizedEmail Enabled=true Role=Photographer
