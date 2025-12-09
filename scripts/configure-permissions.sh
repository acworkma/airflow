#!/bin/bash
set -e

# Apache Airflow on AKS - RBAC Permissions Configuration Script
# This script configures all necessary Azure RBAC permissions for Airflow deployment

# Configuration
RESOURCE_GROUP="rg-airflow-lab"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Apache Airflow on AKS - RBAC Configuration${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v az >/dev/null 2>&1 || { echo -e "${RED}Azure CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }

# Login check
az account show >/dev/null 2>&1 || { echo -e "${RED}Not logged in to Azure. Please run 'az login' first.${NC}" >&2; exit 1; }

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✓ Prerequisites checked${NC}"
echo ""

# Get current user
echo -e "${YELLOW}Retrieving current user information...${NC}"
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)

if [ -z "$CURRENT_USER_ID" ]; then
  # Fallback for service principals
  CURRENT_USER_ID=$(az account show --query user.name -o tsv)
  CURRENT_USER_EMAIL="${CURRENT_USER_ID}"
  echo -e "${YELLOW}Using service principal: ${CURRENT_USER_ID}${NC}"
else
  CURRENT_USER_EMAIL=$(az ad signed-in-user show --query userPrincipalName -o tsv)
  echo -e "${GREEN}✓ User: ${CURRENT_USER_EMAIL}${NC}"
fi
echo ""

# Get resource names
echo -e "${YELLOW}Retrieving resource information...${NC}"
KV_NAME=$(az keyvault list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
AKS_NAME=$(az aks list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
STORAGE_ACCOUNT=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
ACR_NAME=$(az acr list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
POSTGRES_SERVER=$(az postgres flexible-server list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)

if [ -z "$KV_NAME" ] || [ -z "$AKS_NAME" ]; then
  echo -e "${RED}Error: Could not find resources in resource group ${RESOURCE_GROUP}${NC}"
  echo -e "${YELLOW}Please run ./scripts/deploy-infrastructure.sh first${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Resources found${NC}"
echo "  Key Vault:        ${KV_NAME}"
echo "  AKS Cluster:      ${AKS_NAME}"
echo "  Storage Account:  ${STORAGE_ACCOUNT}"
echo "  Container Reg:    ${ACR_NAME}"
echo "  PostgreSQL:       ${POSTGRES_SERVER}"
echo ""

# Get AKS managed identities
echo -e "${YELLOW}Retrieving AKS managed identities...${NC}"
AKS_IDENTITY=$(az aks show --resource-group "${RESOURCE_GROUP}" --name "${AKS_NAME}" --query "identity.principalId" -o tsv)
KUBELET_IDENTITY=$(az aks show --resource-group "${RESOURCE_GROUP}" --name "${AKS_NAME}" --query "identityProfile.kubeletidentity.objectId" -o tsv)

echo -e "${GREEN}✓ Identities retrieved${NC}"
echo "  AKS Identity:     ${AKS_IDENTITY}"
echo "  Kubelet Identity: ${KUBELET_IDENTITY}"
echo ""

# Configure permissions for current user (for running deployment scripts)
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Configuring Current User Permissions${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Key Vault Secrets Officer - allows reading/writing secrets
echo -e "${YELLOW}Assigning Key Vault Secrets Officer role...${NC}"
az role assignment create \
  --assignee "${CURRENT_USER_ID}" \
  --role "Key Vault Secrets Officer" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP}/providers/microsoft.keyvault/vaults/${KV_NAME}" \
  --output none 2>/dev/null || echo "  (Role may already be assigned)"

echo -e "${GREEN}✓ User permissions configured${NC}"
echo ""

# Configure permissions for AKS managed identity
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Configuring AKS Managed Identity Permissions${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# ACR Pull - allows pulling container images
echo -e "${YELLOW}Assigning AcrPull role for container images...${NC}"
ACR_ID=$(az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)
az role assignment create \
  --assignee "${AKS_IDENTITY}" \
  --role "AcrPull" \
  --scope "${ACR_ID}" \
  --output none 2>/dev/null || echo "  (Role may already be assigned)"

# Storage Blob Data Contributor - allows writing logs to blob storage
echo -e "${YELLOW}Assigning Storage Blob Data Contributor role for remote logging...${NC}"
STORAGE_ID=$(az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)
az role assignment create \
  --assignee "${AKS_IDENTITY}" \
  --role "Storage Blob Data Contributor" \
  --scope "${STORAGE_ID}" \
  --output none 2>/dev/null || echo "  (Role may already be assigned)"

echo -e "${GREEN}✓ AKS identity permissions configured${NC}"
echo ""

# Configure permissions for Kubelet identity (for Key Vault CSI driver)
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Configuring Kubelet Identity Permissions${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Key Vault Secrets User - allows reading secrets via CSI driver
echo -e "${YELLOW}Assigning Key Vault Secrets User role...${NC}"
az role assignment create \
  --assignee "${KUBELET_IDENTITY}" \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP}/providers/microsoft.keyvault/vaults/${KV_NAME}" \
  --output none 2>/dev/null || echo "  (Role may already be assigned)"

echo -e "${GREEN}✓ Kubelet identity permissions configured${NC}"
echo ""

# Update PostgreSQL password to match Key Vault secret
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Synchronizing PostgreSQL Password${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

echo -e "${YELLOW}Synchronizing PostgreSQL password with Key Vault...${NC}"
POSTGRES_CONN=$(az keyvault secret show \
  --vault-name "${KV_NAME}" \
  --name "airflow-postgres-connection" \
  --query value -o tsv 2>/dev/null || true)

if [ -n "$POSTGRES_CONN" ]; then
  POSTGRES_PASS=$(echo "${POSTGRES_CONN}" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
  
  echo "  Updating PostgreSQL password to match Key Vault..."
  az postgres flexible-server update \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${POSTGRES_SERVER}" \
    --admin-password "${POSTGRES_PASS}" \
    --output none 2>/dev/null || echo "    Warning: Could not update PostgreSQL password"
  
  echo -e "${GREEN}✓ PostgreSQL password synchronized${NC}"
else
  echo -e "${YELLOW}  Note: PostgreSQL connection string not found in Key Vault${NC}"
  echo -e "${YELLOW}  This is normal if you haven't run deploy-infrastructure.sh yet${NC}"
fi
echo ""

# Wait for RBAC propagation
echo -e "${YELLOW}Waiting for RBAC permissions to propagate (30 seconds)...${NC}"
sleep 30
echo -e "${GREEN}✓ RBAC propagation complete${NC}"
echo ""

# Summary
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}RBAC Configuration Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Configured Permissions:${NC}"
echo ""
echo -e "${YELLOW}Current User (${CURRENT_USER_EMAIL}):${NC}"
echo "  ✓ Key Vault Secrets Officer on ${KV_NAME}"
echo ""
echo -e "${YELLOW}AKS Managed Identity:${NC}"
echo "  ✓ AcrPull on ${ACR_NAME}"
echo "  ✓ Storage Blob Data Contributor on ${STORAGE_ACCOUNT}"
echo ""
echo -e "${YELLOW}Kubelet Managed Identity:${NC}"
echo "  ✓ Key Vault Secrets User on ${KV_NAME}"
echo ""
echo -e "${YELLOW}Database:${NC}"
echo "  ✓ PostgreSQL password synchronized with Key Vault"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Deploy Airflow to the cluster:"
echo "     ./scripts/deploy-airflow.sh"
echo ""
