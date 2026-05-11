# Avbilder architecture

Avbilder is a conference-demo platform for a small photography business. It demonstrates how much can be launched on free and low-cost Azure services while staying realistic about limits.

## Architecture at a glance

```text
Customer browser
  |
  | HTTPS
  v
Azure Static Web Apps Free
  |-- static site: portfolio, sessions, registration, client portal
  |-- managed Functions: registrations, survey, client preview access
  |
  +--> Data Storage Account
  |      |-- Table Storage: metadata and workflow state
  |      |-- Blob Storage: private preview images
  |
  +--> Azure Communication Services Email
  +--> Application Insights

Azure App Service Free
  |-- admin portal: registrations, users, calendar, preview uploads
  |-- built-in Microsoft/Entra authentication
  |
  +--> Data Storage Account
  +--> Application Insights

Log Analytics
  |-- log-avbilder-weu for Application Insights, App Service, and ACS diagnostics

Azure DNS
  |-- avbilder.no zone
  |-- www CNAME -> SWA generated hostname
  |-- _dmarc TXT -> demo-safe DMARC policy

Azure Automation Account (optional)
  |-- aa-avbilder-ops-weu for scheduled preview cleanup
  |
  +--> Data Storage Account
        |-- preview blob/table cleanup access

Key Vault
  |-- swa-deployment-token for Azure DevOps SWA deployment

User-assigned managed identity
  |-- id-avbilder-devops-weu for Azure DevOps workload identity federation
```

## Repository layout

```text
Avbilder\
├─ infra\       # Infrastructure: Bicep, setup/configuration scripts, runbooks
├─ site-user\   # Customer website and SWA-managed .NET Functions API
└─ site-admin\  # Admin portal for registrations, users, calendar, and preview upload
```

## Design choices

- Static Web Apps Free keeps the customer site and managed Functions cheap. A standalone linked Function App would require SWA Standard.
- The admin portal is separate on App Service Free so the demo can show a clean customer/admin split and another free Azure tier.
- Registration and client portal are protected with built-in SWA auth, so registrations are tied to the signed-in customer email.
- Table scans are accepted for the small demo dataset. Production would add index tables for admin/calendar views.
- Preview uploads go through the App Service API in v1. Direct-to-Blob SAS upload is the v2 scale path.
- Event Grid is not deployed in v1 because SWA-managed Function endpoints exist only after app deployment. Preview publication is an explicit admin action instead.
- Key Vault stores the SWA deployment token. Runtime secrets remain SWA/App Service app settings in v1 because SWA-managed Functions do not provide the same clean Key Vault reference pattern as a standalone Function App.
- Azure Automation Account is optional and used for scheduled preview cleanup runbooks, demonstrating maintenance without adding frontend load to the core demo.
- DMARC starts with `p=none` so the demo improves email trust signals without rejecting mail.
- Container Apps is left for v2 image processing, watermarking, ZIP packaging, and AI tagging.

## Related docs

- [Setup](setup.md)
- [Operations](operations.md)
- [Diagnostics](diagnostics.md)
- [Future ideas](future-ideas.md)
