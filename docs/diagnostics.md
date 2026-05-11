# Avbilder Diagnostics

Use this guide when the demo is deployed but something is not behaving correctly.

## Observability resources

Application Insights and App Service diagnostics use:

```text
rg-avbilder-weu / log-avbilder-weu
```

ACS Email logs use resource-specific tables:

```kusto
ACSEmailSendMailOperational
| where TimeGenerated > ago(24h)
| order by TimeGenerated desc
```

```kusto
ACSEmailStatusUpdateOperational
| where TimeGenerated > ago(24h)
| order by TimeGenerated desc
```

The app also writes email attempts to the `NotificationLog` table. Check that first when email behavior is unclear.

For a demo-friendly monitoring flow, KQL queries, and alert rules, see [Monitoring demo pack](monitoring-demo.md).

## Admin authentication

If admin auth fails, open:

```text
https://app-avbilder-admin-weu.azurewebsites.net/.auth/me
```

Seed the exact signed-in email shown there:

```powershell
.\scripts\repair\seed-admin-allowlist.ps1 `
  -DataStorageAccountName stavbilderdataweu01 `
  -AdminEmail "<admin-email>"
```

To force a new admin auth client secret:

```powershell
.\scripts\repair\configure-admin-app-auth.ps1 -RotateSecret
```

Then sign out or use a private browser session:

```text
https://app-avbilder-admin-weu.azurewebsites.net/.auth/logout
```

## Related docs

- [Architecture](architecture.md)
- [Setup](setup.md)
- [Operations](operations.md)
- [Future ideas](future-ideas.md)
