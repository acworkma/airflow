# Apache Airflow on Azure Kubernetes Service (AKS) - Lab Guide

## Overview

This lab demonstrates how to deploy and run Apache Airflow on Azure Kubernetes Service (AKS) using infrastructure-as-code (Bicep) and Helm. The deployment uses the KubernetesExecutor for dynamic task execution and integrates with Azure services including PostgreSQL, Key Vault, and Blob Storage.

## Architecture

- **AKS Cluster**: Public Kubernetes cluster with Azure CNI networking
- **Executor**: KubernetesExecutor (each task runs in its own pod)
- **Database**: Azure PostgreSQL Flexible Server (metadata storage)
- **Storage**: Azure Blob Storage (logs via WASB)
- **DAGs**: Synced from GitHub repository using git-sync sidecar
- **Secrets**: Managed via Azure Key Vault with CSI driver integration
- **Monitoring**: Azure Log Analytics and Container Insights

## Prerequisites

Before starting this lab, ensure you have:

1. **Azure Subscription** with appropriate permissions to create resources
2. **Azure CLI** (version 2.50.0 or later)
   ```bash
   az --version
   az login
   ```
3. **kubectl** (Kubernetes command-line tool)
   ```bash
   kubectl version --client
   ```
4. **Helm 3** (Kubernetes package manager)
   ```bash
   helm version
   ```
5. **Git** (for cloning and managing the repository)
6. **OpenSSL** (for generating secrets)
7. **Python 3** (for Fernet key generation)
   ```bash
   pip install cryptography
   ```

## Lab Structure

```
airflow/
├── infrastructure/           # Bicep templates for Azure resources
│   ├── main.bicep           # Main orchestration template
│   ├── modules/             # Modular Bicep files
│   └── parameters/          # Environment-specific parameters
├── kubernetes/              # Kubernetes configurations
│   └── airflow-values.yaml  # Helm chart values
├── scripts/                 # Deployment scripts
│   ├── deploy-infrastructure.sh
│   └── deploy-airflow.sh
├── dags/                    # Airflow DAGs (synced to cluster)
│   ├── example_bash_python.py
│   └── example_kubernetes_pod.py
└── LAB-GUIDE.md            # This file
```

## Cost Estimate

Running this lab will incur Azure costs. Estimated monthly cost: **$150-$200 USD**

Breakdown:
- AKS cluster (2 x Standard_D2s_v3 nodes): ~$140/month
- PostgreSQL Flexible Server (Burstable B1ms): ~$15/month
- Azure Storage (Standard LRS): ~$5/month
- Container Registry (Basic): ~$5/month
- Key Vault: ~$1/month
- Log Analytics: ~$5-10/month (depending on ingestion)

**Cost Optimization Tips**:
- Stop/deallocate the AKS cluster when not in use
- Delete the resource group after completing the lab
- Use Azure Cost Management to monitor spending

## Step-by-Step Deployment

### Step 1: Clone the Repository

```bash
git clone https://github.com/acworkma/airflow.git
cd airflow
```

### Step 2: Review Configuration

Review and customize the parameter file if needed:

```bash
cat infrastructure/parameters/lab.bicepparam
```

Key parameters:
- `environmentName`: Environment identifier (default: `lab`)
- `resourcePrefix`: Prefix for resource names (default: `airflow`)
- `aksNodeCount`: Number of AKS nodes (default: `2`)
- `aksNodeVmSize`: VM size for nodes (default: `Standard_D2s_v3`)

### Step 3: Deploy Azure Infrastructure

Make the deployment script executable and run it:

```bash
chmod +x scripts/deploy-infrastructure.sh
./scripts/deploy-infrastructure.sh
```

This script will:
1. Create a resource group (`rg-airflow-lab`)
2. Deploy all Azure resources using Bicep templates (10-15 minutes)
3. Configure RBAC permissions for AKS managed identity
4. Generate Airflow secrets (Fernet key, webserver secret)
5. Store all secrets in Azure Key Vault
6. Configure kubectl to access the AKS cluster

**Expected Output**:
```
================================================
Infrastructure Deployment Complete!
================================================

Deployment Summary:
  Resource Group:        rg-airflow-lab
  Location:              eastus
  AKS Cluster:           airflow-lab-aks
  Container Registry:    airflowlabacr
  Key Vault:             airflowlabkv
  PostgreSQL Server:     airflow-lab-postgres.postgres.database.azure.com
  Storage Account:       airflowlabstorage
```

### Step 4: Deploy Apache Airflow

Make the Airflow deployment script executable and run it:

```bash
chmod +x scripts/deploy-airflow.sh
./scripts/deploy-airflow.sh
```

