param name string
param location string = 'global'
param tags object = {}

resource email 'Microsoft.Communication/emailServices@2023-03-31' = {
  name: name
  location: location
  tags: tags
  properties: {
    dataLocation: 'Europe'
  }
}

output id string = email.id
output name string = email.name
