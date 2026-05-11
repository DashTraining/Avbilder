# Avbilder Future Ideas

These ideas are intentionally outside the demo baseline. They could be useful when planning upgrade paths, operational maturity, and what would change for production.

## Application upgrades

- Upgrade to SWA Standard.
- Add Entra External ID for customer sign-up.
- Move to a linked backend Function App.
- Switch admin preview upload to direct-to-Blob.
- Add Event Grid for blob-created events.
- Add Container Apps for image resizing, watermarking, ZIP packaging.
- Add RAW photo archival and a fuller gallery management system.
- Add apex-domain redirect.

## Automation Account demo

Storage lifecycle management is the simplest way to delete old preview blobs. Use Automation Account when you want to schedule cleanup with business logic.

Deploy the optional Automation Account and publish the runbook:

```powershell
Connect-AzAccount
Set-Location <drive>:\Avbilder\infra
.\scripts\deploy-preview-cleanup-automation.ps1
```

The account running this command needs permission to create role assignments on the data storage account, such as `Owner` or `User Access Administrator`.

By default, the runbook is published and attached to a weekly dry-run schedule named `weekly-preview-cleanup`. To publish the runbook without a schedule:

```powershell
.\scripts\deploy-preview-cleanup-automation.ps1 `
  -SkipSchedule
```

Switch `-DryRun $false` only when you want the scheduled job to delete data. Re-running the script updates the runbook schedule parameters.

The runbook:

- deletes preview blobs under `previews/reg/` older than the retention window
- removes `PreviewSets` rows when no blobs remain for a registration
- marks registrations as `PreviewExpired`
- cleans old orphan preview blobs where the registration no longer exists
- writes an audit row to `MaintenanceLog`

## Related docs

- [Architecture](architecture.md)
- [Setup](setup.md)
- [Operations](operations.md)
- [Diagnostics](diagnostics.md)
