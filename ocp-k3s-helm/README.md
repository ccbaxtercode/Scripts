# K3s on OpenShift Virtualization

Deploy K3s Kubernetes clusters on OpenShift Virtualization with automated, sequential VM provisioning.

## 🎯 Overview

This Helm chart automates the deployment of K3s clusters on OpenShift Virtualization infrastructure. It creates Ubuntu 22.04 VMs, installs K3s in a controlled sequence, and provides external access via OpenShift Routes.

### Key Features

- ✅ **Sequential Deployment**: Jobs ensure proper initialization order
- ✅ **High Availability**: Support for 1, 3, or 5 master nodes
- ✅ **Persistent Storage**: Each VM has dedicated PVC
- ✅ **External Access**: K3s API exposed via OpenShift Route
- ✅ **Auto Kubeconfig**: Automatically fetched and configured
- ✅ **Ubuntu 22.04**: Stable LTS base with cloud-init
- ✅ **Pod Network**: VMs use masquerade networking (no additional network setup)

## 📋 Prerequisites

### Required

- OpenShift 4.19+ with Virtualization Operator installed
- Helm 3.x
- Valid StorageClass available in cluster
- Namespace with permissions to create:
  - VirtualMachines
  - Secrets, PVCs, Services, Routes
  - Jobs, ServiceAccounts, Roles, RoleBindings

### Recommended

- `virtctl` CLI for VM console access
- `kubectl` for K3s cluster management

### Resource Requirements

Per VM:
- CPU: 2 cores (default)
- Memory: 4Gi (default)
- Disk: 20Gi (default)

Total for default config (1 master + 2 workers):
- CPU: 6 cores
- Memory: 12Gi
- Storage: 60Gi

## 🚀 Quick Start

### 1. Install from Helm Repository

```bash
# Add the repository (replace with actual URL)
helm repo add k3s-charts https://your-repo-url/

# Update repositories
helm repo update

# Install with minimal configuration
helm install my-k3s k3s-charts/k3s-openshift-virt \
  --set password=MySecurePassword123! \
  --set storageClassName=thin-csi \
  --namespace my-k3s \
  --create-namespace
```

### 2. Install from Local Chart

```bash
# From chart directory
helm install my-k3s ./k3s-openshift-virt \
  --set password=MySecurePassword123! \
  --set storageClassName=thin-csi \
  --namespace my-k3s \
  --create-namespace
```

### 3. Install from Catalog (OpenShift Console)

1. Navigate to **Developer Catalog**
2. Search for "K3s on OpenShift Virt"
3. Click **Install**
4. Fill in required parameters:
   - Password (required)
   - StorageClass name (required)
5. Click **Install**

## ⚙️ Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `password` | Admin user password for VM access | `SecurePass123!` |
| `storageClassName` | StorageClass for VM persistent disks | `thin-csi` |

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `clusterName` | K3s cluster name | `k3s-cluster` |
| `masterCount` | Number of master nodes (1, 3, or 5) | `1` |
| `workerCount` | Number of worker nodes | `2` |
| `username` | Admin username for VMs | `k3sadmin` |
| `k3sVersion` | K3s version to install | `v1.28.5+k3s1` |
| `vmResources.cpu` | CPU cores per VM | `2` |
| `vmResources.memory` | Memory per VM | `4Gi` |
| `vmResources.diskSize` | Disk size per VM | `20Gi` |
| `ubuntuImage` | Ubuntu container disk image | `quay.io/containerdisks/ubuntu:22.04` |

### Example Configurations

#### Development Cluster (Minimal)

```bash
helm install dev-k3s k3s-openshift-virt \
  --set clusterName=dev-cluster \
  --set masterCount=1 \
  --set workerCount=1 \
  --set password=DevPass123! \
  --set storageClassName=thin-csi \
  --set vmResources.cpu=2 \
  --set vmResources.memory=2Gi \
  --set vmResources.diskSize=10Gi \
  --namespace development
```

#### Production Cluster (HA)

```bash
helm install prod-k3s k3s-openshift-virt \
  --set clusterName=production-k3s \
  --set masterCount=3 \
  --set workerCount=5 \
  --set password=ProdSecurePass123! \
  --set storageClassName=fast-ssd \
  --set vmResources.cpu=4 \
  --set vmResources.memory=8Gi \
  --set vmResources.diskSize=100Gi \
  --namespace production
```

#### Using values.yaml

```yaml
# my-values.yaml
clusterName: staging-k3s
masterCount: 3
workerCount: 3
username: admin
password: StagingPass123!
k3sVersion: v1.28.5+k3s1
storageClassName: thin-csi

vmResources:
  cpu: 4
  memory: 8Gi
  diskSize: 50Gi
```