This script will:
1. Verify prerequisites and cluster connectivity
2. Create the `airflow` namespace
3. Configure Azure Key Vault CSI driver integration
4. Create Kubernetes secrets from Key Vault
5. Add Apache Airflow Helm repository
6. Install Airflow with custom configuration (5-10 minutes)
7. Wait for LoadBalancer IP assignment

**Expected Output**:
```
================================================
Airflow Deployment Complete!
================================================

Access Information:
  Airflow UI URL:        http://20.XXX.XXX.XXX:8080
  Default Username:      admin
  Default Password:      admin
  Namespace:             airflow
```

### Step 5: Verify Deployment

Check that all pods are running:

```bash
kubectl get pods -n airflow
```

Expected pods:
- `airflow-scheduler-*` (2 replicas)
- `airflow-webserver-*` (2 replicas)
- `airflow-triggerer-*` (1 replica)
- `airflow-statsd-*` (1 replica)

Check services:

```bash
kubectl get svc -n airflow
```

Look for the `airflow-webserver` service with an `EXTERNAL-IP`.

### Step 6: Access the Airflow UI

1. Get the LoadBalancer IP:
   ```bash
   kubectl get svc airflow-webserver -n airflow -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. Open your browser and navigate to:
   ```
   http://<EXTERNAL-IP>:8080
   ```

3. Login with default credentials:
   - **Username**: `admin`
   - **Password**: `admin`

> **Security Note**: Change the default password in production by modifying the `kubernetes/airflow-values.yaml` file and upgrading the Helm release.

### Step 7: Verify Git-Sync DAG Synchronization

The DAGs are automatically synchronized from the GitHub repository every 60 seconds.

1. In the Airflow UI, you should see two DAGs:
   - `example_bash_python`
   - `example_kubernetes_pod`

2. Check git-sync logs to verify synchronization:
   ```bash
   kubectl logs -n airflow -l component=scheduler -c git-sync --tail=50
   ```

3. To add new DAGs:
   - Commit and push new DAG files to the `dags/` folder in this repository
   - Wait up to 60 seconds for automatic synchronization
   - Refresh the Airflow UI to see new DAGs

### Step 8: Run Sample DAGs

#### Run the Bash/Python Example DAG

1. In the Airflow UI, navigate to the **DAGs** page
2. Click on `example_bash_python`
3. Click the **Play** button (▶) to trigger the DAG
4. Click on the running DAG to view the graph
5. Click on individual tasks to view logs

**What it demonstrates**:
- BashOperator for shell commands
- PythonOperator for Python functions
- Task dependencies and linear workflow
- XCom for passing data between tasks

#### Run the Kubernetes Pod Example DAG

1. Navigate to `example_kubernetes_pod`
2. Trigger the DAG
3. Observe how tasks create separate Kubernetes pods

**What it demonstrates**:
- KubernetesPodOperator usage
- Running different container images (Ubuntu, Python, curl)
- Resource requests and limits
- Parallel task execution
- Automatic pod cleanup

4. Watch pods being created and deleted:
   ```bash
   kubectl get pods -n airflow -w
   ```

### Step 9: Monitor and Troubleshoot

#### View Logs

**Webserver logs**:
```bash
kubectl logs -n airflow -l component=webserver --tail=100 -f
```

**Scheduler logs**:
```bash
kubectl logs -n airflow -l component=scheduler --tail=100 -f
```

**Specific task logs** (via Airflow UI):
- Click on a task in the graph view
- Click **Log** button

**Task logs in Azure Blob Storage**:
```bash
# List logs in Azure Storage
az storage blob list \
  --account-name <storage-account-name> \
  --container-name airflow-logs \
  --output table
