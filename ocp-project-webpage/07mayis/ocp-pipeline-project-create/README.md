# OpenShift Project Creator

Web application for creating OpenShift projects via Tekton Pipeline with OAuth authentication.

## Quick Start

```bash
# 1. Create group and add users
oc adm groups new project-creators
oc adm groups add-users project-creators user1 user2

# 2. Build and deploy
cd ocp-pipeline-project-create-web-page
podman build -t project-creator-web:latest .
podman push <registry>/project-creator-web:latest

oc apply -f deployment.yaml

# 3. Update cookie-secret in deployment.yaml with:
openssl rand -base64 32
```

## Project Structure

```
├── server.js              # Node.js backend
├── public/
│   └── index.html         # Web UI
├── deployment.yaml        # OpenShift deployment
├── Dockerfile             # Container image
└── package.json           # Dependencies

../pipeline.yaml           # Tekton Pipeline
../tasks.yaml              # Tekton Tasks
../preview.html            # UI preview
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ALLOWED_GROUPS` | `project-creators` | Comma-separated allowed groups |
| `TEAM_DEV_PREFIX` | `dev-` | Dev team prefix |
| `TEAM_TEST_PREFIX` | `test-` | Test team prefix |
| `TEAM_PROD_PREFIX` | `prod-` | Prod team prefix |
| `TEAM_DEV_GROUP` | `group-dev` | Dev team group name |
| `TEAM_TEST_GROUP` | `group-test` | Test team group name |
| `TEAM_PROD_GROUP` | `group-prod` | Prod team group name |

## Requirements

- OpenShift 4.x
- Tekton Pipeline operator
- `create-project-and-assign-role` pipeline
- Users/Groups in OpenShift

## Testing

```bash
# Local syntax check
node --check server.js

# Deploy and check
oc get pods -n project-creator
oc logs -l app=project-creator-web -c app -n project-creator -f

# Get route
oc get route project-creator-web -n project-creator -o jsonpath='{.spec.host}'
```