```bash
helm install staging-k3s k3s-openshift-virt \
  -f my-values.yaml \
  --namespace staging
```

## 📊 Deployment Process

The chart deploys K3s in a controlled sequence using Kubernetes Jobs:

```
Helm Install
    ↓
[Static Resources Created]
  • Secrets (credentials, token)
  • PVCs (VM disks)
  • Service (K3s API - internal)
  • Route (K3s API - external)
  • RBAC (ServiceAccount, Role, RoleBinding)
    ↓
[Job 1: Create Master-0]
  • Creates first master VM
  • Initializes K3s cluster (--cluster-init)
  • Waits for K3s API to respond
    ↓
[Job 2: Create Additional Masters] (if masterCount > 1)
  • Waits for Job-1 completion
  • Creates Master-1, Master-2, etc.
  • Joins existing cluster via Service
    ↓
[Job 3: Create Workers] (if workerCount > 0)
  • Waits for all masters ready
  • Creates all worker VMs
  • Joins cluster as agents via Service
    ↓
[Job 4: Fetch Kubeconfig]
  • Waits for cluster fully deployed
  • Retrieves kubeconfig from Master-0
  • Updates server URL to Route hostname
  • Saves to Secret for download
    ↓
[Deployment Complete]
```

### Timing

- **Single Master + Workers**: 3-5 minutes
- **HA (3 Masters) + Workers**: 5-8 minutes
- **Large Cluster (5 Masters + 10 Workers)**: 10-15 minutes

## 📥 Post-Installation

### 1. Monitor Deployment

```bash
# Watch all resources
watch 'oc get job,vm,vmi -n my-k3s'

# Watch jobs specifically
oc get jobs -n my-k3s -w

# Check job logs
oc logs -f job/my-k3s-01-create-master0 -n my-k3s
```

### 2. Wait for Completion

```bash
# Wait for kubeconfig job
oc wait --for=condition=complete \
  job/my-k3s-04-fetch-kubeconfig \
  -n my-k3s --timeout=600s
```

### 3. Get Route Address

```bash
# Get external K3s API URL
oc get route my-k3s-k3s-api -n my-k3s -o jsonpath='{.spec.host}'
```

### 4. Download Kubeconfig

```bash
# Download kubeconfig
oc get secret my-k3s-kubeconfig \
  -n my-k3s \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > k3s-kubeconfig.yaml

# Set as active kubeconfig
export KUBECONFIG=k3s-kubeconfig.yaml

# Verify cluster access
kubectl get nodes
kubectl get pods -A
```

## 🔌 Accessing VMs

### Console Access (requires virtctl)

```bash
# Connect to Master-0 console
virtctl console my-k3s-master-0 -n my-k3s

# Login with credentials from values.yaml
# Username: k3sadmin (default)
# Password: <your-password>
```

### SSH Access (requires virtctl)

```bash
# SSH to Master-0
virtctl ssh k3sadmin@my-k3s-master-0 -n my-k3s

# SSH to Worker-0
virtctl ssh k3sadmin@my-k3s-worker-0 -n my-k3s
```

### Direct Pod Exec

```bash
# Find VMI pod
VMI_POD=$(oc get pod -n my-k3s \
  -l kubevirt.io/domain=my-k3s-master-0 \
  -o jsonpath='{.items[0].metadata.name}')

# Execute command in VM
oc exec -n my-k3s $VMI_POD -- bash -c "your-command"
```

## 🔍 Troubleshooting

### Job Failures

```bash
# Check which job failed
oc get jobs -n my-k3s

# View job logs
oc logs job/my-k3s-01-create-master0 -n my-k3s

# Check events
oc get events -n my-k3s --sort-by='.lastTimestamp'

# Delete failed job to retry
oc delete job my-k3s-01-create-master0 -n my-k3s
helm upgrade my-k3s k3s-openshift-virt -n my-k3s --reuse-values
```

### VM Issues

```bash
# Check VM status
oc get vm -n my-k3s
oc describe vm my-k3s-master-0 -n my-k3s

# Check VMI status
oc get vmi -n my-k3s
oc describe vmi my-k3s-master-0 -n my-k3s

# Check VMI pod logs
oc logs -l kubevirt.io/domain=my-k3s-master-0 -n my-k3s
```

### PVC Issues

```bash
# Check PVC status
oc get pvc -n my-k3s

# Check PVC events
oc describe pvc my-k3s-master-0-disk -n my-k3s

# Verify StorageClass exists
oc get storageclass
```

