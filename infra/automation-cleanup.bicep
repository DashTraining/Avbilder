targetScope = 'resourceGroup'

@description('Azure region for the Automation Account.')
param location string = resourceGroup().location

@description('Automation Account used for optional operations runbooks.')
param automationAccountName string = 'aa-avbilder-ops-weu'

@description('Data storage account that contains preview blobs and Avbilder tables.')
param dataStorageAccountName string = 'stavbilderdataweu01'

param tags object = {
  Project: 'avbilder'
  Workload: 'photographer-swa-demo'
  ManagedBy: 'Bicep'
}

var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

resource dataStorage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: dataStorageAccountName
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' existing = {
  name: 'default'
  parent: dataStorage
}

resource maintenanceLogTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  name: 'MaintenanceLog'
  parent: tableService
}

resource automation 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: true
    sku: {
      name: 'Basic'
    }
  }
}

resource blobDataRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataStorage.id, automation.id, storageBlobDataContributorRoleId)
  scope: dataStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: automation.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource tableDataRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataStorage.id, automation.id, storageTableDataContributorRoleId)
  scope: dataStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: automation.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output automationAccountName string = automation.name
output automationPrincipalId string = automation.identity.principalId
output dataStorageAccountName string = dataStorage.name
