param zoneName string
param recordName string
param cnameTarget string
param ttl int = 300

resource zone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: zoneName
}

resource cname 'Microsoft.Network/dnsZones/CNAME@2018-05-01' = {
  name: recordName
  parent: zone
  properties: {
    TTL: ttl
    CNAMERecord: {
      cname: cnameTarget
    }
  }
}

output fqdn string = '${recordName}.${zoneName}'
