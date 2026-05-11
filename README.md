# Running a real business for free* on Azure services

Avbilder demo site built for the **Glasspaper Learning Inspirasjonsdagene 2026** conference, showcasing how to run a real business for free* on Azure services.

This package rebuilds the Avbilder conference-demo infrastructure around the low-cost architecture:

- Azure Static Web Apps Free tier with managed Azure Function API for the customer-facing website
- Azure App Service Free tier for the separate admin portal
- Azure DNS authoritative for the domain
- one storage account for data tables and private preview blobs
- Azure Communication Services Email for registration and preview-ready messages
- Application Insights basic telemetry
- Key Vault for values that are appropriate to demonstrate as secrets
- optional Azure Automation Account for scheduled preview cleanup demos

In the future, it can be supplemented with:

- Microsoft Entra External ID for customer sign-up/sign-in
- linked backend Function App and deployed Container Apps

Repository split:

```text
Avbilder/
├─ infra/       # Infrastructure: Bicep, setup/configuration scripts, runbooks
├─ site-user/   # Customer website: source and built static site output + SWA-managed .NET Functions API
└─ site-admin/  # Admin portal for registrations, users, calendar, and preview upload
```

Start with `docs/README.md`. The normal setup is split into base infrastructure (`infra/scripts/deploy-infra.ps1`) and post-infra service configuration (`infra/scripts/configure-demo-services.ps1`).

The `infra/scripts` folder contains only the normal entry-point scripts. One-off repair helpers live under `infra/scripts/repair`.

Core docs:

- `docs/architecture.md`
- `docs/setup.md`
- `docs/operations.md`
- `docs/diagnostics.md`
- `docs/future-ideas.md`
