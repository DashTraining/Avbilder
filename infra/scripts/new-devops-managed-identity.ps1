[CmdletBinding()]
param(
    [string]$IdentityName,
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$KeyVaultName,
    [string]$FederatedCredentialName = 'fic-azure-devops-sc-avbilder-azure',
    [string]$FederatedCredentialIssuer,
    [string]$FederatedCredentialSubject,
    [switch]$AssignSubscriptionContributor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'IdentityName',
    'ResourceGroupName',
    'Location',
    'KeyVaultName'
) -Aliases @{
    IdentityName = 'DevOpsManagedIdentityName'
}

function Ensure-RoleAssignment {
    param(
        [Parameter(Mandatory)] [string]$PrincipalId,
        [Parameter(Mandatory)] [string]$RoleName,
        [Parameter(Mandatory)] [string]$Scope
    )

    $existing = az role assignment list `
        --assignee $PrincipalId `
        --role $RoleName `
        --scope $Scope `
        --query '[0].id' `
        --output tsv

    if ([string]::IsNullOrWhiteSpace($existing)) {
        az role assignment create `
            --assignee-object-id $PrincipalId `
            --assignee-principal-type ServicePrincipal `
            --role $RoleName `
            --scope $Scope | Out-Null
    }
}

$subscriptionId = az account show --query id --output tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'No active Azure subscription was found. Run az login and az account set first.'
}

$resourceGroupExists = az group exists --name $ResourceGroupName --output tsv
if ($resourceGroupExists -ne 'true') {
    az group create `
        --name $ResourceGroupName `
        --location $Location | Out-Null
}

$identity = az identity list `
    --resource-group $ResourceGroupName `
    --query "[?name=='$IdentityName'] | [0].{id:id, clientId:clientId, principalId:principalId, tenantId:tenantId}" `
    --output json | ConvertFrom-Json

if (-not $identity) {
    $identity = az identity create `
        --name $IdentityName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --query '{id:id, clientId:clientId, principalId:principalId, tenantId:tenantId}' `
        --output json | ConvertFrom-Json
}

if ($FederatedCredentialIssuer -and $FederatedCredentialSubject) {
    $existingFederatedCredential = az identity federated-credential list `
        --identity-name $IdentityName `
        --resource-group $ResourceGroupName `
        --query "[?name=='$FederatedCredentialName'].name | [0]" `
        --output tsv

    if ([string]::IsNullOrWhiteSpace($existingFederatedCredential)) {
        az identity federated-credential create `
            --name $FederatedCredentialName `
            --identity-name $IdentityName `
            --resource-group $ResourceGroupName `
            --issuer $FederatedCredentialIssuer `
            --subject $FederatedCredentialSubject `
            --audiences 'api://AzureADTokenExchange' | Out-Null
    }
}
elseif ($FederatedCredentialIssuer -or $FederatedCredentialSubject) {
    throw 'Provide both FederatedCredentialIssuer and FederatedCredentialSubject, or neither.'
}

$vaultId = az keyvault show `
    --name $KeyVaultName `
    --resource-group $ResourceGroupName `
    --query id `
    --output tsv

Ensure-RoleAssignment `
    -PrincipalId $identity.principalId `
    -RoleName 'Key Vault Secrets User' `
    -Scope $vaultId

if ($AssignSubscriptionContributor) {
    Ensure-RoleAssignment `
        -PrincipalId $identity.principalId `
        -RoleName 'Contributor' `
        -Scope "/subscriptions/$subscriptionId"
}

[pscustomobject]@{
    IdentityName = $IdentityName
    ResourceGroupName = $ResourceGroupName
    SubscriptionId = $subscriptionId
    TenantId = $identity.tenantId
    ClientId = $identity.clientId
    PrincipalId = $identity.principalId
    KeyVaultName = $KeyVaultName
    KeyVaultRole = 'Key Vault Secrets User'
    SubscriptionContributorAssigned = [bool]$AssignSubscriptionContributor
    FederatedCredentialConfigured = [bool]($FederatedCredentialIssuer -and $FederatedCredentialSubject)
}
