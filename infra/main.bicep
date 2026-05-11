targetScope = 'subscription'

@description('Azure region for all regional resources.')
param location string = 'westeurope'

@description('Short project name used in resource names.')
param projectShortName string = 'avbilder'

@description('Primary DNS zone. Azure DNS will be authoritative for this zone.')
param dnsZoneName string = 'avbilder.no'

@description('Resource group name.')
param resourceGroupName string = 'rg-avbilder-weu'

@description('Static Web App SKU. Free keeps the core demo low-cost. Do not use linked backend with Free.')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('Create DNS CNAME for www to the SWA generated hostname. Custom-domain binding still requires a post-deploy step.')
param createWwwCname bool = true

@description('Create a demo-safe DMARC TXT record in Azure DNS. Registrar delegation is still manual.')
param createDmarcRecord bool = true

@description('Send ACS Email diagnostics to the explicit Log Analytics workspace.')
param enableCommunicationDiagnostics bool = true

@description('Create a Key Vault secret placeholder for the External ID OIDC client secret. Use only non-production placeholder values here; replace by script/manual step.')
param createOidcSecretPlaceholder bool = false

@secure()
@description('Placeholder OIDC client secret value. Prefer setting this later through Key Vault or a repair script.')
param oidcClientSecret string = ''

@description('Optional Entra application client ID for App Service built-in authentication on the admin portal. Leave empty and configure auth manually after deployment.')
param adminAuthClientId string = ''

var tags = {
  Project: projectShortName
  Workload: 'photographer-swa-demo'
  ManagedBy: 'Bicep'
}

var suffix = 'weu'
var dataStorageName = 'st${projectShortName}data${suffix}01'
var keyVaultName = 'kv-${projectShortName}-${suffix}'
var staticWebAppName = 'swa-${projectShortName}-${suffix}'
var adminAppServicePlanName = 'asp-${projectShortName}-admin-${suffix}'
var adminAppServiceName = 'app-${projectShortName}-admin-${suffix}'
var appInsightsName = 'appi-${projectShortName}-${suffix}'
var logAnalyticsWorkspaceName = 'log-${projectShortName}-${suffix}'
var commServiceName = 'acs-${projectShortName}-${suffix}'
var emailServiceName = 'email-${projectShortName}-${suffix}'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module dataStorage 'modules/storage-account.bicep' = {
  name: 'data-storage'
  scope: rg
  params: {
    name: dataStorageName
    location: location
    tags: tags
    allowBlobPublicAccess: false
  }
}

module previewsContainer 'modules/storage-blob-container.bicep' = {
  name: 'container-previews'
  scope: rg
  params: {
    storageAccountName: dataStorage.outputs.name
    containerName: 'previews'
  }
}

var tables = [
  'CustomerProfiles'
  'SessionRegistrations'
  'SurveyResponses'
  'PreviewSets'
  'AdminAllowlist'
  'NotificationLog'
  'MaintenanceLog'
]

module storageTables 'modules/storage-table.bicep' = [for tableName in tables: {
  name: 'table-${tableName}'
  scope: rg
  params: {
    storageAccountName: dataStorage.outputs.name
    tableName: tableName
  }
}]

module keyVault 'modules/key-vault.bicep' = {
  name: 'key-vault'
  scope: rg
  params: {
    name: keyVaultName
    location: location
    tags: tags
  }
}

module oidcSecret 'modules/key-vault-secret.bicep' = if (createOidcSecretPlaceholder && !empty(oidcClientSecret)) {
  name: 'secret-oidc-client-secret'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    secretName: 'swa-auth-oidc-client-secret'
    secretValue: oidcClientSecret
  }
}

module logAnalyticsWorkspace 'modules/log-analytics-workspace.bicep' = {
  name: 'log-analytics-workspace'
  scope: rg
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    tags: tags
  }
}

module appInsights 'modules/application-insights.bicep' = {
  name: 'app-insights'
  scope: rg
  params: {
    name: appInsightsName
    location: location
    tags: tags
    workspaceResourceId: logAnalyticsWorkspace.outputs.id
  }
}

module staticWebApp 'modules/static-web-app.bicep' = {
  name: 'static-web-app'
  scope: rg
  params: {
    name: staticWebAppName
    location: location
    tags: tags
    skuName: staticWebAppSku
  }
}

module adminAppServicePlan 'modules/app-service-plan.bicep' = {
  name: 'admin-app-service-plan'
  scope: rg
  params: {
    name: adminAppServicePlanName
    location: location
    tags: tags
  }
}

module adminAppService 'modules/app-service-admin.bicep' = {
  name: 'admin-app-service'
  scope: rg
  params: {
    name: adminAppServiceName
    location: location
    tags: tags
    appServicePlanId: adminAppServicePlan.outputs.id
    adminAuthClientId: adminAuthClientId
  }
}

module dnsZone 'modules/dns-zone-public.bicep' = {
  name: 'dns-zone-public'
  scope: rg
  params: {
    zoneName: dnsZoneName
    tags: tags
  }
}

module wwwCname 'modules/dns-cname-record.bicep' = if (createWwwCname) {
  name: 'dns-cname-www'
  scope: rg
  params: {
    zoneName: dnsZone.outputs.name
    recordName: 'www'
    cnameTarget: staticWebApp.outputs.defaultHostname
    ttl: 300
  }
}

module dmarcTxt 'modules/dns-txt-record.bicep' = if (createDmarcRecord) {
  name: 'dns-txt-dmarc'
  scope: rg
  params: {
    zoneName: dnsZone.outputs.name
    recordName: '_dmarc'
    values: [
      'v=DMARC1; p=none; adkim=s; aspf=s; pct=100'
    ]
    ttl: 3600
  }
}

module communication 'modules/communication-services.bicep' = {
  name: 'communication-services'
  scope: rg
  params: {
    name: commServiceName
    location: 'global'
    tags: tags
  }
}

module communicationDiagnostics 'modules/communication-diagnostics.bicep' = if (enableCommunicationDiagnostics) {
  name: 'communication-diagnostics'
  scope: rg
  params: {
    communicationServiceName: communication.outputs.name
    workspaceResourceId: logAnalyticsWorkspace.outputs.id
  }
}

module email 'modules/email-service.bicep' = {
  name: 'email-service'
  scope: rg
  params: {
    name: emailServiceName
    location: 'global'
    tags: tags
  }
}

/*
Future extension point only. Not deployed in v1.

module acaEnv 'modules/container-app-environment.bicep' = {
  name: 'container-app-env'
  scope: rg
  params: {
    name: 'cae-${projectShortName}-${suffix}'
    location: location
    tags: tags
  }
}

module imageResizer 'modules/container-app-image-resizer.bicep' = {
  name: 'container-app-image-resizer'
  scope: rg
  params: {
    name: 'ca-${projectShortName}-resize-${suffix}'
    location: location
    tags: tags
  }
}
*/

output resourceGroup string = rg.name
output staticWebAppName string = staticWebApp.outputs.name
output staticWebAppDefaultHostname string = staticWebApp.outputs.defaultHostname
output adminAppServiceName string = adminAppService.outputs.name
output adminAppServiceDefaultHostName string = adminAppService.outputs.defaultHostName
output dnsZoneName string = dnsZone.outputs.name
output dnsNameServers array = dnsZone.outputs.nameServers
output dataStorageAccountName string = dataStorage.outputs.name
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.uri
output appInsightsConnectionString string = appInsights.outputs.connectionString
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.outputs.name
output communicationServiceName string = communication.outputs.name
output emailServiceName string = email.outputs.name
