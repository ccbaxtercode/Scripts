# K3s on OpenShift Virtualization with MetalLB

Deploy production-ready K3s Kubernetes clusters on OpenShift Virtualization with automated VM provisioning and MetalLB LoadBalancer integration.

## 🎯 Overview

This Helm chart automates the complete deployment of K3s clusters on OpenShift Virtualization. It creates Ubuntu 22.04 VMs, installs K3s in a controlled sequence, and exposes the cluster API via MetalLB LoadBalancer.

### Key Features

- ✅ **Sequential Deployment**: Jobs ensure proper initialization order
- ✅ **MetalLB Integration**: Service gets external IP automatically
- ✅ **Persistent Storage**: DataVolumes with full OS persistence
- ✅ **High Availability**: Support for 1, 3, or 5 master nodes
- ✅ **Pod Network**: VMs use masquerade networking (no bridge setup needed)
- ✅ **Auto Kubeconfig**: Automatically fetched with Service IP
- ✅ **Cluster Info**: All credentials and IPs in one Secret

## 📋 Prerequisites

### Required

- OpenShift 4.19+ with Virtualization Operator
- MetalLB operator installed and configured
- CDI (Containerized Data Importer) for DataVolumes
- Helm 3.x
- Valid StorageClass
- HTTP server with Ubuntu 22.04 cloud image

### Resource Requirements

**Per VM:**
- CPU: 2 cores (default)
- Memory: 4Gi (default)
- Disk: 20Gi (default)

**For default config (1 master + 2 workers):**
- Total CPU: 6 cores
- Total Memory: 12Gi
- Total Storage: 60Gi

### Preparing Ubuntu Image

Download Ubuntu 22.04 cloud image:
```bash
wget https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img

# Serve via HTTP (example with Python)
python3 -m http.server 8080
# Image URL: http://your-server-ip:8080/ubuntu-22.04-server-cloudimg-amd64.img
```

## 🚀 Quick Start

### Install from Helm Repository

```bash
helm install my-k3s k3s-openshift-virt \
  --set password=SecurePassword123! \
  --set storageClassName=thin-csi \
  --set ubuntuImageURL=http://10.0.0.100:8080/ubuntu-22.04-server-cloudimg-amd64.img \
  --namespace my-k3s \
  --create-namespace
```

### Install from OpenShift Developer Catalog

1. Navigate to **Developer Catalog**
2. Search for "K3s on OpenShift Virt"
3. Click **Install**
4. Fill required parameters:
   - Admin Password
   - StorageClass name
   - Ubuntu Image URL
5. Click **Install**

## ⚙️ Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `password` | Admin user password | `SecurePass123!` |
| `storageClassName` | StorageClass for VM disks | `thin-csi` |
| `ubuntuImageURL` | HTTP URL to Ubuntu cloud image | `http://10.0.0.100:8080/ubuntu.img` |

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `clusterName` | K3s cluster name | `k3s-cluster` |
| `masterCount` | Number of masters (1, 3, or 5) | `1` |
| `workerCount` | Number of workers | `2` |
| `username` | Admin username | `k3sadmin` |
| `sshPublicKey` | SSH public key (optional) | `""` |
| `k3sVersion` | K3s version | `v1.28.5+k3s1` |
| `vmResources.cpu` | CPU cores per VM | `2` |
| `vmResources.memory` | Memory per VM | `4Gi` |
| `vmResources.diskSize` | Disk size per VM | `20Gi` |

### Example Configurations

#### Development Cluster

```bash
helm install dev-k3s k3s-openshift-virt \
  --set clusterName=dev-cluster \
  --set masterCount=1 \
  --set workerCount=1 \
  --set password=DevPass123! \
  --set storageClassName=thin-csi \
  --set ubuntuImageURL=http://10.0.0.100:8080/ubuntu.img \
  --set vmResources.cpu=2 \
  --set vmResources.memory=2Gi \
  --namespace development
```

