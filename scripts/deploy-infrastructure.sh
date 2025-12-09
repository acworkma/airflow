#!/bin/bash
set -e

# Apache Airflow on AKS - Infrastructure Deployment Script
# This script deploys all required Azure infrastructure using Bicep templates

# Configuration
RESOURCE_GROUP="rg-airflow-lab"
LOCATION="canadacentral"
BICEP_FILE="infrastructure/main.bicep"
PARAMS_FILE="infrastructure/parameters/lab.bicepparam"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Apache Airflow on AKS - Infrastructure Deployment${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v az >/dev/null 2>&1 || { echo -e "${RED}Azure CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }

# Login check
echo -e "${YELLOW}Verifying Azure CLI login...${NC}"
az account show >/dev/null 2>&1 || { echo -e "${RED}Not logged in to Azure. Please run 'az login' first.${NC}" >&2; exit 1; }

# Display current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✓ Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})${NC}"
echo ""

# Generate PostgreSQL password
echo -e "${YELLOW}Generating secure PostgreSQL password...${NC}"
POSTGRES_PASSWORD=$(openssl rand -base64 32)
echo -e "${GREEN}✓ PostgreSQL password generated${NC}"
echo ""

# Create resource group
echo -e "${YELLOW}Creating/verifying resource group: ${RESOURCE_GROUP}...${NC}"
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none 2>/dev/null || true

echo -e "${GREEN}✓ Resource group ready${NC}"
echo ""

# Deploy Bicep template (incremental mode - only updates what changed)
echo -e "${YELLOW}Deploying Azure infrastructure (incremental deployment)...${NC}"
echo "  This will create new resources and update existing ones without deleting."
echo "  Estimated time: 10-15 minutes for full deployment, 2-5 minutes for updates."
echo ""
DEPLOYMENT_OUTPUT=$(az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${BICEP_FILE}" \
  --mode Incremental \
  --parameters environmentName=lab \
  --parameters resourcePrefix=airflow \
  --parameters aksNodeCount=2 \
  --parameters aksNodeVmSize=Standard_D2s_v3 \
  --parameters postgresAdminUsername=airflowadmin \
  --parameters postgresAdminPassword="${POSTGRES_PASSWORD}" \
  --query properties.outputs \
  --output json)

echo -e "${GREEN}✓ Infrastructure deployment completed${NC}"
echo ""

# Extract outputs
AKS_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.aksClusterName.value')
AKS_IDENTITY_PRINCIPAL_ID=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.aksIdentityPrincipalId.value')
AKS_KUBELET_IDENTITY_OBJECT_ID=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.aksKubeletIdentityObjectId.value')
ACR_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.acrName.value')
KV_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.keyVaultName.value')
POSTGRES_FQDN=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.postgresFqdn.value')
POSTGRES_DB=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.postgresDatabaseName.value')
STORAGE_ACCOUNT=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.storageAccountName.value')
STORAGE_KEY=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.storageAccountKey.value')

echo -e "${YELLOW}Configuring RBAC permissions...${NC}"

# Get ACR resource ID
ACR_ID=$(az acr show --name "${ACR_NAME}" --query id -o tsv)

# Grant AKS kubelet identity AcrPull role on ACR
echo "  - Granting AcrPull role to AKS..."
az role assignment create \
  --assignee "${AKS_KUBELET_IDENTITY_OBJECT_ID}" \
  --role "AcrPull" \
  --scope "${ACR_ID}" \
  --output none 2>/dev/null || echo "    (Role already exists - continuing)"

# Get Storage Account resource ID
STORAGE_ID=$(az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)

# Grant AKS kubelet identity Storage Blob Data Contributor role
echo "  - Granting Storage Blob Data Contributor role to AKS..."
az role assignment create \
  --assignee "${AKS_KUBELET_IDENTITY_OBJECT_ID}" \
  --role "Storage Blob Data Contributor" \
  --scope "${STORAGE_ID}" \
  --output none 2>/dev/null || echo "    (Role already exists - continuing)"

echo -e "${GREEN}✓ RBAC permissions configured${NC}"
echo ""

# Generate Airflow secrets
echo -e "${YELLOW}Generating Airflow secrets...${NC}"
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
WEBSERVER_SECRET=$(openssl rand -hex 32)
echo -e "${GREEN}✓ Airflow secrets generated${NC}"
echo ""

# Store secrets in Key Vault
echo -e "${YELLOW}Storing secrets in Key Vault...${NC}"

# PostgreSQL connection string
POSTGRES_CONN_STRING="postgresql+psycopg2://airflowadmin:${POSTGRES_PASSWORD}@${POSTGRES_FQDN}:5432/${POSTGRES_DB}?sslmode=require"
az keyvault secret set \
  --vault-name "${KV_NAME}" \
  --name "airflow-postgres-connection" \
  --value "${POSTGRES_CONN_STRING}" \
  --output none 2>/dev/null || echo "  Warning: Could not update postgres connection (may already exist)"

# Fernet key
az keyvault secret set \
  --vault-name "${KV_NAME}" \
  --name "airflow-fernet-key" \
  --value "${FERNET_KEY}" \
  --output none 2>/dev/null || echo "  Warning: Could not update fernet key (may already exist)"

# Webserver secret key
az keyvault secret set \
  --vault-name "${KV_NAME}" \
  --name "airflow-webserver-secret-key" \
  --value "${WEBSERVER_SECRET}" \
  --output none 2>/dev/null || echo "  Warning: Could not update webserver secret (may already exist)"

# Storage account name and key
az keyvault secret set \
  --vault-name "${KV_NAME}" \
  --name "storage-account-name" \
  --value "${STORAGE_ACCOUNT}" \
  --output none 2>/dev/null || echo "  Warning: Could not update storage account name (may already exist)"

az keyvault secret set \
  --vault-name "${KV_NAME}" \
  --name "storage-account-key" \
  --value "${STORAGE_KEY}" \
  --output none 2>/dev/null || echo "  Warning: Could not update storage account key (may already exist)"

echo -e "${GREEN}✓ Secrets stored in Key Vault${NC}"
echo ""

# Get AKS credentials
echo -e "${YELLOW}Configuring kubectl access to AKS cluster...${NC}"
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --overwrite-existing \
  --output none 2>/dev/null || echo "  Warning: Could not get AKS credentials"

echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# Summary
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Infrastructure Deployment Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Deployment Summary:${NC}"
echo "  Resource Group:        ${RESOURCE_GROUP}"
echo "  Location:              ${LOCATION}"
echo "  AKS Cluster:           ${AKS_NAME}"
echo "  Container Registry:    ${ACR_NAME}"
echo "  Key Vault:             ${KV_NAME}"
echo "  PostgreSQL Server:     ${POSTGRES_FQDN}"
echo "  Storage Account:       ${STORAGE_ACCOUNT}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Run the Airflow deployment script:"
echo "     ./scripts/deploy-airflow.sh"
echo ""
echo -e "${YELLOW}Note:${NC} All secrets have been stored in Azure Key Vault: ${KV_NAME}"
echo ""
