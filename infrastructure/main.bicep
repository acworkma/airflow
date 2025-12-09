// Main Bicep template for Apache Airflow on Azure Kubernetes Service
// This orchestrates all infrastructure modules for the lab environment

targetScope = 'resourceGroup'

// Parameters
@description('Environment name (e.g., lab, dev, prod)')
param environmentName string = 'lab'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name prefix for all resources')
param resourcePrefix string = 'airflow'

@description('AKS node count')
@minValue(1)
@maxValue(10)
param aksNodeCount int = 2

@description('AKS node VM size')
param aksNodeVmSize string = 'Standard_D2s_v3'

@description('PostgreSQL administrator username')
param postgresAdminUsername string = 'airflowadmin'

@description('PostgreSQL administrator password')
@secure()
param postgresAdminPassword string

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Application: 'Apache Airflow'
  ManagedBy: 'Bicep'
}

// Variables
var resourceName = '${resourcePrefix}-${environmentName}'

// Module: Virtual Network
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    location: location
    vnetName: '${resourceName}-vnet'
    addressPrefix: '10.0.0.0/16'
    aksSubnetName: 'aks-subnet'
    aksSubnetPrefix: '10.0.1.0/24'
    databaseSubnetName: 'database-subnet'
    databaseSubnetPrefix: '10.0.2.0/24'
    tags: tags
  }
}

// Module: Log Analytics Workspace
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  params: {
    location: location
    workspaceName: '${resourceName}-logs'
    tags: tags
  }
}

// Module: Azure Container Registry
module acr 'modules/acr.bicep' = {
  name: 'acr-deployment'
  params: {
    location: location
    acrName: replace('${resourceName}-acr', '-', '')
    tags: tags
  }
}

// Module: AKS Cluster
module aks 'modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    location: location
    clusterName: '${resourceName}-aks'
    nodeCount: aksNodeCount
    nodeVmSize: aksNodeVmSize
    subnetId: vnet.outputs.aksSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

// Module: Azure Key Vault
module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    location: location
    keyVaultName: replace('${resourceName}-kv', '-', '')
    aksPrincipalId: aks.outputs.kubeletIdentityObjectId
    tags: tags
  }
}

// Module: PostgreSQL Flexible Server
module postgresql 'modules/postgresql.bicep' = {
  name: 'postgresql-deployment'
  params: {
    location: location
    serverName: '${resourceName}-postgres'
    administratorLogin: postgresAdminUsername
    administratorPassword: postgresAdminPassword
    databaseName: 'airflow'
    tags: tags
  }
}

// Module: Storage Account
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: replace('${resourceName}storage', '-', '')
    containerNames: [
      'airflow-logs'
    ]
    tags: tags
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output aksClusterName string = aks.outputs.clusterName
output aksIdentityPrincipalId string = aks.outputs.identityPrincipalId
output aksKubeletIdentityObjectId string = aks.outputs.kubeletIdentityObjectId
output acrName string = acr.outputs.acrName
output acrLoginServer string = acr.outputs.loginServer
output keyVaultName string = keyvault.outputs.keyVaultName
output keyVaultUri string = keyvault.outputs.keyVaultUri
output postgresServerName string = postgresql.outputs.serverName
output postgresFqdn string = postgresql.outputs.fqdn
output postgresDatabaseName string = postgresql.outputs.databaseName
output storageAccountName string = storage.outputs.storageAccountName
output storageAccountKey string = storage.outputs.storageAccountKey
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
