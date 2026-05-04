# OpenShift Project Creator

Web application for creating OpenShift projects via Tekton Pipeline with OAuth authentication.

## Features

- Create namespace/project
- Assign role to user(s) or group
- Resource quotas (CPU, Memory, Storage)
- Network Policy (deny-all-ingress)
- OAuth authentication with group-based access control
- Role selection (roles starting with "ocp-")

## Quick Links

- [App README](openshift-project-app/README.md) - Detailed deployment guide
- [Preview](preview.html) - Web UI preview (open in browser)

## File Structure

```
openshift-project-app/
├── server.js              # Node.js backend
├── package.json           # Dependencies
├── Dockerfile             # Container image
├── deployment.yaml        # OpenShift deployment
└── public/
    └── index.html         # Web UI

pipeline.yaml               # Tekton Pipeline
tasks.yaml                  # Tekton Tasks
preview.html               # UI preview
```

## Prerequisites

- OpenShift 4.x
- Tekton Pipeline
- Users/Groups in OpenShift

## Quick Start

```bash
# 1. Create group
oc adm groups new project-creators
oc adm groups add-users project-creators user1 user2

# 2. Build and push image
cd openshift-project-app
docker build -t project-creator:latest .
docker tag project-creator:latest <nexus>/project-creator:latest
docker push <nexus>/project-creator:latest

# 3. Deploy
oc new-project project-creator
oc apply -f tasks.yaml -n project-creator
oc apply -f pipeline.yaml -n project-creator
oc apply -f openshift-project-app/deployment.yaml -n project-creator

# 4. OAuth permissions
oc adm policy add-cluster-role-to-user system:oauth-proxy \
  system:serviceaccount:project-creator:project-creator-sa
oc adm policy add-cluster-role-to-user system:auth-delegator \
  system:serviceaccount:project-creator:project-creator-sa
```

See [openshift-project-app/README.md](openshift-project-app/README.md) for detailed instructions.
