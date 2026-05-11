[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$AdminAppServiceName,
    [string]$WorkspaceName,
    [string]$DiagnosticSettingName = 'admin-auth-logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'AdminAppServiceName',
    'WorkspaceName'
) -Aliases @{
    WorkspaceName = 'LogAnalyticsWorkspaceName'
}

$subscriptionId = az account show --query id --output tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'No active Azure subscription was found. Run az login and az account set first.'
}

$adminAppId = az webapp show `
    --name $AdminAppServiceName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv

$workspaceId = az monitor log-analytics workspace show `
    --name $WorkspaceName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv
if ([string]::IsNullOrWhiteSpace($workspaceId)) {
    throw "Log Analytics workspace '$WorkspaceName' was not found in resource group '$ResourceGroupName'. Run scripts/deploy-infra.ps1 first, or scripts/repair/deploy-admin-infra.ps1 for an admin-only repair."
}

az monitor diagnostic-settings create `
    --name $DiagnosticSettingName `
    --resource $adminAppId `
    --workspace $workspaceId `
    --logs '[
        {"category":"AppServiceAuthenticationLogs","enabled":true},
        {"category":"AppServiceHTTPLogs","enabled":true}
    ]' | Out-Null

[pscustomobject]@{
    AdminAppServiceName = $AdminAppServiceName
    DiagnosticSettingName = $DiagnosticSettingName
    WorkspaceId = $workspaceId
    EnabledLogs = 'AppServiceAuthenticationLogs, AppServiceHTTPLogs'
}
