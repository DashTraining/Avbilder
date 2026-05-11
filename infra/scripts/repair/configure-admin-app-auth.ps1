[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$AdminAppServiceName,
    [string]$EntraAppDisplayName = 'Avbilder Admin Portal',
    [switch]$RotateSecret
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'AdminAppServiceName'
)

function Get-AzCliTsvValue {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $Description
    )

    $value = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query $Description."
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Azure CLI returned an empty value for $Description."
    }

    return ($value -join "`n").Trim()
}

$subscriptionId = Get-AzCliTsvValue `
    -Description 'active subscription id' `
    -Arguments @('account', 'show', '--only-show-errors', '--query', 'id', '--output', 'tsv')

$tenantId = Get-AzCliTsvValue `
    -Description 'active tenant id' `
    -Arguments @('account', 'show', '--only-show-errors', '--query', 'tenantId', '--output', 'tsv')

$defaultHostName = Get-AzCliTsvValue `
    -Description "default hostname for '$AdminAppServiceName'" `
    -Arguments @(
        'webapp', 'show',
        '--only-show-errors',
        '--resource-group', $ResourceGroupName,
        '--name', $AdminAppServiceName,
        '--query', 'defaultHostName',
        '--output', 'tsv'
    )

$appUrl = "https://$defaultHostName"
$callbackUrl = "$appUrl/.auth/login/aad/callback"

$clientId = az ad app list `
    --display-name $EntraAppDisplayName `
    --query '[0].appId' `
    --output tsv

if ([string]::IsNullOrWhiteSpace($clientId)) {
    $clientId = az ad app create `
        --display-name $EntraAppDisplayName `
        --sign-in-audience AzureADMyOrg `
        --web-redirect-uris $callbackUrl `
        --query appId `
        --output tsv
}
else {
    az ad app update `
        --id $clientId `
        --web-redirect-uris $callbackUrl | Out-Null
}

az ad app update `
    --id $clientId `
    --enable-id-token-issuance true | Out-Null

az ad sp create --id $clientId 2>$null | Out-Null

$authSecretSettingName = 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
$authSecretSettingExists = (az webapp config appsettings list `
    --name $AdminAppServiceName `
    --resource-group $ResourceGroupName `
    --query "[?name=='$authSecretSettingName'].name | [0]" `
    --output tsv)

if ($RotateSecret -or [string]::IsNullOrWhiteSpace($authSecretSettingExists)) {
    $secret = az ad app credential reset `
        --id $clientId `
        --append `
        --display-name 'app-service-auth' `
        --query password `
        --output tsv

    if ([string]::IsNullOrWhiteSpace($secret)) {
        throw "Azure CLI returned an empty client secret for '$EntraAppDisplayName'."
    }

    az webapp config appsettings set `
        --name $AdminAppServiceName `
        --resource-group $ResourceGroupName `
        --settings "$authSecretSettingName=$secret" | Out-Null
}

$authUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$AdminAppServiceName/config/authsettingsV2?api-version=2022-09-01"
$authBody = @{
    properties = @{
        platform = @{
            enabled = $true
            runtimeVersion = '~1'
        }
        globalValidation = @{
            requireAuthentication = $true
            unauthenticatedClientAction = 'RedirectToLoginPage'
            redirectToProvider = 'azureactivedirectory'
        }
        identityProviders = @{
            apple = @{
                enabled = $false
                registration = @{}
                login = @{}
            }
            azureActiveDirectory = @{
                enabled = $true
                registration = @{
                    clientId = $clientId
                    clientSecretSettingName = $authSecretSettingName
                    openIdIssuer = "https://login.microsoftonline.com/$tenantId/v2.0"
                }
                validation = @{
                    allowedAudiences = @(
                        $clientId
                        "api://$clientId"
                    )
                    defaultAuthorizationPolicy = @{
                        allowedPrincipals = @{}
                    }
                }
            }
            facebook = @{
                enabled = $false
                registration = @{}
                login = @{}
            }
            gitHub = @{
                enabled = $false
                registration = @{}
                login = @{}
            }
            google = @{
                enabled = $false
                registration = @{}
                login = @{}
                validation = @{}
            }
            legacyMicrosoftAccount = @{
                enabled = $false
                registration = @{}
                login = @{}
                validation = @{}
            }
            twitter = @{
                enabled = $false
                registration = @{}
            }
        }
        httpSettings = @{
            requireHttps = $true
            routes = @{
                apiPrefix = '/.auth'
            }
        }
        login = @{
            tokenStore = @{
                enabled = $true
            }
        }
    }
} | ConvertTo-Json -Depth 12

$authBodyPath = Join-Path ([System.IO.Path]::GetTempPath()) 'avbilder-admin-authsettings.json'
Set-Content `
    -LiteralPath $authBodyPath `
    -Value $authBody `
    -Encoding UTF8

az rest `
    --only-show-errors `
    --method put `
    --uri $authUri `
    --headers 'Content-Type=application/json' `
    --body "@$authBodyPath" | Out-Null

[pscustomObject]@{
    AdminAppServiceName = $AdminAppServiceName
    AdminUrl = $appUrl
    EntraAppDisplayName = $EntraAppDisplayName
    ClientId = $clientId
    CallbackUrl = $callbackUrl
    RotatedSecret = [bool]$RotateSecret
}
