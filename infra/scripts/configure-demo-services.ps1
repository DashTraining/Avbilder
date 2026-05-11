[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$AdminEmail,
    [string]$DataStorageAccountName,
    [string]$StaticWebAppName,
    [string]$AdminAppServiceName,
    [string]$ApplicationInsightsName,
    [string]$CommunicationServiceName,
    [string]$EmailServiceName,
    [string]$DomainName,
    [string]$CustomHostname,
    [string]$SenderUsername,
    [string]$SenderDisplayName,
    [switch]$CreateEmailDomain,
    [switch]$BindCustomDomain,
    [switch]$SkipAdminAuth,
    [switch]$SkipDnsRecords,
    [switch]$SkipAcsSender
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'DataStorageAccountName',
    'StaticWebAppName',
    'AdminAppServiceName',
    'ApplicationInsightsName',
    'CommunicationServiceName',
    'EmailServiceName',
    'DomainName',
    'CustomHostname',
    'SenderUsername',
    'SenderDisplayName'
)

function Invoke-Step {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock
    )

    Write-Host ""
    Write-Host "== $Name =="
    & $ScriptBlock
}

$scriptRoot = $PSScriptRoot
$repairScriptRoot = Join-Path $scriptRoot 'repair'

if (-not $SkipDnsRecords) {
    Invoke-Step 'Configure Azure DNS records' {
        & (Join-Path $repairScriptRoot 'set-dns-records.ps1') `
            -ResourceGroupName $ResourceGroupName `
            -ZoneName $DomainName `
            -StaticWebAppName $StaticWebAppName
    }
}

if (-not $SkipAcsSender) {
    Invoke-Step 'Configure ACS Email domain, sender, and SWA sender setting' {
        $senderArgs = @{
            ResourceGroupName = $ResourceGroupName
            CommunicationServiceName = $CommunicationServiceName
            EmailServiceName = $EmailServiceName
            DomainName = $DomainName
            StaticWebAppName = $StaticWebAppName
            SenderUsername = $SenderUsername
            DisplayName = $SenderDisplayName
        }

        if ($CreateEmailDomain) {
            $senderArgs.CreateDomain = $true
        }

        & (Join-Path $repairScriptRoot 'set-acs-email-sender.ps1') @senderArgs
    }
}

Invoke-Step 'Configure Static Web Apps managed API settings' {
    & (Join-Path $repairScriptRoot 'set-swa-settings.ps1') `
        -ResourceGroupName $ResourceGroupName `
        -StaticWebAppName $StaticWebAppName `
        -DataStorageAccountName $DataStorageAccountName `
        -ApplicationInsightsName $ApplicationInsightsName `
        -CommunicationServiceName $CommunicationServiceName `
        -AcsEmailSender "$SenderUsername@$DomainName"
}

Invoke-Step 'Configure Admin App Service settings' {
    & (Join-Path $repairScriptRoot 'set-admin-app-settings.ps1') `
        -ResourceGroupName $ResourceGroupName `
        -AdminAppServiceName $AdminAppServiceName `
        -DataStorageAccountName $DataStorageAccountName `
        -ApplicationInsightsName $ApplicationInsightsName `
        -CommunicationServiceName $CommunicationServiceName `
        -AcsEmailSender "$SenderUsername@$DomainName"
}

if (-not $SkipAdminAuth) {
    Invoke-Step 'Configure Admin App Service built-in authentication' {
        & (Join-Path $repairScriptRoot 'configure-admin-app-auth.ps1') `
            -ResourceGroupName $ResourceGroupName `
            -AdminAppServiceName $AdminAppServiceName
    }
}

Invoke-Step 'Ensure Admin App Service diagnostics' {
    & (Join-Path $repairScriptRoot 'enable-admin-auth-diagnostics.ps1') `
        -ResourceGroupName $ResourceGroupName `
        -AdminAppServiceName $AdminAppServiceName
}

if (-not [string]::IsNullOrWhiteSpace($AdminEmail)) {
    Invoke-Step 'Seed admin allowlist' {
        & (Join-Path $repairScriptRoot 'seed-admin-allowlist.ps1') `
            -DataStorageAccountName $DataStorageAccountName `
            -AdminEmail $AdminEmail
    }
}

if ($BindCustomDomain) {
    Invoke-Step 'Bind custom hostname to Static Web Apps' {
        & (Join-Path $repairScriptRoot 'add-swa-custom-domain.ps1') `
            -ResourceGroupName $ResourceGroupName `
            -StaticWebAppName $StaticWebAppName `
            -Hostname $CustomHostname
    }
}

[pscustomobject]@{
    ResourceGroupName = $ResourceGroupName
    StaticWebAppName = $StaticWebAppName
    AdminAppServiceName = $AdminAppServiceName
    SenderAddress = "$SenderUsername@$DomainName"
    AdminEmailSeeded = -not [string]::IsNullOrWhiteSpace($AdminEmail)
    CustomDomainBindingAttempted = [bool]$BindCustomDomain
}
