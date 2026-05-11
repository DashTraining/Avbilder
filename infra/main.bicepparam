using './main.bicep'

param location = 'westeurope'
param projectShortName = 'avbilder'
param dnsZoneName = 'avbilder.no'
param resourceGroupName = 'rg-avbilder-weu'
param staticWebAppSku = 'Free'
param createWwwCname = true
param createOidcSecretPlaceholder = false
param adminAuthClientId = ''
