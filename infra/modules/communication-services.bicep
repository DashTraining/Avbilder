param name string
param location string = 'global'
param tags object = {}

resource comm 'Microsoft.Communication/communicationServices@2023-03-31' = {
  name: name
  location: location
  tags: tags
  properties: {
    dataLocation: 'Europe'
  }
}

output id string = comm.id
output name string = comm.name
