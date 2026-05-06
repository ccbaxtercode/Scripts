# OpenShift Project Creator Web

Web application for creating OpenShift projects via Tekton Pipeline with OAuth authentication.

## Quick Start

```bash
# Build and deploy
podman build -t project-creator-web:latest .
podman push <registry>/project-creator-web:latest
oc apply -f deployment.yaml

# Generate cookie secret
openssl rand -base64 32
# Update REPLACE_WITH_GENERATED_SECRET in deployment.yaml
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TEAM_DEV_PREFIX` | `dev-` | Dev team prefix |
| `TEAM_TEST_PREFIX` | `test-` | Test team prefix |
| `TEAM_PROD_PREFIX` | `prod-` | Prod team prefix |
| `TEAM_DEV_GROUP` | `group-dev` | Dev team group |
| `TEAM_TEST_GROUP` | `group-test` | Test team group |
| `TEAM_PROD_GROUP` | `group-prod` | Prod team group |

## SAR Permission (Access to Web Page)

Users need permission to access the web page. The OAuth proxy uses Subject Access Review (SAR) to check permission on the service.

Required permission:
```bash
# User needs 'get' permission on the service
oc auth can-i get services/project-creator-web -n project-creator --as=<user>
```

To grant access to a user:
```bash
# Create a role for page access
oc create role project-creator-web-access \
  --verb=get \
  --resource=services \
  -n project-creator

# Bind role to user
oc bind role project-creator-web-access \
  --name=project-creator-web-access \
  --user=<username> \
  -n project-creator
```

Or add to an existing group:
```bash
oc adm policy add-role-to-group project-creator-web-access \
  <group-name> -n project-creator
```

## Requirements

- OpenShift 4.x
- Tekton Pipeline operator
- `create-project-and-assign-role` pipeline
- `ocp-` prefixed ClusterRoles

## Testing

```bash
# Local syntax check
node --check server.js

# Deploy and verify
oc apply -f deployment.yaml
oc get pods -n project-creator
oc logs -l app=project-creator-web -c app -n project-creator -f

# Get URL
oc get route project-creator-web -n project-creator -o jsonpath='{.spec.host}'
```

## Architecture

```
User → Route (HTTPS) → OAuth Proxy → Node.js App → PipelineRun
```

## Project Name Rules

- Must start with team prefix (dev-, test-, prod-)
- RFC 1123: lowercase, alphanumeric, hyphens
- Max 63 characters
- Min 3 characters after prefix