#### Production HA Cluster

```bash
helm install prod-k3s k3s-openshift-virt \
  --set clusterName=production-k3s \
  --set masterCount=3 \
  --set workerCount=5 \
  --set password=ProdSecure123! \
  --set storageClassName=fast-ssd \
  --set ubuntuImageURL=http://10.0.0.100:8080/ubuntu.img \
  --set vmResources.cpu=4 \
  --set vmResources.memory=8Gi \
  --set vmResources.diskSize=100Gi \
  --namespace production
```

## 📊 Deployment Flow

### Step-by-Step Process

**1. Helm Install Initiated**

Static resources created immediately:
- Secrets (credentials, token)
- DataVolumes (all masters and workers)
- Service (LoadBalancer type)
- ServiceAccount + RBAC

**2. MetalLB Assigns External IP**

Service gets external IP from MetalLB IP pool.

**3. DataVolume Import**

Ubuntu images imported to PVCs (5-10 minutes per DataVolume, parallel).

**4. Job-01: Master-0 Deployment**

- Waits for Service External IP
- Saves IP to Secret
- Waits for Master-0 DataVolume ready
- Creates Master-0 VM with cloud-init
- Cloud-init installs K3s with Service IP
- Waits for K3s API ready

**5. Job-02: Additional Masters** (if masterCount > 1)

- Waits for Job-01 complete
- Waits for DataVolumes ready
- Creates Master-1, Master-2, etc.
- VMs join cluster via Service IP

**6. Job-03: Workers** (if workerCount > 0)

- Waits for all masters ready
- Waits for DataVolumes ready
- Creates Worker VMs
- VMs join as agents via Service IP

**7. Job-04: Fetch Kubeconfig**

- Waits for all VMs ready
- SSH to Master-0, gets `/etc/rancher/k3s/k3s.yaml`
- Updates server URL with Service External IP
- Saves to `kubeconfig` Secret
- Creates `cluster-info` Secret with all details

**8. Deployment Complete**

NOTES.txt displayed with access instructions.

## 📥 Post-Installation

### 1. Monitor Deployment

```bash
# Watch Jobs
oc get jobs -n my-k3s -w

# Watch VMs and VMIs
watch 'oc get vm,vmi -n my-k3s'

# Check Service External IP
oc get service my-k3s-k3s-api -n my-k3s
```

### 2. Get Cluster Information

```bash
# All cluster details in one Secret
oc get secret my-k3s-cluster-info -n my-k3s -o yaml

# Just the Service External IP
oc get secret my-k3s-cluster-info -n my-k3s \
  -o jsonpath='{.data.service-ip}' | base64 -d
```

### 3. Download Kubeconfig

```bash
# Download kubeconfig
oc get secret my-k3s-kubeconfig -n my-k3s \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > k3s.yaml

# Use it
export KUBECONFIG=k3s.yaml
kubectl get nodes
kubectl get pods -A
```

### 4. Access VMs

```bash
# Console access (requires virtctl)
virtctl console my-k3s-master-0 -n my-k3s

# SSH access
virtctl ssh k3sadmin@my-k3s-master-0 -n my-k3s

# Login: username/password from cluster-info Secret
```

## 🔍 Troubleshooting

### MetalLB Not Assigning IP

```bash
# Check MetalLB operator
oc get pods -n metallb-system

# Check IPAddressPool
oc get ipaddresspool -n metallb-system

# Check Service
oc describe service my-k3s-k3s-api -n my-k3s
```

### DataVolume Import Failed

```bash
# Check DataVolume status
oc get datavolume -n my-k3s

# Check specific DataVolume
oc describe datavolume my-k3s-master-0-disk -n my-k3s

# Check importer pod logs
oc logs -l cdi.kubevirt.io/dataVolume=my-k3s-master-0-disk -n my-k3s
```

### VM Not Booting

