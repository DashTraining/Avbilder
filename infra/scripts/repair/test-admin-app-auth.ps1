[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$AdminAppServiceName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'AdminAppServiceName'
)

$subscriptionId = az account show --query id --output tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'No active Azure subscription was found. Run az login and az account set first.'
}

$authUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$AdminAppServiceName/config/authsettingsV2?api-version=2022-09-01"
$auth = az rest `
    --only-show-errors `
    --method get `
    --uri $authUri `
    --output json | ConvertFrom-Json

$settings = az webapp config appsettings list `
    --name $AdminAppServiceName `
    --resource-group $ResourceGroupName `
    --query "[].name" `
    --output tsv

$defaultHostName = az webapp show `
    --name $AdminAppServiceName `
    --resource-group $ResourceGroupName `
    --query defaultHostName `
    --output tsv

[pscustomobject]@{
    AdminUrl = "https://$defaultHostName"
    AuthPlatformEnabled = [bool]$auth.properties.platform.enabled
    RequireAuthentication = [bool]$auth.properties.globalValidation.requireAuthentication
    RedirectProvider = $auth.properties.globalValidation.redirectToProvider
    AzureAdProviderEnabled = [bool]$auth.properties.identityProviders.azureActiveDirectory.enabled
    HasAuthSecretSetting = $settings -contains 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
    HasDataStorageSetting = $settings -contains 'DATA_STORAGE_CONNECTION_STRING'
    HasAppInsightsSetting = $settings -contains 'APPLICATIONINSIGHTS_CONNECTION_STRING'
}
