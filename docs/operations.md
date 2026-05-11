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

## User site deployment

The top-level GitHub package treats `site-user` as normal files. Azure DevOps deployment still expects `site-user` to be its own Git repository, so initialize it or connect it to your own DevOps repo before creating the pipeline:

```powershell
Set-Location <drive>:\Avbilder\site-user
git init
git add .
git commit -m "Initial site-user deployment source"
git branch -M main
git remote add origin "<your Azure DevOps site-user repo URL>"
git push -u origin main
```

Build the static site locally:

```powershell
Set-Location <drive>:\Avbilder\site-user
.\scripts\build-site.ps1
```

Deploy with Azure DevOps:

- sync the Repository
- use `site-user/azure-pipelines.yml` for Pipeline configuration

The pipeline expects:

- static output already generated in `site-user/site`
- managed Functions source in `site-user/api/Avbilder.Api`
- variable group `avbilder-secrets`
- Key Vault secret `swa-deployment-token`

## Admin portal deployment

Local deployment:

```powershell
Set-Location <drive>:\Avbilder\infra
.\scripts\deploy-admin-app.ps1
```

Pipeline deployment (not used in this demo):

```text
site-admin/azure-pipelines.yml
```

## Health check

```powershell
Set-Location <drive>:\Avbilder\infra
.\scripts\test-demo-configuration.ps1
```

Expected:

- SWA and admin app have data storage and ACS settings.
- Admin auth is enabled.
- ACS Email domain/SPF/DKIM/DMARC are verified.
- Admin App Service auth platform is enabled.

Browser checks:

```text
https://www.avbilder.no
https://www.avbilder.no/register/
https://www.avbilder.no/portal/
https://app-avbilder-admin-weu.azurewebsites.net
```

## Repair scripts

The normal setup uses only the top-level scripts in `infra/scripts`. Lower-level repair tools live under `infra/scripts/repair` and are called by `configure-demo-services.ps1` when needed. Use them directly only when repairing one specific subsystem.

The legacy `repair/upload-preview-set.ps1` remains as a fallback to upload preview JPEGs when the admin portal is unavailable.

## Related docs

- [Architecture](architecture.md)
- [Setup](setup.md)
- [Diagnostics](diagnostics.md)
- [Future ideas](future-ideas.md)
