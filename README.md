# Apache Airflow on Azure Kubernetes Service (AKS)

A complete lab demonstrating how to deploy and run Apache Airflow on Azure Kubernetes Service using infrastructure-as-code and best practices.

## Overview

This repository contains everything needed to deploy a production-ready Apache Airflow environment on Azure Kubernetes Service (AKS), including:

- **Infrastructure as Code**: Modular Bicep templates for all Azure resources
- **Automated Deployment**: Shell scripts for one-command infrastructure and Airflow deployment
- **Kubernetes Configuration**: Helm chart values with Azure integrations
- **Sample DAGs**: Example workflows demonstrating Airflow capabilities
- **Comprehensive Documentation**: Step-by-step lab guide

## Architecture

- **Executor**: KubernetesExecutor (dynamic pod creation per task)
- **Database**: Azure PostgreSQL Flexible Server (metadata storage)
- **Storage**: Azure Blob Storage (WASB remote logging)
- **DAG Management**: Git-sync from this repository
- **Secrets**: Azure Key Vault with CSI driver integration
- **Monitoring**: Azure Log Analytics and Container Insights
- **Networking**: Public AKS cluster with LoadBalancer service

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/acworkma/airflow.git
cd airflow

# 2. Deploy Azure infrastructure (10-15 minutes)
./scripts/deploy-infrastructure.sh

# 3. Configure RBAC permissions (required)
./scripts/configure-permissions.sh

# 4. Deploy Airflow to Kubernetes (5-10 minutes)
./scripts/deploy-airflow.sh

# 5. Access the Airflow UI
kubectl get svc -n airflow airflow-webserver
# Open http://<EXTERNAL-IP>:8080 in your browser
# Login with credentials created during deployment
```

## Prerequisites

- Azure subscription with contributor access
- Azure CLI (`az`) - [Install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- kubectl - [Install](https://kubernetes.io/docs/tasks/tools/)
- Helm 3 - [Install](https://helm.sh/docs/intro/install/)
- Git
- jq - [Install](https://stedolan.github.io/jq/download/)
- Python 3 with `cryptography` package:
  ```bash
  pip install cryptography
  ```

**Note**: The deployment scripts will automatically install the `cryptography` Python package if it's missing.

## Repository Structure

```
airflow/
├── infrastructure/              # Bicep templates
│   ├── main.bicep              # Main orchestration template
│   ├── modules/                # Resource-specific modules
│   │   ├── aks.bicep
│   │   ├── acr.bicep
│   │   ├── postgresql.bicep
│   │   ├── keyvault.bicep
│   │   ├── storage.bicep
│   │   ├── vnet.bicep
│   │   └── monitoring.bicep
│   └── parameters/
│       └── lab.bicepparam      # Lab environment parameters
├── kubernetes/
│   └── airflow-values.yaml     # Helm chart configuration
├── scripts/
│   ├── deploy-infrastructure.sh
│   └── deploy-airflow.sh
├── dags/                       # Airflow DAGs (auto-synced)
│   ├── example_bash_python.py
│   ├── example_kubernetes_pod.py
│   └── .airflowignore
├── LAB-GUIDE.md               # Detailed lab instructions
└── README.md                  # This file
```

## Azure Resources Deployed

| Resource | Purpose | SKU/Tier |
|----------|---------|----------|
| AKS Cluster | Kubernetes orchestration | 2 x Standard_D2s_v3 nodes |
| PostgreSQL | Airflow metadata database | Burstable B1ms |
| Storage Account | Log storage (WASB) | Standard LRS |
| Container Registry | Custom images | Basic |
| Key Vault | Secrets management | Standard |
| Virtual Network | Network isolation | 10.0.0.0/16 |
| Log Analytics | Monitoring and insights | Pay-as-you-go |

## Cost Estimate

**~$150-$200 USD/month** for lab environment

See [LAB-GUIDE.md](LAB-GUIDE.md) for detailed cost breakdown and optimization tips.

## Features

✅ **KubernetesExecutor** - Each task runs in its own isolated pod  
✅ **Git-Sync** - DAGs automatically synced from GitHub every 60 seconds  
✅ **Azure Integrations** - PostgreSQL, Blob Storage, Key Vault, Log Analytics  
✅ **High Availability** - 2 schedulers, 2 webservers  
✅ **Secure by Default** - Managed identities, Key Vault secrets, RBAC  
✅ **Production Ready** - Container Insights, remote logging, auto-scaling  
✅ **Easy Deployment** - One-command infrastructure and Airflow setup  

## Sample DAGs

### example_bash_python.py
Demonstrates basic Airflow operators:
- BashOperator for shell commands
- PythonOperator for Python functions
- XCom for inter-task communication
- Linear task dependencies

### example_kubernetes_pod.py
Shows KubernetesExecutor capabilities:
- KubernetesPodOperator usage
- Multiple container images (Ubuntu, Python, curl)
- Resource requests and limits
- Parallel task execution
- Automatic pod cleanup

## Usage

### Access Airflow UI

```bash
# Get the LoadBalancer IP
kubectl get svc -n airflow airflow-webserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Open in browser: http://<IP>:8080
# Login: admin / admin
```

### Add New DAGs

1. Create a Python file in the `dags/` directory
2. Commit and push to GitHub
3. Wait 60 seconds for automatic sync
4. View in Airflow UI

### Monitor Deployment

```bash
# Check all pods
kubectl get pods -n airflow

# View scheduler logs
kubectl logs -n airflow -l component=scheduler --tail=100

# View webserver logs
kubectl logs -n airflow -l component=webserver --tail=100

# Watch git-sync
kubectl logs -n airflow -l component=scheduler -c git-sync --tail=50
```

### Cleanup

```bash
# Delete all resources
az group delete --name rg-airflow-lab --yes --no-wait
```

## Documentation

- **[LAB-GUIDE.md](LAB-GUIDE.md)** - Complete step-by-step lab guide with troubleshooting
- **Infrastructure** - See `infrastructure/` directory for Bicep templates
- **Kubernetes** - See `kubernetes/` directory for Helm values
- **DAGs** - See `dags/` directory for example workflows

## Learning Outcomes

After completing this lab, you will understand:

1. **Infrastructure as Code** with Azure Bicep
2. **Kubernetes** deployment and management on AKS
3. **Apache Airflow** architecture and components
4. **KubernetesExecutor** for dynamic task execution
5. **Azure integrations** (Key Vault, PostgreSQL, Blob Storage)
6. **DAG development** and git-sync workflows
7. **Production patterns** for workflow orchestration

## Troubleshooting

See the [LAB-GUIDE.md](LAB-GUIDE.md) for comprehensive troubleshooting steps.

Common issues:
- **DAGs not appearing**: Check git-sync logs
- **Database errors**: Verify PostgreSQL firewall rules
- **Pod failures**: Check RBAC permissions
- **LoadBalancer IP pending**: Wait 2-5 minutes for Azure to assign IP

## Contributing

This is a learning lab repository. Feel free to:
- Add more example DAGs
- Improve deployment scripts
- Enhance documentation
- Share feedback and issues

## Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/)
- [Azure AKS Documentation](https://learn.microsoft.com/azure/aks/)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [KubernetesExecutor Guide](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/kubernetes.html)

## License

This project is for educational purposes.

## Support

For issues:
1. Check [LAB-GUIDE.md](LAB-GUIDE.md) troubleshooting section
2. Review deployment script output
3. Check pod logs: `kubectl logs -n airflow <pod-name>`
4. Verify Azure resource status in Azure Portal

---

**Ready to get started?** Open [LAB-GUIDE.md](LAB-GUIDE.md) for detailed instructions!