### K3s Issues

```bash
# Connect to VM and check K3s status
virtctl console my-k3s-master-0 -n my-k3s

# Inside VM:
sudo systemctl status k3s
sudo journalctl -u k3s -f
sudo kubectl get nodes
```

### Kubeconfig Not Generated

```bash
# Check Job-4 status
oc get job my-k3s-04-fetch-kubeconfig -n my-k3s
oc logs job/my-k3s-04-fetch-kubeconfig -n my-k3s

# Manually fetch kubeconfig
VMI_POD=$(oc get pod -n my-k3s \
  -l kubevirt.io/domain=my-k3s-master-0 \
  -o jsonpath='{.items[0].metadata.name}')

oc exec -n my-k3s $VMI_POD -- \
  cat /etc/rancher/k3s/k3s.yaml > temp-kubeconfig.yaml

# Update server URL manually
ROUTE_HOST=$(oc get route my-k3s-k3s-api -n my-k3s -o jsonpath='{.spec.host}')
sed -i "s|127.0.0.1:6443|${ROUTE_HOST}:443|g" temp-kubeconfig.yaml
```

## 🗑️ Uninstallation

### Remove Cluster

```bash
# Uninstall Helm release
helm uninstall my-k3s -n my-k3s
```

This removes:
- All Jobs
- All VirtualMachines and VMIs
- Service and Route
- Secrets (credentials, token, kubeconfig)
- ServiceAccount and RBAC

### Clean Up Storage

PVCs are retained by default to prevent data loss:

```bash
# List PVCs
oc get pvc -n my-k3s

# Delete all cluster PVCs
oc delete pvc -l app.kubernetes.io/instance=my-k3s -n my-k3s

# Or delete specific PVC
oc delete pvc my-k3s-master-0-disk -n my-k3s
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│           OpenShift Cluster                          │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │  Namespace: my-k3s                          │    │
│  │                                              │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐ │    │
│  │  │ Master-0 │  │ Master-1 │  │ Master-2 │ │    │
│  │  │ (VM)     │  │ (VM)     │  │ (VM)     │ │    │
│  │  │ K3s      │  │ K3s      │  │ K3s      │ │    │
│  │  │ Server   │  │ Server   │  │ Server   │ │    │
│  │  │ + etcd   │  │ + etcd   │  │ + etcd   │ │    │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘ │    │
│  │       │             │             │        │    │
│  │       └──────┬──────┴──────┬──────┘        │    │
│  │              │             │               │    │
│  │         ┌────▼─────────────▼────┐          │    │
│  │         │ Service (ClusterIP)    │          │    │
│  │         │  my-k3s-k3s-api:6443   │          │    │
│  │         └────┬───────────────────┘          │    │
│  │              │                              │    │
│  │         ┌────▼──────────────────┐           │    │
│  │         │ Route (Passthrough)    │           │    │
│  │         │ https://k3s.apps...    │           │    │
│  │         └────────────────────────┘           │    │
│  │                                              │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐ │    │
│  │  │ Worker-0 │  │ Worker-1 │  │ Worker-2 │ │    │
│  │  │ (VM)     │  │ (VM)     │  │ (VM)     │ │    │
│  │  │ K3s      │  │ K3s      │  │ K3s      │ │    │
│  │  │ Agent    │  │ Agent    │  │ Agent    │ │    │
│  │  └──────────┘  └──────────┘  └──────────┘ │    │
│  │                                              │    │
│  │  [Each VM has dedicated PVC]                │    │
│  └────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘

External Users → Route → Service → Master VMs (K3s API)
Workers → Service (internal) → Master VMs
```

## 📖 Additional Resources

- [K3s Documentation](https://docs.k3s.io)
- [OpenShift Virtualization](https://docs.openshift.com/container-platform/latest/virt/about-virt.html)
- [Helm Documentation](https://helm.sh/docs/)
- [KubeVirt](https://kubevirt.io)

## 🤝 Contributing

Contributions are welcome! Please submit issues and pull requests.

## 📄 License

This Helm chart is provided as-is for use with K3s and OpenShift Virtualization.

## ⚠️ Important Notes

- **Token Security**: Cluster token is auto-generated and stored in Secret. Keep it secure!
- **Password Storage**: VM passwords are stored in cloud-init Secrets. Use strong passwords!
- **Resource Planning**: Ensure sufficient cluster resources before deploying large clusters
- **Network Access**: VMs use pod network (masquerade) - no additional network configuration needed
- **Persistence**: VM data is stored on PVCs - backup important data regularly
- **Updates**: Use `helm upgrade` carefully - VMs are not automatically recreated
