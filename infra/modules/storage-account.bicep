param name string
param location string
param tags object = {}
param allowBlobPublicAccess bool = false
param skuName string = 'Standard_LRS'

resource account 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: allowBlobPublicAccess
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

output id string = account.id
output name string = account.name
output primaryBlobEndpoint string = account.properties.primaryEndpoints.blob
output primaryTableEndpoint string = account.properties.primaryEndpoints.table
