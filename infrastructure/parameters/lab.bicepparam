using '../main.bicep'

param environmentName = 'lab'
param resourcePrefix = 'airflow'
param aksNodeCount = 2
param aksNodeVmSize = 'Standard_D2s_v3'
param postgresAdminUsername = 'airflowadmin'
