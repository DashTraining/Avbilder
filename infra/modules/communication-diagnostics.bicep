param communicationServiceName string
param workspaceResourceId string

resource communicationService 'Microsoft.Communication/communicationServices@2023-03-31' existing = {
  name: communicationServiceName
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'acs-email-logs'
  scope: communicationService
  properties: {
    workspaceId: workspaceResourceId
    logs: [
      {
        category: 'EmailSendMailOperational'
        enabled: true
      }
      {
        category: 'EmailStatusUpdateOperational'
        enabled: true
      }
      {
        category: 'EmailUserEngagementOperational'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Traffic'
        enabled: true
      }
    ]
  }
}

output name string = diagnostics.name
