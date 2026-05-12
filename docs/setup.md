# Avbilder Setup

Use this guide for first-time setup or rebuilding the demo environment. Use PowerShell 7+ and Azure CLI.

## Before you deploy

- Confirm you can create resources and role assignments in the target Azure subscription.
- Install PowerShell 7+, the Az PowerShell module, PowerShell 'Hyde' module and prerequisites (or use Jekyll), Azure CLI, BICEP, .NET 8 SDK, Azure Functions Core Tools, and the Azure CLI Bicep extension.
- Review `infra/scripts/avbilder-demo.settings.ps1`; it lists the resource names and domain values that are specific to the original demo environment.
- Choose unique resource names if you are not using the default Avbilder demo names. Also update `infra/main.bicepparam` for Bicep-managed names such as `projectShortName`, `dnsZoneName`, and `resourceGroupName`.
- In script settings, `DomainName` is also used as the DNS zone name. `PublicBaseUrl` is derived from `CustomHostname` as `https://<custom-hostname>`.
- Use a DNS domain you control if you want the custom `www` hostname and ACS Email verification to work.
- Expect ACS Email domain verification and DNS delegation to take time; those are normal manual checkpoints.

## Script map

The normal workflow uses only these top-level scripts:

| Script | Use |
|---|---|
| `deploy-infra.ps1` | Deploy Bicep-managed baseline infrastructure. |
| `configure-demo-services.ps1` | Configure DNS records, app settings, ACS Email, admin auth, diagnostics, and admin allowlist. |
| `new-devops-managed-identity.ps1` | Create/update the Azure DevOps managed identity and federated credential. |
| `deploy-admin-app.ps1` | Publish and deploy the admin portal app content. |
| `test-demo-configuration.ps1` | Check service configuration after setup. |
| `deploy-preview-cleanup-automation.ps1` | Optional Automation Account cleanup demo. Creates the weekly schedule by default. |

Special-purpose repair scripts live in `infra/scripts/repair` and are not part of the normal demo setup path.

Demo-specific script defaults live in:

```text
infra/scripts/avbilder-demo.settings.ps1
```

Change that file when adapting the scripts to a different workshop environment. Explicit script parameters still win over the shared defaults.

## 1. Sign in

```powershell
az login
az account set --subscription "<subscription-id-or-name>"
az account show --output table
```

## 2. Deploy infrastructure

```powershell
Set-Location <drive>:\Avbilder\infra
.\scripts\deploy-infra.ps1
```

This deploys the Azure resource group, Static Web App, admin App Service, storage, tables, preview container, Key Vault, Application Insights, Log Analytics, Azure DNS, ACS, ACS Email, DMARC TXT record, and ACS diagnostics.

If the base infrastructure already exists and you only need the admin App Service pieces:

```powershell
.\scripts\repair\deploy-admin-infra.ps1
```

## 3. Manual: delegate DNS

Azure can create the DNS zone and records, but the registrar must delegate `avbilder.no`. At the registrar, set `avbilder.no` to use the Azure DNS name servers shown by the script.

```powershell
az network dns zone show `
  --resource-group rg-avbilder-weu `
  --name avbilder.no `
  --query nameServers `
  --output table
```

## 4. Configure services

Run the post-deployment configuration:

```powershell
.\scripts\configure-demo-services.ps1 `
  -AdminEmail "<admin-email>"
```

This configures:

- Azure DNS `www` and `_dmarc` records
- ACS Email sender `studio@avbilder.no`
- SWA managed API settings
- Admin App Service settings
- Admin App Service built-in authentication
- Admin diagnostics
- `AdminAllowlist`

After DNS delegation has propagated, bind the custom domain:

```powershell
.\scripts\configure-demo-services.ps1 `
  -AdminEmail "<admin-email>" `
  -BindCustomDomain
```

If the `avbilder.no` ACS Email domain does not exist yet:

```powershell
.\scripts\configure-demo-services.ps1 `
  -AdminEmail "<admin-email>" `
  -CreateEmailDomain