```bash
# Check VM status
oc describe vm my-k3s-master-0 -n my-k3s

# Check VMI
oc describe vmi my-k3s-master-0 -n my-k3s

# Access console
virtctl console my-k3s-master-0 -n my-k3s
```

### Job Failures

```bash
# Check job status
oc get jobs -n my-k3s

# View job logs
oc logs job/my-k3s-01-create-master0 -n my-k3s

# Delete failed job to retry
oc delete job my-k3s-01-create-master0 -n my-k3s
helm upgrade my-k3s k3s-openshift-virt -n my-k3s --reuse-values
```

### K3s Not Accessible

```bash
# Check Service External IP
oc get service my-k3s-k3s-api -n my-k3s

# Test connectivity from within cluster
oc run test-pod --image=curlimages/curl -it --rm -- \
  curl -k https://<service-external-ip>:6443/ping

# SSH to master and check K3s
virtctl ssh k3sadmin@my-k3s-master-0 -n my-k3s
sudo systemctl status k3s
sudo kubectl get nodes
```

## 🗑️ Uninstallation

### Remove Cluster

```bash
# Uninstall Helm release
helm uninstall my-k3s -n my-k3s
```

This removes:
- All Jobs
- All VirtualMachines
- Service
- Secrets
- ServiceAccount and RBAC

### Clean Up Storage

DataVolumes and PVCs are retained:

```bash
# List DataVolumes
oc get datavolume -n my-k3s

# Delete all cluster DataVolumes
oc delete datavolume -l release=my-k3s -n my-k3s

# PVCs will be deleted automatically when DataVolumes are deleted
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
│  │  │ Pod Net  │  │ Pod Net  │  │ Pod Net  │ │    │
│  │  │ K3s      │  │ K3s      │  │ K3s      │ │    │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘ │    │
│  │       │             │             │        │    │
│  │       └──────┬──────┴──────┬──────┘        │    │
│  │              │             │               │    │
│  │         ┌────▼─────────────▼────┐          │    │
│  │         │ Service (LoadBalancer) │          │    │
│  │         │  my-k3s-k3s-api:6443   │          │    │
│  │         │  External IP: 10.0.1.50│          │    │
│  │         └────────────────────────┘          │    │
│  │              ▲                              │    │
│  │              │ (MetalLB)                    │    │
│  │                                              │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐ │    │
│  │  │ Worker-0 │  │ Worker-1 │  │ Worker-2 │ │    │
│  │  │ (VM)     │  │ (VM)     │  │ (VM)     │ │    │
│  │  │ Pod Net  │  │ Pod Net  │  │ Pod Net  │ │    │
│  │  │ K3s      │  │ K3s      │  │ K3s      │ │    │
│  │  └──────────┘  └──────────┘  └──────────┘ │    │
│  │                                              │    │
│  │  [All VMs run on DataVolumes - persistent]  │    │
│  └────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘

External Users → MetalLB IP:6443 → Service → Master VMs
Workers → Service (internal) → Master VMs
```

## 📖 Additional Resources

- [K3s Documentation](https://docs.k3s.io)
- [OpenShift Virtualization](https://docs.openshift.com/container-platform/latest/virt/about-virt.html)
- [MetalLB](https://metallb.universe.tf/)
- [Helm Documentation](https://helm.sh/docs/)

## 🤝 Contributing

Contributions welcome! Please submit issues and pull requests.

## ⚠️ Important Notes

- **MetalLB Required**: Service needs MetalLB to get external IP
- **Ubuntu Image**: Must be accessible via HTTP
- **Pod Network**: VMs use masquerade (NAT) - no bridge setup needed
- **Persistence**: All OS data on DataVolumes/PVCs
- **SSH Access**: Requires virtctl or direct SSH to Service IP
- **Security**: Use strong passwords and SSH keys

## 📄 License

This Helm chart is provided as-is for use with K3s and OpenShift Virtualization.
