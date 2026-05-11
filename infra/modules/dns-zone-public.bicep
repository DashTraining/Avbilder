param zoneName string
param tags object = {}

resource zone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

output id string = zone.id
output name string = zone.name
output nameServers array = zone.properties.nameServers
