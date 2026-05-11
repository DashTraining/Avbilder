# Avbilder user site

This repository contains:

- `site_source/` — Jekyll source for the public website and portal pages.
- `site/` — generated static output to be deployed to Azure Static Web Apps. Build this locally and commit it.
- `api/Avbilder.Api/` — .NET 8 isolated Azure Functions for SWA managed APIs.
- `azure-pipelines.yml` - Azure DevOps deployment pipeline definition
- `scripts/build-site.ps1` - local Hyde build helper
- `scripts/serve-site.ps1` - simple local static preview server

The current low-cost architecture uses Static Web Apps Free with managed Functions.

Build the static site locally before committing:

```powershell
.\scripts\build-site.ps1
```

Preview locally:

```powershell
.\scripts\serve-site.ps1 -Port 4173
```

Setup is documented in `../docs/setup.md`; day-to-day deployment and demo operations are in `../docs/operations.md`.
