# Demo-specific defaults for the Avbilder environment.
#
# Review these values before deploying.
# Many of them are globally unique or tied to the original demo domain and Azure resources.

$AvbilderDemoSettings = @{
    Location            = 'westeurope'
    DeploymentName      = 'avbilder-infra-weu'
    AdminDeploymentName = 'avbilder-admin-app-weu'
    ProjectShortName    = 'avbilder'

    ResourceGroupName         = 'rg-avbilder-weu'
    DataStorageAccountName    = 'stavbilderdataweu01'
    StaticWebAppName          = 'swa-avbilder-weu'
    AdminAppServiceName       = 'app-avbilder-admin-weu'
    AutomationAccountName     = 'aa-avbilder-ops-weu'
    ApplicationInsightsName   = 'appi-avbilder-weu'
    LogAnalyticsWorkspaceName = 'log-avbilder-weu'
    CommunicationServiceName  = 'acs-avbilder-weu'
    EmailServiceName          = 'email-avbilder-weu'
    KeyVaultName              = 'kv-avbilder-weu'
    DevOpsManagedIdentityName = 'id-avbilder-devops-weu'

    DomainName     = 'avbilder.no'
    CustomHostname = 'www.avbilder.no'

    SenderUsername    = 'studio'
    SenderDisplayName = 'Avbilder Studio'

    PreviewContainerName = 'previews'
}

$AvbilderDemoSettings.PublicBaseUrl = "https://$($AvbilderDemoSettings.CustomHostname)"

function Initialize-AvbilderDemoDefaults {
    param(
        [Parameter(Mandatory)] [hashtable] $BoundParameters,
        [Parameter(Mandatory)] [string[]] $Names,
        [hashtable] $Aliases = @{}
    )

    foreach ($name in $Names) {
        if ($BoundParameters.ContainsKey($name)) {
            continue
        }

        $settingName = if ($Aliases.ContainsKey($name)) { $Aliases[$name] } else { $name }
        if (-not $AvbilderDemoSettings.ContainsKey($settingName)) {
            continue
        }

        $currentValue = Get-Variable -Name $name -Scope 1 -ValueOnly -ErrorAction SilentlyContinue
        if ($null -eq $currentValue -or ($currentValue -is [string] -and [string]::IsNullOrWhiteSpace($currentValue))) {
            Set-Variable -Name $name -Value $AvbilderDemoSettings[$settingName] -Scope 1
        }
    }
}
