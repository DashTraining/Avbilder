# Log Queries

## Query 1: Solution Status

Heartbeat chart across App Insights, App Service, ACS Email, and Storage Blob/Table metrics. The values are normalized per signal so small-but-important events do not disappear behind storage transaction counts. Run this after a registration, admin approval, and preview upload.

```kusto
let lookback = 6h;
let step = 5m;
let adminApp = "app-avbilder-admin-weu";
let storageAccount = "stavbilderdataweu01";
let pulse =
union isfuzzy=true
(
    AppRequests
    | where TimeGenerated > ago(lookback)
    | summarize Raw = count() by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "Customer/API requests", Value = todouble(Raw)
),
(
    AppServiceHTTPLogs
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) contains adminApp
        or tostring(column_ifexists("Resource", "")) contains adminApp
    | summarize Raw = count() by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "Admin HTTP", Value = todouble(Raw)
),
(
    AppServiceAuthenticationLogs
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) contains adminApp
        or tostring(column_ifexists("Resource", "")) contains adminApp
    | summarize Raw = count() by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "Admin auth", Value = todouble(Raw)
),
(
    AppServicePlatformLogs
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) contains adminApp
        or tostring(column_ifexists("Resource", "")) contains adminApp
    | summarize Raw = count() by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "Admin platform", Value = todouble(Raw)
),
(
    ACSEmailSendMailOperational
    | where TimeGenerated > ago(lookback)
    | summarize Raw = count() by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "ACS send mail", Value = todouble(Raw)
),
(
    ACSEmailStatusUpdateOperational
    | where TimeGenerated > ago(lookback)
    | summarize Raw = count() by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "ACS delivery status", Value = todouble(Raw)
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | extend ResourceName = tolower(tostring(column_ifexists("Resource", ""))),
        ResourcePath = tolower(strcat(tostring(column_ifexists("_ResourceId", "")), " ", tostring(column_ifexists("ResourceId", ""))))
    | where ResourceName == storageAccount or ResourcePath contains storageAccount
    | where MetricName == "Transactions"
    | where ResourcePath contains "/blobservices/"
    | summarize Raw = sum(todouble(Total)) by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "Blob transactions", Value = todouble(Raw)
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | extend ResourceName = tolower(tostring(column_ifexists("Resource", ""))),
        ResourcePath = tolower(strcat(tostring(column_ifexists("_ResourceId", "")), " ", tostring(column_ifexists("ResourceId", ""))))
    | where ResourceName == storageAccount or ResourcePath contains storageAccount
    | where MetricName == "Transactions"
    | where ResourcePath contains "/tableservices/"
    | summarize Raw = sum(todouble(Total)) by TimeGenerated = bin(TimeGenerated, step)
    | project TimeGenerated, Signal = "Table transactions", Value = todouble(Raw)
);
pulse
| summarize Raw = sum(Value) by TimeGenerated, Signal
| join kind=inner (
    pulse
    | summarize Raw = sum(Value) by TimeGenerated, Signal
    | summarize MaxRaw = max(Raw) by Signal
) on Signal
| extend Pulse = iff(MaxRaw == 0, 0.0, round(100.0 * Raw / MaxRaw, 1))
| project TimeGenerated, Signal, Pulse
| order by TimeGenerated asc
| render timechart with (title = "SOLUTION STATUS")
```

## Query 2: Free Limit Usage

This is the “are we still comfortably inside the free limits?” graph. Every row uses a documented Azure service limit. Some rows are measured from telemetry; the Static Web Apps inventory rows are set manually because those subscription/app quota counts are not emitted as Log Analytics metrics.

