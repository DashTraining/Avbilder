[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$StaticWebAppName,
    [string]$DataStorageAccountName,
    [string]$ApplicationInsightsName,
    [string]$CommunicationServiceName,
    [string]$DataStorageConnectionString,
    [string]$ApplicationInsightsConnectionString,
    [string]$AcsConnectionString,
    [string]$AcsEmailSender,
    [string]$PublicBaseUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'StaticWebAppName',
    'DataStorageAccountName',
    'ApplicationInsightsName',
    'CommunicationServiceName',
    'PublicBaseUrl'
)
if (-not $PSBoundParameters.ContainsKey('AcsEmailSender') -and [string]::IsNullOrWhiteSpace($AcsEmailSender)) {
    $AcsEmailSender = "$($AvbilderDemoSettings.SenderUsername)@$($AvbilderDemoSettings.DomainName)"
}

function Invoke-AzRestJson {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [string] $Body
    )

    $arguments = @(
        'rest',
        '--only-show-errors',
        '--method', $Method,
        '--uri', $Uri,
        '--output', 'json'
    )

    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $arguments += @('--body', $Body)
    }

    $json = & az @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "az rest $Method failed for $Uri"
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    try {
        return ($json | ConvertFrom-Json)
    }
    catch {
        throw "az rest $Method returned non-JSON output for $Uri. Output was: $json"
    }
}

function Get-AzCliTsvValue {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $Description
    )

    $value = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query $Description."
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Azure CLI returned an empty value for $Description."
    }

    return ($value -join "`n").Trim()
}

$subscriptionId = Get-AzCliTsvValue `
    -Description 'active subscription id' `
    -Arguments @(
        'account', 'show',
        '--only-show-errors',
        '--query', 'id',
        '--output', 'tsv'
    )

if ([string]::IsNullOrWhiteSpace($DataStorageConnectionString)) {
    $DataStorageConnectionString = Get-AzCliTsvValue `
        -Description "storage account connection string for '$DataStorageAccountName'" `
        -Arguments @(
            'storage', 'account', 'show-connection-string',
            '--only-show-errors',
            '--resource-group', $ResourceGroupName,
            '--name', $DataStorageAccountName,
            '--query', 'connectionString',
            '--output', 'tsv'
        )
}

if ([string]::IsNullOrWhiteSpace($ApplicationInsightsConnectionString)) {
    $appInsightsUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/components/$ApplicationInsightsName`?api-version=2020-02-02"
    $appInsights = Invoke-AzRestJson `
        -Method 'get' `
        -Uri $appInsightsUri

    $ApplicationInsightsConnectionString = $appInsights.properties.ConnectionString
    if ([string]::IsNullOrWhiteSpace($ApplicationInsightsConnectionString)) {
        throw "Azure returned an empty Application Insights connection string for '$ApplicationInsightsName'."
    }
}

if ([string]::IsNullOrWhiteSpace($AcsConnectionString)) {
    $acsListKeysUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Communication/CommunicationServices/$CommunicationServiceName/listKeys?api-version=2023-03-31"
    $acsKeys = Invoke-AzRestJson `
        -Method 'post' `
        -Uri $acsListKeysUri

    $AcsConnectionString = $acsKeys.primaryConnectionString
    if ([string]::IsNullOrWhiteSpace($AcsConnectionString)) {
        throw "Azure returned an empty ACS connection string for '$CommunicationServiceName'."
    }
}

$settings = @(
    "DATA_STORAGE_CONNECTION_STRING=$DataStorageConnectionString",
    'TABLE_CUSTOMER_PROFILES=CustomerProfiles',
    'TABLE_SESSION_REGISTRATIONS=SessionRegistrations',
    'TABLE_SURVEY_RESPONSES=SurveyResponses',
    'TABLE_PREVIEW_SETS=PreviewSets',
    'TABLE_ADMIN_ALLOWLIST=AdminAllowlist',
    'TABLE_NOTIFICATION_LOG=NotificationLog',
    'BLOB_CONTAINER_PREVIEWS=previews',
    "ACS_EMAIL_SENDER=$AcsEmailSender",
    "APP_PUBLIC_BASE_URL=$PublicBaseUrl"
)

if (-not [string]::IsNullOrWhiteSpace($AcsConnectionString)) {
    $settings += "ACS_CONNECTION_STRING=$AcsConnectionString"
}

if (-not [string]::IsNullOrWhiteSpace($ApplicationInsightsConnectionString)) {
    $settings += "APPLICATIONINSIGHTS_CONNECTION_STRING=$ApplicationInsightsConnectionString"
}

az staticwebapp appsettings set `
    --name $StaticWebAppName `
    --resource-group $ResourceGroupName `
    --setting-names $settings
