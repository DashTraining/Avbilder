param zoneName string
param recordName string
param values array
param ttl int = 3600

resource zone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: zoneName
}

resource txt 'Microsoft.Network/dnsZones/TXT@2018-05-01' = {
  name: recordName
  parent: zone
  properties: {
    TTL: ttl
    TXTRecords: [
      for value in values: {
        value: [
          value
        ]
      }
    ]
  }
}

output fqdn string = '${recordName}.${zoneName}'
