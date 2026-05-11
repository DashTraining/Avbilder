targetScope = 'resourceGroup'

@description('Azure region for the admin App Service resources.')
param location string = 'westeurope'

@description('Admin App Service plan name.')
param adminAppServicePlanName string = 'asp-avbilder-admin-weu'

@description('Admin App Service name.')
param adminAppServiceName string = 'app-avbilder-admin-weu'

@description('Log Analytics workspace name for App Service diagnostic settings.')
param logAnalyticsWorkspaceName string = 'log-avbilder-weu'

@description('Enable App Service authentication and HTTP diagnostics to the Log Analytics workspace.')
param enableAdminDiagnostics bool = true

@description('Optional Entra application client ID for App Service built-in authentication. Leave empty and configure auth with scripts/configure-demo-services.ps1.')
param adminAuthClientId string = ''

param tags object = {
  Project: 'avbilder'
  Workload: 'photographer-swa-demo'
  ManagedBy: 'Bicep'
}

module diagnosticsWorkspace 'modules/log-analytics-workspace.bicep' = {
  name: 'admin-diagnostics-workspace'
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    tags: tags
  }
}

module adminAppServicePlan 'modules/app-service-plan.bicep' = {
  name: 'admin-app-service-plan'
  params: {
    name: adminAppServicePlanName
    location: location
    tags: tags
  }
}

module adminAppService 'modules/app-service-admin.bicep' = {
  name: 'admin-app-service'
  params: {
    name: adminAppServiceName
    location: location
    tags: tags
    appServicePlanId: adminAppServicePlan.outputs.id
    adminAuthClientId: adminAuthClientId
  }
}

resource adminApp 'Microsoft.Web/sites@2022-09-01' existing = {
  name: adminAppServiceName
}

resource adminDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableAdminDiagnostics) {
  name: 'admin-app-service-logs'
  scope: adminApp
  properties: {
    workspaceId: diagnosticsWorkspace.outputs.id
    logs: [
      {
        category: 'AppServiceAuthenticationLogs'
        enabled: true
      }
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
    ]
  }
  dependsOn: [
    adminAppService
  ]
}

output adminAppServicePlanName string = adminAppServicePlan.outputs.name
output adminAppServiceName string = adminAppService.outputs.name
output adminAppServiceDefaultHostName string = adminAppService.outputs.defaultHostName
output logAnalyticsWorkspaceName string = diagnosticsWorkspace.outputs.name
