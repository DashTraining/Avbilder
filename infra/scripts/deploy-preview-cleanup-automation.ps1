#Requires -Modules Az.Accounts, Az.Resources, Az.Automation

[CmdletBinding()]
param(
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$AutomationAccountName,
    [string]$DataStorageAccountName,
    [string]$PreviewContainerName,
    [string]$RunbookName  = 'Cleanup-ExpiredPreviews',
    [string]$ScheduleName = 'weekly-preview-cleanup',
    [int]$RetentionDays   = 90,
    [bool]$DryRun         = $true,
    [switch]$EnableSchedule,
    [switch]$SkipSchedule,
    [datetime]$ScheduleStartUtc = ([datetime]::UtcNow.Date.AddDays(1).AddHours(3))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'Location',
    'AutomationAccountName',
    'DataStorageAccountName',
    'PreviewContainerName'
)

$scriptRoot   = Split-Path -Parent $PSScriptRoot
$templateFile = Join-Path $scriptRoot 'automation-cleanup.bicep'
$runbookPath  = Join-Path $scriptRoot 'automation\Cleanup-ExpiredPreviews.ps1'

if (-not (Test-Path -LiteralPath $runbookPath)) {
    throw "Runbook source was not found at '$runbookPath'."
}

$context = Get-AzContext
if ($null -eq $context) {
    throw 'No active Azure PowerShell context was found. Run Connect-AzAccount and Select-AzSubscription first.'
}

if ($EnableSchedule -and $SkipSchedule) {
    throw 'Use either -EnableSchedule or -SkipSchedule, not both.'
}

$createSchedule = -not $SkipSchedule

$templateParameters = @{
    location = $Location
    automationAccountName = $AutomationAccountName
    dataStorageAccountName = $DataStorageAccountName
}

New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -Name 'avbilder-preview-cleanup-automation' `
    -TemplateFile $templateFile `
    -TemplateParameterObject $templateParameters | Out-Null

Import-AzAutomationRunbook `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -Name $RunbookName `
    -Path $runbookPath `
    -Type PowerShell72 `
    -Description 'Deletes expired preview blobs, clears PreviewSets, marks registrations PreviewExpired, and writes MaintenanceLog audit rows.' `
    -LogProgress $true `
    -LogVerbose $true `
    -Force `
    -Published | Out-Null

if ($createSchedule) {
    $schedule = Get-AzAutomationSchedule `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Name $ScheduleName `
        -ErrorAction SilentlyContinue

    if ($null -eq $schedule) {
        Write-Host "Creating weekly Automation schedule '$ScheduleName'."
        New-AzAutomationSchedule `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Name $ScheduleName `
            -Description 'Weekly Avbilder preview cleanup schedule.' `
            -StartTime $ScheduleStartUtc.ToUniversalTime() `
            -WeekInterval 1 `
            -DaysOfWeek $ScheduleStartUtc.DayOfWeek `
            -TimeZone 'UTC' | Out-Null
    }
    else {
        Write-Host "Automation schedule '$ScheduleName' already exists."
    }

    $existingLink = Get-AzAutomationScheduledRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -RunbookName $RunbookName `
        -ScheduleName $ScheduleName `
        -ErrorAction SilentlyContinue

    if ($null -ne $existingLink) {
        Unregister-AzAutomationScheduledRunbook `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -RunbookName $RunbookName `
            -ScheduleName $ScheduleName `
            -Force | Out-Null
    }

    Write-Host "Linking runbook '$RunbookName' to schedule '$ScheduleName'."
    Register-AzAutomationScheduledRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -RunbookName $RunbookName `
        -ScheduleName $ScheduleName `
        -Parameters @{
            StorageAccountName = $DataStorageAccountName
            ContainerName      = $PreviewContainerName
            RetentionDays      = $RetentionDays
            DryRun             = $DryRun
            CleanOrphans       = $true
        } | Out-Null

    $linkedSchedule = Get-AzAutomationScheduledRunbook `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -RunbookName $RunbookName `
        -ScheduleName $ScheduleName `
        -ErrorAction Stop

    if ($null -eq $linkedSchedule) {
        throw "Schedule '$ScheduleName' was not linked to runbook '$RunbookName'."
    }
}

[pscustomobject]@{
    AutomationAccountName = $AutomationAccountName
    RunbookName           = $RunbookName
    RunbookPublished      = $true
    ScheduleEnabled       = [bool]$createSchedule
    ScheduleName          = if ($createSchedule) { $ScheduleName } else { '' }
    RetentionDays         = $RetentionDays
    DryRun                = $DryRun
}
