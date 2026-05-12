# Avbilder Operations

Use this guide after the environment is set up. First-time deployment is in [setup.md](setup.md); architecture notes are in [architecture.md](architecture.md).

## Demo user flow

1. Open the user portal at <https://www.avbilder.no/register/>.
2. Sign in when redirected.
3. Register a photography session.
4. Open <https://www.avbilder.no/portal/>.
5. Confirm the registration appears with `Needs Approval` and `Previews not ready`.
6. After the photography session, return to the client portal and confirm preview status is ready.
7. Open previews and download.

## Demo admin flow

1. Open the admin portal at <https://app-avbilder-admin-weu.azurewebsites.net>.
2. Approve or change the session date and check the ACS email status notification.
3. PHOTOGRAPHY SESSION TAKES PLACE
4. Upload JPEG previews with drag-and-drop.

## Admin operations

The admin portal:

- uses App Service built-in Microsoft/Entra authentication
- checks `AdminAllowlist`
- shows registrations, users, and preferred-date calendar entries
- approves or changes session dates
- sends ACS Email notifications
- uploads JPEG previews through App Service
- deletes registrations plus related survey/preview metadata and blobs
- deletes customer profile rows

For this demo, admin list views use table scans because the demo dataset is small. Production would add index tables.

## JPEG upload script

The script `infra/repair/upload-preview-set.ps1` remains as a fallback to upload preview JPEGs when the admin portal is unavailable.

## Repair scripts

A number of lower-level repair tools live under `infra/scripts/repair` and are called by `configure-demo-services.ps1` when needed. Use them directly only when repairing one specific subsystem.

## Related docs

- [Architecture](architecture.md)
- [Setup](setup.md)
- [Diagnostics](diagnostics.md)
- [Future ideas](future-ideas.md)
