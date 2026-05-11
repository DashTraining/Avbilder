param name string
param location string
param tags object = {}
param workspaceResourceId string = ''

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    IngestionMode: 'ApplicationInsights'
    WorkspaceResourceId: empty(workspaceResourceId) ? null : workspaceResourceId
  }
}

output id string = appi.id
output name string = appi.name
output instrumentationKey string = appi.properties.InstrumentationKey
output connectionString string = appi.properties.ConnectionString