```kusto
let lookback = 24h;
let monthLookback = 31d;
let adminApp = "app-avbilder-admin-weu";
let storageAccount = "stavbilderdataweu01";
let oneGiB = 1024.0 * 1024.0 * 1024.0;
let oneMiB = 1024.0 * 1024.0;
let onePiB = 1024.0 * 1024.0 * 1024.0 * 1024.0 * 1024.0;
let appServiceCpuMinutesPerDayLimit = 60.0;
let appServiceCpuShortMinutesPer5mLimit = 3.0;
let appServiceStorageBytesLimit = oneGiB;
let appServiceBandwidthBytesPerDayLimit = 165.0 * oneMiB;
let staticWebAppsFreeAppsPerSubscriptionLimit = 10.0;
let staticWebAppsFreeCustomDomainsLimit = 2.0;
let staticWebAppsFreeMonthlyBandwidthBytesLimit = 100.0 * oneGiB;
let storageAccountCapacityBytesLimit = 5.0 * onePiB;
let storageAccountRequestsPerSecondLimitWestEurope = 40000.0;
let automationNewJobsPer30SecondsLimit = 100.0;
let acsCustomDomainSendPerMinuteLimit = 30.0;
let acsCustomDomainSendPerHourLimit = 100.0;
union isfuzzy=true
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) contains adminApp
        or tostring(column_ifexists("Resource", "")) contains adminApp
    | where MetricName == "CpuTime"
    | summarize Used = sum(todouble(Total)) / 60.0
    | project Guardrail = "REAL LIMIT - App Service Free CPU/day", Used = todouble(Used), Limit = appServiceCpuMinutesPerDayLimit, Unit = "minutes/day"
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) contains adminApp
        or tostring(column_ifexists("Resource", "")) contains adminApp
    | where MetricName == "CpuTime"
    | summarize Used = sum(todouble(Total)) / 60.0 by bin(TimeGenerated, 5m)
    | summarize Used = max(Used)
    | project Guardrail = "REAL LIMIT - App Service Free CPU/5 min", Used = todouble(Used), Limit = appServiceCpuShortMinutesPer5mLimit, Unit = "minutes/5 min"
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) contains adminApp
        or tostring(column_ifexists("Resource", "")) contains adminApp
    | where MetricName in ("FileSystemUsage", "FileSystemUsageBytes")
    | summarize Used = max(todouble(coalesce(Average, Total)))
    | project Guardrail = "REAL LIMIT - App Service Free filesystem", Used = todouble(Used), Limit = appServiceStorageBytesLimit, Unit = "bytes"
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) contains adminApp
        or tostring(column_ifexists("Resource", "")) contains adminApp
    | where MetricName in ("BytesSent", "IoBytesSent")
    | summarize Used = sum(todouble(Total))
    | project Guardrail = "REAL LIMIT - App Service Free outbound/day", Used = todouble(Used), Limit = appServiceBandwidthBytesPerDayLimit, Unit = "bytes/day"
),
(
    datatable(Used:real, Limit:real, Unit:string, Guardrail:string)
    [
        1.0, 10.0, "apps/subscription", "REAL LIMIT - Static Web Apps Free apps",
        1.0, 2.0, "custom domains/app", "REAL LIMIT - Static Web Apps Free custom domains"
    ]
    | project Guardrail, Used = todouble(Used), Limit = todouble(Limit), Unit
),
(
    AzureMetrics
    | where TimeGenerated > ago(monthLookback)
    | where MetricName in ("Bandwidth", "DataOut")
    | where tostring(column_ifexists("_ResourceId", "")) has "staticSites"
    | summarize Used = sum(todouble(Total))
    | project Guardrail = "REAL LIMIT - Static Web Apps Free bandwidth/month", Used = todouble(Used), Limit = staticWebAppsFreeMonthlyBandwidthBytesLimit, Unit = "bytes/month"
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | extend ResourceName = tolower(tostring(column_ifexists("Resource", ""))),
        ResourcePath = tolower(strcat(tostring(column_ifexists("_ResourceId", "")), " ", tostring(column_ifexists("ResourceId", ""))))
    | where ResourceName == storageAccount or ResourcePath contains storageAccount
    | where MetricName == "BlobCapacity"
    | summarize Used = max(todouble(Average))
    | project Guardrail = "REAL LIMIT - Storage account capacity", Used = todouble(Used), Limit = storageAccountCapacityBytesLimit, Unit = "bytes"
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | extend ResourceName = tolower(tostring(column_ifexists("Resource", ""))),
        ResourcePath = tolower(strcat(tostring(column_ifexists("_ResourceId", "")), " ", tostring(column_ifexists("ResourceId", ""))))
    | where ResourceName == storageAccount or ResourcePath contains storageAccount
    | where MetricName == "Transactions"
    | summarize Used = sum(todouble(Total)) by bin(TimeGenerated, 1m)
    | summarize Used = max(Used) / 60.0
    | project Guardrail = "REAL LIMIT - Storage account request rate", Used = todouble(Used), Limit = storageAccountRequestsPerSecondLimitWestEurope, Unit = "requests/second"
),
(
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | where tostring(column_ifexists("_ResourceId", "")) has "Microsoft.Automation/automationAccounts"
    | where MetricName in ("TotalJob", "TotalJobs", "Jobs")
    | summarize Used = sum(todouble(Total)) by bin(TimeGenerated, 30s)
    | summarize Used = max(Used)
    | project Guardrail = "REAL LIMIT - Automation new jobs/30 sec", Used = todouble(Used), Limit = automationNewJobsPer30SecondsLimit, Unit = "jobs/30 sec"
),
(
    ACSEmailSendMailOperational
    | where TimeGenerated > ago(lookback)
    | summarize Used = todouble(count()) by bin(TimeGenerated, 1m)
    | summarize Used = max(Used)
    | project Guardrail = "REAL LIMIT - ACS Email custom domain send/min", Used = todouble(Used), Limit = acsCustomDomainSendPerMinuteLimit, Unit = "emails/min"
),
(
    ACSEmailSendMailOperational
    | where TimeGenerated > ago(lookback)
    | summarize Used = todouble(count()) by bin(TimeGenerated, 1h)
    | summarize Used = max(Used)
    | project Guardrail = "REAL LIMIT - ACS Email custom domain send/hour", Used = todouble(Used), Limit = acsCustomDomainSendPerHourLimit, Unit = "emails/hour"
)
| summarize Used = sum(Used), Limit = max(Limit), Unit = take_any(Unit) by Guardrail
| where isnotnull(Used) and isnotnull(Limit) and Limit > 0
| extend PercentOfLimit = round(100.0 * Used / Limit, 4)
| project Guardrail, PercentOfLimit, Used = round(Used, 2), Limit = round(Limit, 2), Unit
| order by PercentOfLimit desc
| render barchart with (title = "FREE LIMIT USAGE")
```

Official limit references used for Query 2:

- [Static Web Apps quotas](https://learn.microsoft.com/en-us/azure/static-web-apps/quotas)
- [App Service limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-app-service-limits)
- [Azure Storage scalability targets](https://learn.microsoft.com/en-us/azure/storage/common/scalability-targets-standard-account)
- [Azure Automation limits and quotas](https://learn.microsoft.com/en-us/azure/automation/automation-subscription-limits-faq)
- [Azure Communication Services service limits](https://learn.microsoft.com/en-us/azure/communication-services/concepts/service-limits#rate-limits-for-email)