```

#### Common Issues and Solutions

**Issue**: DAGs not appearing in UI
- **Solution**: Check git-sync logs, verify repository URL and branch in `kubernetes/airflow-values.yaml`
- **Verify**: `kubectl logs -n airflow -l component=scheduler -c git-sync`

**Issue**: Database connection errors
- **Solution**: Check PostgreSQL firewall rules allow Azure services, verify connection string in Key Vault
- **Verify**: `kubectl logs -n airflow -l component=scheduler | grep -i database`

**Issue**: Tasks fail with "pod not found" errors
- **Solution**: Verify RBAC permissions for service account
- **Verify**: `kubectl get rolebinding -n airflow`

**Issue**: LoadBalancer IP not assigned
- **Solution**: Wait a few minutes, check AKS cluster has available public IPs
- **Verify**: `kubectl describe svc airflow-webserver -n airflow`

#### Useful Commands

Check Airflow version:
```bash
kubectl exec -n airflow -it deployment/airflow-scheduler -- airflow version
```

List Airflow connections:
```bash
kubectl exec -n airflow -it deployment/airflow-scheduler -- airflow connections list
```

Check database connectivity:
```bash
kubectl exec -n airflow -it deployment/airflow-scheduler -- airflow db check
```

Access Airflow CLI:
```bash
kubectl exec -n airflow -it deployment/airflow-scheduler -- /bin/bash
```

### Step 10: Explore Advanced Features

#### Create Custom DAGs

1. Create a new Python file in the `dags/` directory
2. Follow the example DAG structure
3. Commit and push to GitHub
4. Wait for git-sync (60 seconds)
5. View in Airflow UI

#### Configure Airflow Connections

Add Azure Blob Storage connection via Airflow UI:
1. Navigate to **Admin** > **Connections**
2. Click **+** to add new connection
3. Set:
   - Connection Id: `azure_blob_logs`
   - Connection Type: `Azure Blob Storage`
   - Configure with storage account details

#### View Metrics

Access Azure Monitor Container Insights:
```bash
# Get Log Analytics Workspace ID
az monitor log-analytics workspace show \
  --resource-group rg-airflow-lab \
  --workspace-name airflow-lab-logs \
  --query id -o tsv
```

View in Azure Portal:
- Navigate to AKS cluster > Insights
- Explore pods, nodes, and container performance

## Cleanup

To avoid ongoing charges, delete all resources when done:

### Option 1: Delete Resource Group (Recommended)

```bash
az group delete --name rg-airflow-lab --yes --no-wait
```

This deletes all resources including:
- AKS cluster
- PostgreSQL database
- Storage account
- Container registry
- Key Vault
- Virtual network
- Log Analytics workspace

### Option 2: Delete Individual Resources

If you want to keep some resources:

```bash
# Delete Airflow Helm release
helm uninstall airflow -n airflow

# Delete namespace
kubectl delete namespace airflow

# Delete specific Azure resources (keep others)
az aks delete --resource-group rg-airflow-lab --name airflow-lab-aks --yes --no-wait
```

### Verify Cleanup

```bash
# List remaining resources
az resource list --resource-group rg-airflow-lab --output table

# Verify resource group deletion (should eventually return error)
az group show --name rg-airflow-lab
```

## Next Steps and Learning Resources

### Extend This Lab

1. **Add more DAGs**:
   - Data processing workflows
   - ETL pipelines with Azure Data Lake
   - Machine learning pipelines

2. **Configure email notifications**:
   - Set up SMTP settings in Helm values
   - Configure alerts for task failures

3. **Enable authentication**:
   - Configure Azure AD OAuth integration
   - Set up RBAC roles in Airflow

4. **Implement CI/CD**:
   - GitHub Actions for DAG testing
   - Automated deployment pipelines

5. **Production hardening**:
   - Enable private AKS cluster
   - Configure network policies
   - Implement backup strategies
   - Set up high availability

### Learning Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/)
- [Azure AKS Documentation](https://learn.microsoft.com/azure/aks/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [KubernetesExecutor Guide](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/kubernetes.html)

## Troubleshooting Reference

### Pod Status Issues

| Status | Cause | Solution |
|--------|-------|----------|
| `Pending` | Insufficient resources | Scale up node pool or reduce resource requests |
| `ImagePullBackOff` | Cannot pull container image | Check ACR integration, verify image exists |
| `CrashLoopBackOff` | Container keeps crashing | Check logs with `kubectl logs`, review configuration |
| `Error` | Task failed | View task logs in Airflow UI or kubectl logs |

### Network Issues

Test connectivity from within cluster:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- sh
# Inside the pod:
curl -v http://airflow-webserver.airflow.svc.cluster.local:8080
```

### Database Issues

Test PostgreSQL connection:
```bash
kubectl run -it --rm psql --image=postgres:15 --restart=Never -- \
  psql postgresql://airflowadmin@airflow-lab-postgres.postgres.database.azure.com:5432/airflow
```

## Support

For issues specific to this lab:
- Check the logs as described in Step 9
- Review the deployment scripts for errors
- Verify all prerequisites are installed

For Airflow-specific questions:
- [Airflow Slack Community](https://apache-airflow.slack.com/)
- [Airflow GitHub Issues](https://github.com/apache/airflow/issues)

For Azure-specific questions:
- [Azure Support](https://azure.microsoft.com/support/)
- [Microsoft Q&A](https://learn.microsoft.com/answers/)

---

**Congratulations!** You've successfully deployed Apache Airflow on Azure Kubernetes Service. You now have a working environment to explore workflow orchestration, data pipelines, and Kubernetes-based task execution.
