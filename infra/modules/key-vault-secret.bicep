param keyVaultName string
param secretName string
@secure()
param secretValue string

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: secretName
  parent: vault
  properties: {
    value: secretValue
  }
}

output name string = secret.name
