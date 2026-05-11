[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path "$PSScriptRoot\..\..").Path,
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$DeploymentName,
    [string]$AdminAppServiceName,
    [string]$LogAnalyticsWorkspaceName,
    [string]$AdminAuthClientId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\avbilder-demo.settings.ps1')
Initialize-AvbilderDemoDefaults -BoundParameters $PSBoundParameters -Names @(
    'ResourceGroupName',
    'Location',
    'DeploymentName',
    'AdminAppServiceName',
    'LogAnalyticsWorkspaceName'
) -Aliases @{
    DeploymentName = 'AdminDeploymentName'
}

Set-Location $RootPath

$resourceGroupExists = az group exists `
    --name $ResourceGroupName `
    --output tsv

if ($resourceGroupExists -ne 'true') {
    throw "Resource group '$ResourceGroupName' does not exist. Run the base infrastructure deployment first."
}

az bicep build --file .\admin-app.bicep

$parameters = @(
    "location=$Location",
    "adminAppServiceName=$AdminAppServiceName",
    "logAnalyticsWorkspaceName=$LogAnalyticsWorkspaceName",
    "adminAuthClientId=$AdminAuthClientId"
)

az deployment group create `
    --name $DeploymentName `
    --resource-group $ResourceGroupName `
    --template-file .\admin-app.bicep `
    --parameters $parameters
