# OpenShift Project Creator

Web UI for creating OpenShift projects via Tekton Pipeline.

## Features

- Create namespace/project
- Assign role to user or group (select multiple users)
- Resource quotas (CPU, Memory, Storage)
- Network Policy (deny-all-ingress, same-project allowed)
- OAuth authentication with group-based access control
- Role selection (roles starting with "ocp-")

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   User      │────▶│ oauth-proxy │────▶│   App      │
│  Browser    │     │   (sidecar) │     │  (Node.js) │
└─────────────┘     └──────────────┘     └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  Tekton     │
                                        │  Pipeline   │
                                        └─────────────┘
```

## File Structure

```
openshift-project-app/
├── server.js              # Node.js backend
├── package.json            # Dependencies
├── Dockerfile              # Container image
├── deployment.yaml        # OpenShift deployment + OAuth
└── public/
    └── index.html         # Web UI

../pipeline.yaml            # Tekton Pipeline
../tasks.yaml               # Tekton Tasks
../preview.html             # UI preview (mock data)
```

## Prerequisites

- OpenShift 4.x
- Tekton Pipeline installed
- Users/Groups configured in OpenShift

## Quick Start

### 1. Create Group and Add Users

```bash
# Create group
oc adm groups new project-creators

# Add users to group
oc adm groups add-users project-creators user1 user2
```

### 2. Build and Push Image

```bash
cd openshift-project-app

# Build image (connected environment)
docker build -t project-creator:latest .

# Tag and push to your registry
docker tag project-creator:latest <nexus>/project-creator:latest
docker push <nexus>/project-creator:latest
```

### 3. Update Image in deployment.yaml

```yaml
containers:
  - name: app
    image: <nexus>/project-creator:latest
```

### 4. Generate Cookie Secret

```bash
# Generate secret
openssl rand -base64 32
```

Replace `REPLACE_WITH_GENERATED_SECRET` in deployment.yaml or create secret:

```bash
oc create secret generic oauth-proxy-secrets \
  --from-literal=cookie-secret=$(openssl rand -base64 32) \
  -n project-creator
```

### 5. Deploy

```bash
# Create project
oc new-project project-creator

# Apply Tekton resources
oc apply -f ../tasks.yaml -n project-creator
oc apply -f ../pipeline.yaml -n project-creator

# Apply deployment
oc apply -f deployment.yaml -n project-creator
```

### 6. Configure OAuth Permissions

```bash
# Grant oauth-proxy permissions
oc adm policy add-cluster-role-to-user system:oauth-proxy \
  system:serviceaccount:project-creator:project-creator-sa

# Grant auth-delegator for group checking
oc adm policy add-cluster-role-to-user system:auth-delegator \
  system:serviceaccount:project-creator:project-creator-sa
```

### 7. Check Deployment

```bash
oc get pods -n project-creator
oc get route project-creator -n project-creator
```

## Access Control

Access is controlled via OpenShift `--openshift-sar`:

```yaml
- --openshift-sar={"namespace":"project-creator","resource":"clusterroles","name":"project-creator-access","verb":"impersonate"}
```

This checks if user can impersonate `project-creator-access` ClusterRole, which is bound to `project-creators` group.

**To change allowed groups:**

```bash
# Edit ClusterRoleBinding
oc edit clusterrolebinding project-creator-group-binding
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ALLOWED_GROUPS` | Comma-separated list of allowed groups | `project-creators` |
| `PORT` | Server port | `8080` |

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Web UI |
| `/health` | GET | Health check |
| `/ready` | GET | Readiness check |
| `/api/users-groups` | GET | List users, groups, and roles |
| `/api/create-project` | POST | Trigger PipelineRun |
| `/api/pipelinerun-status/:name` | GET | Get PipelineRun status |
| `/api/me` | GET | Current user info |

## Web UI Preview

Open `preview.html` in browser to see UI without OpenShift.

## Troubleshooting

### Access Denied

1. Check user is in `project-creators` group:
```bash
oc adm groups view project-creators
```

2. Check ClusterRoleBinding:
```bash
oc get clusterrolebinding project-creator-group-binding
```

### OAuth Issues

1. Check oauth-proxy logs:
```bash
oc logs deployment/project-creator -c oauth-proxy -n project-creator
```

2. Check service account annotations:
```bash
oc get sa project-creator-sa -n project-creator -o yaml
```
