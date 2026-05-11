# Avbilder infra scripts

The top-level scripts are the normal setup and operations entry points:

Demo-specific defaults such as resource group, domain, Static Web App, App Service, storage account, Key Vault, ACS, and Application Insights names live in `avbilder-demo.settings.ps1`. Change that file when adapting the scripts to a different environment. Explicit parameters still override those defaults.

| Script | Use |
|---|---|
| `deploy-infra.ps1` | Deploy the Bicep baseline. |
| `configure-demo-services.ps1` | Configure DNS records, app settings, ACS Email, admin auth, diagnostics, and admin allowlist. |
| `new-devops-managed-identity.ps1` | Create/update the Azure DevOps managed identity and federated credential. |
| `deploy-admin-app.ps1` | Publish and deploy the admin portal content. |
| `test-demo-configuration.ps1` | Check the live configuration. |
| `deploy-preview-cleanup-automation.ps1` | Optional Automation Account cleanup demo. Creates the weekly schedule by default. |

`repair/` contains smaller implementation and repair helpers. They are called by `configure-demo-services.ps1` and should not be needed in the normal demo path.
