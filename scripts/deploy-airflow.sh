#!/bin/bash
set -e

# Apache Airflow on AKS - Airflow Deployment Script
# This script deploys Apache Airflow to the AKS cluster using Helm

# Configuration
RESOURCE_GROUP="rg-airflow-lab"
NAMESPACE="airflow"
HELM_RELEASE="airflow"
VALUES_FILE="kubernetes/airflow-values.yaml"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Apache Airflow on AKS - Airflow Deployment${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Helm is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v az >/dev/null 2>&1 || { echo -e "${RED}Azure CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }

# Verify kubectl connection
kubectl cluster-info >/dev/null 2>&1 || { echo -e "${RED}Cannot connect to Kubernetes cluster. Run deploy-infrastructure.sh first.${NC}" >&2; exit 1; }
echo -e "${GREEN}✓ Prerequisites checked${NC}"
echo ""

# Get deployment outputs
echo -e "${YELLOW}Retrieving deployment information...${NC}"
KV_NAME=$(az deployment group show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "keyvault-deployment" \
  --query properties.outputs.keyVaultName.value -o tsv)

STORAGE_ACCOUNT=$(az keyvault secret show \
  --vault-name "${KV_NAME}" \
  --name "storage-account-name" \
  --query value -o tsv)

echo -e "${GREEN}✓ Deployment information retrieved${NC}"
echo ""

# Create namespace
echo -e "${YELLOW}Creating Kubernetes namespace: ${NAMESPACE}...${NC}"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace created/verified${NC}"
echo ""

# Install Azure Key Vault Provider for Secrets Store CSI Driver
# Note: The driver is already enabled in AKS via addon
echo -e "${YELLOW}Verifying Azure Key Vault CSI driver...${NC}"
kubectl get csidriver secrets-store.csi.k8s.io >/dev/null 2>&1 || {
  echo -e "${RED}Secrets Store CSI driver not found. It should be enabled via AKS addon.${NC}"
  exit 1
}
echo -e "${GREEN}✓ CSI driver verified${NC}"
echo ""

# Get AKS managed identity client ID
echo -e "${YELLOW}Retrieving AKS managed identity...${NC}"
AKS_NAME=$(az deployment group show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "aks-deployment" \
  --query properties.outputs.clusterName.value -o tsv)

KUBELET_IDENTITY_CLIENT_ID=$(az aks show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --query identityProfile.kubeletidentity.clientId -o tsv)

echo -e "${GREEN}✓ Managed identity retrieved${NC}"
echo ""

# Get Key Vault and Tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)

# Create SecretProviderClass for Key Vault integration
echo -e "${YELLOW}Creating SecretProviderClass for Key Vault integration...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: airflow-kv-sync
  namespace: ${NAMESPACE}
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "${KUBELET_IDENTITY_CLIENT_ID}"
    keyvaultName: "${KV_NAME}"
    tenantId: "${TENANT_ID}"
    objects: |
      array:
        - |
          objectName: airflow-postgres-connection
          objectType: secret
          objectAlias: connection-string
        - |
          objectName: airflow-fernet-key
          objectType: secret
          objectAlias: fernet-key
        - |
          objectName: airflow-webserver-secret-key
          objectType: secret
          objectAlias: webserver-secret
        - |
          objectName: storage-account-name
          objectType: secret
          objectAlias: storage-name
        - |
          objectName: storage-account-key
          objectType: secret
          objectAlias: storage-key
  secretObjects:
    - secretName: airflow-secrets
      type: Opaque
      data:
        - objectName: connection-string
          key: connection
        - objectName: fernet-key
          key: fernet-key
        - objectName: webserver-secret
          key: webserver-secret-key
    - secretName: airflow-azure-storage
      type: Opaque
      data:
        - objectName: storage-name
          key: storage-account-name
        - objectName: storage-key
          key: storage-account-key
EOF

echo -e "${GREEN}✓ SecretProviderClass created${NC}"
echo ""

# Create Airflow connection secret for Azure Blob Storage
echo -e "${YELLOW}Creating Airflow Azure Blob connection...${NC}"
STORAGE_KEY=$(az keyvault secret show \
  --vault-name "${KV_NAME}" \
  --name "storage-account-key" \
  --query value -o tsv)

# Create connection string for Azure Blob (WASB)
WASB_CONN="wasb://${STORAGE_ACCOUNT}:${STORAGE_KEY}@"

kubectl create secret generic airflow-azure-blob-connection \
  --from-literal=connection="${WASB_CONN}" \
  --namespace "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Azure Blob connection secret created${NC}"
echo ""

# Create database secret
echo -e "${YELLOW}Creating database connection secret...${NC}"
POSTGRES_CONN=$(az keyvault secret show \
  --vault-name "${KV_NAME}" \
  --name "airflow-postgres-connection" \
  --query value -o tsv)

kubectl create secret generic airflow-postgresql \
  --from-literal=connection="${POSTGRES_CONN}" \
  --namespace "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Database secret created${NC}"
echo ""

# Add Apache Airflow Helm repository
echo -e "${YELLOW}Adding Apache Airflow Helm repository...${NC}"
helm repo add apache-airflow https://airflow.apache.org
helm repo update
echo -e "${GREEN}✓ Helm repository added${NC}"
echo ""

# Install/Upgrade Airflow
echo -e "${YELLOW}Installing Apache Airflow (this may take 5-10 minutes)...${NC}"

# Retrieve secrets from Key Vault
FERNET_KEY=$(az keyvault secret show \
  --vault-name "${KV_NAME}" \
  --name "airflow-fernet-key" \
  --query value -o tsv)

WEBSERVER_SECRET=$(az keyvault secret show \
  --vault-name "${KV_NAME}" \
  --name "airflow-webserver-secret-key" \
  --query value -o tsv)

STORAGE_NAME=$(az keyvault secret show \
  --vault-name "${KV_NAME}" \
  --name "storage-account-name" \
  --query value -o tsv)

# Install Airflow using the secret for database connection
helm upgrade --install "${HELM_RELEASE}" apache-airflow/airflow \
  --namespace "${NAMESPACE}" \
  --version 1.13.1 \
  --values "${VALUES_FILE}" \
  --set data.metadataSecretName="airflow-postgresql" \
  --set fernetKey="${FERNET_KEY}" \
  --set webserverSecretKey="${WEBSERVER_SECRET}" \
  --set-string env[3].name="AZURE_STORAGE_ACCOUNT_NAME" \
  --set-string env[3].value="${STORAGE_NAME}" \
  --set-string env[4].name="AZURE_STORAGE_ACCOUNT_KEY" \
  --set-string env[4].value="${STORAGE_KEY}" \
  --timeout 15m \
  --wait

echo -e "${GREEN}✓ Airflow installed${NC}"
echo ""

# Wait for LoadBalancer IP
echo -e "${YELLOW}Waiting for LoadBalancer IP assignment...${NC}"
echo "  (This may take a few minutes)"

EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  EXTERNAL_IP=$(kubectl get svc "${HELM_RELEASE}-webserver" \
    --namespace "${NAMESPACE}" \
    --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -z "$EXTERNAL_IP" ] && sleep 10
done

echo -e "${GREEN}✓ LoadBalancer IP assigned${NC}"
echo ""

# Create admin user if it doesn't exist
echo -e "${YELLOW}Creating admin user...${NC}"
WEBSERVER_POD=$(kubectl get pods -n "${NAMESPACE}" -l component=webserver -o jsonpath='{.items[0].metadata.name}')

# Check if user exists
USER_EXISTS=$(kubectl exec -n "${NAMESPACE}" "${WEBSERVER_POD}" -- airflow users list 2>/dev/null | grep -c "^admin" || true)

if [ "$USER_EXISTS" -eq 0 ]; then
  echo "  Creating admin user..."
  kubectl exec -n "${NAMESPACE}" "${WEBSERVER_POD}" -- airflow users create \
    --username admin \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password admin >/dev/null 2>&1
  echo -e "${GREEN}✓ Admin user created${NC}"
else
  echo -e "${GREEN}✓ Admin user already exists${NC}"
fi
echo ""

# Summary
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Airflow Deployment Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Access Information:${NC}"
echo "  Airflow UI URL:        http://${EXTERNAL_IP}:8080"
echo "  Username:              admin"
echo "  Password:              admin"
echo "  Namespace:             ${NAMESPACE}"
echo ""
echo -e "${YELLOW}Verify Installation:${NC}"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get svc -n ${NAMESPACE}"
echo ""
echo -e "${YELLOW}View Logs:${NC}"
echo "  kubectl logs -n ${NAMESPACE} -l component=webserver --tail=100"
echo "  kubectl logs -n ${NAMESPACE} -l component=scheduler --tail=100"
echo ""
echo -e "${YELLOW}Note:${NC} DAGs will be automatically synced from GitHub repository every 60 seconds"
echo "      Repository: https://github.com/acworkma/airflow (dags/ folder)"
echo ""
echo -e "${GREEN}Ready to use Apache Airflow!${NC}"
echo ""