```

Then complete ACS DNS verification in Azure and rerun without `-CreateEmailDomain`.

## 5. Manual: Azure DevOps connection and variable group

Create or reuse the managed identity:

```powershell
.\scripts\new-devops-managed-identity.ps1
```

In Azure DevOps, create a service connection:

```text
Name: sc-avbilder-azure
Type: Azure Resource Manager
Auth: Managed identity, manual, workload identity federation
```

Use the Tenant ID and Client ID printed by the script. Save the service connection as a draft, copy `Issuer` and `Subject identifier`, then run:

```powershell
.\scripts\new-devops-managed-identity.ps1 `
  -FederatedCredentialIssuer "<issuer from draft service connection>" `
  -FederatedCredentialSubject "<subject identifier from draft service connection>"
```

Return to Azure DevOps and verify/save the service connection.

Create a Library variable group:

```text
Name: avbilder-secrets
Link Key Vault: kv-avbilder-weu
Selected secret: swa-deployment-token
```

The SWA deployment token can be copied from:

```powershell
az staticwebapp secrets list `
  --name swa-avbilder-weu `
  --resource-group rg-avbilder-weu
```

Store it in Key Vault:

```powershell
az keyvault secret set `
  --vault-name kv-avbilder-weu `
  --name swa-deployment-token `
  --value "<apiKey value>"
```

For an infrastructure pipeline, give the managed identity subscription `Contributor`:

```powershell
.\scripts\new-devops-managed-identity.ps1 -AssignSubscriptionContributor
```

## 6. Build and deploy customer site/API

When this workshop package is shared from the top-level GitHub repository, `site-user` is included as normal files, not as an embedded Git repository. Before using Azure DevOps deployment, create or attach a separate Azure DevOps repo for `site-user`:

```powershell
Set-Location <drive>:\Avbilder\site-user
git init
git add .
git commit -m "Initial site-user deployment source"
git branch -M main
git remote add origin "<your Azure DevOps site-user repo URL>"
git push -u origin main
```

If you already have a `site-user` DevOps repo (like from a previous demo build) and want to maintain its old history, fetch it without overwriting the local files:

```powershell
git remote add origin "<your Azure DevOps site-user repo URL>"
git fetch origin
```

The customer site is designed to be built with Jekyll, a popular static site builder. But that requires Ruby. I created a PowerShell module that performs the same task but only has a few prerequisites which are all internal to PowerShell. You will need:

* https://www.powershellgallery.com/packages/powershell-yaml/
* https://www.powershellgallery.com/packages/PowerLiquid/
* https://www.powershellgallery.com/packages/Hyde/

After installing those modules, build the static site locally with my Hyde PowerShell module:

```powershell
Set-Location <drive>:\Avbilder\site-user
.\scripts\build-site.ps1
```

(or use Jekyll, if you already have access to it)

Deploy with:

```text
site-user/azure-pipelines.yml
```

The pipeline expects:

- static output already generated in `site-user/site`
- managed Functions source in `site-user/api/Avbilder.Api`
- variable group `avbilder-secrets`
- Key Vault secret `swa-deployment-token`

## 7. Deploy admin portal

Deployment using a zip upload directly to the App Service:

```powershell
Set-Location <drive>:\Avbilder\infra
.\scripts\deploy-admin-app.ps1
```

Optionally, you can create a DevOps Pipeline deployment. If you decide to create a repo for this, you can use this definition:

```text
site-admin/azure-pipelines.yml
```

## 8. Verify

```powershell
Set-Location <drive>:\Avbilder\infra
.\scripts\test-demo-configuration.ps1
```

Expected:

- SWA and admin app have data storage and ACS settings.
- Admin auth is enabled.
- ACS Email domain/SPF/DKIM/DMARC are verified.
- Admin App Service auth platform is enabled.

Browser checks (based on the demo naming):

```text
https://www.avbilder.no
https://app-avbilder-admin-weu.azurewebsites.net
```

## Related docs

- [Architecture](architecture.md)
- [Operations](operations.md)
- [Diagnostics](diagnostics.md)
- [Future ideas](future-ideas.md)
