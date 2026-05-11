targetScope = 'resourceGroup'

@description('Short project name used in alert names and tags.')
param projectShortName string = 'avbilder'

@description('Application Insights component name.')
param applicationInsightsName string = 'appi-avbilder-weu'

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string = 'log-avbilder-weu'

@description('Admin App Service name.')
param adminAppServiceName string = 'app-avbilder-admin-weu'

@description('Data storage account name.')
param dataStorageAccountName string = 'stavbilderdataweu01'

@description('Enable the alert rules. Set false if you only want them visible as disabled demo rules.')
param alertsEnabled bool = true

@description('Optional action group resource IDs. Leave empty for portal-only demo rules.')
param actionGroupResourceIds array = []

@description('Admin App Service CPU-time warning threshold in seconds per hour. Free plans have tight daily CPU quotas, so this is deliberately low for the demo.')
param adminCpuTimeSecondsPerHourWarning int = 600

@description('Admin App Service request-count warning threshold per hour.')
param adminRequestsPerHourWarning int = 200

@description('Application Insights request-count warning threshold per hour.')
param appInsightsRequestsPerHourWarning int = 250

@description('Preview Blob capacity warning threshold in bytes. This is a demo budget, not an Azure free-tier limit.')
param previewBlobCapacityBytesWarning int = 52428800

@description('Log Analytics billable ingestion warning threshold in MB over 24 hours. This is a demo budget.')
param logAnalyticsBillableMbPerDayWarning int = 25

var tags = {
  Project: projectShortName
  Demo: 'monitoring'
  ManagedBy: 'Bicep'
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource adminApp 'Microsoft.Web/sites@2022-09-01' existing = {
  name: adminAppServiceName
}

resource dataStorage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: dataStorageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' existing = {
  parent: dataStorage
  name: 'default'
}

resource adminCpuTime 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${projectShortName}-demo-admin-cpu-time'
  location: 'global'
  tags: tags
  properties: {
    description: 'Demo guardrail: admin App Service CPU time is high for a Free-plan workload.'
    severity: 3
    enabled: alertsEnabled
    scopes: [
      adminApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT1H'
    autoMitigate: true
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: resourceGroup().location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CpuTime'
          metricName: 'CpuTime'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          threshold: adminCpuTimeSecondsPerHourWarning
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [for actionGroupResourceId in actionGroupResourceIds: {
      actionGroupId: actionGroupResourceId
    }]
  }
}

resource adminRequestVolume 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${projectShortName}-demo-admin-request-volume'
  location: 'global'
  tags: tags
  properties: {
    description: 'Demo guardrail: admin App Service request volume is noisy for a small Free-plan back office.'
    severity: 3
    enabled: alertsEnabled
    scopes: [
      adminApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT1H'
    autoMitigate: true
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: resourceGroup().location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Requests'
          metricName: 'Requests'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          threshold: adminRequestsPerHourWarning
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [for actionGroupResourceId in actionGroupResourceIds: {
      actionGroupId: actionGroupResourceId
    }]
  }
}

resource appInsightsRequestVolume 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${projectShortName}-demo-appi-request-volume'
  location: 'global'
  tags: tags
  properties: {
    description: 'Demo guardrail: Application Insights request telemetry volume is getting noisy.'
    severity: 3
    enabled: alertsEnabled
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT1H'
    autoMitigate: true
    targetResourceType: 'Microsoft.Insights/components'
    targetResourceRegion: resourceGroup().location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RequestCount'
          metricName: 'requests/count'
          metricNamespace: 'Microsoft.Insights/components'
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          threshold: appInsightsRequestsPerHourWarning
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [for actionGroupResourceId in actionGroupResourceIds: {
      actionGroupId: actionGroupResourceId
    }]
  }
}

resource previewBlobCapacity 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${projectShortName}-demo-preview-blob-capacity'
  location: 'global'
  tags: tags
  properties: {
    description: 'Demo guardrail: private preview Blob capacity crossed the small demo budget.'
    severity: 3
    enabled: alertsEnabled
    scopes: [
      blobService.id
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    autoMitigate: true
    targetResourceType: 'Microsoft.Storage/storageAccounts/blobServices'
    targetResourceRegion: resourceGroup().location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'BlobCapacity'
          metricName: 'BlobCapacity'
          metricNamespace: 'Microsoft.Storage/storageAccounts/blobServices'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          threshold: previewBlobCapacityBytesWarning
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [for actionGroupResourceId in actionGroupResourceIds: {
      actionGroupId: actionGroupResourceId
    }]
  }
}

resource logAnalyticsUsage 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: '${projectShortName}-demo-log-ingestion-budget'
  location: resourceGroup().location
  tags: tags
  properties: {
    displayName: '${projectShortName} demo Log Analytics ingestion budget'
    description: 'Demo guardrail: billable Log Analytics ingestion crossed the small daily demo budget.'
    severity: 3
    enabled: alertsEnabled
    scopes: [
      workspace.id
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'P1D'
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: '''
Usage
| where TimeGenerated > ago(24h)
| where tostring(IsBillable) =~ "true"
| summarize BillableMB = sum(Quantity)
'''
          timeAggregation: 'Total'
          metricMeasureColumn: 'BillableMB'
          operator: 'GreaterThan'
          threshold: logAnalyticsBillableMbPerDayWarning
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: actionGroupResourceIds
    }
  }
}

output alertRuleNames array = [
  adminCpuTime.name
  adminRequestVolume.name
  appInsightsRequestVolume.name
  previewBlobCapacity.name
  logAnalyticsUsage.name
]
