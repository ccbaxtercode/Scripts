const express = require('express');
const { execSync } = require('child_process');
const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Get users and groups from OpenShift
function getUsersAndGroups() {
  try {
    // Get users - jsonpath for name column
    const usersOutput = execSync("oc get users -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ''", { encoding: 'utf8' });
    const users = usersOutput.trim().split(/\s+/).filter(Boolean);

    // Get groups - jsonpath for name column
    const groupsOutput = execSync("oc get groups -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ''", { encoding: 'utf8' });
    const groups = groupsOutput.trim().split(/\s+/).filter(Boolean);

    return { users, groups };
  } catch (error) {
    console.error('Error getting users/groups:', error.message);
    return { users: [], groups: [] };
  }
}

// Get roles starting with "ocp-"
function getRoles() {
  try {
    const rolesOutput = execSync("oc get clusterrole -o jsonpath='{.items[?(@.metadata.name startsWith \"ocp-\")].metadata.name}' 2>/dev/null || echo ''", { encoding: 'utf8' });
    const roles = rolesOutput.trim().split(/\s+/).filter(Boolean);
    return roles;
  } catch (error) {
    console.error('Error getting roles:', error.message);
    return [];
  }
}

// Trigger PipelineRun to create project
function triggerPipelineRun(projectName, assignmentType, userOrGroupName, userOrGroupNames, quota, role) {
  const sanitizedProject = projectName.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const pipelineRunName = `create-project-${sanitizedProject}-${Date.now()}`;

  const pipelineRun = {
    apiVersion: 'tekton.dev/v1beta1',
    kind: 'PipelineRun',
    metadata: { name: pipelineRunName },
    spec: {
      pipelineRef: { name: 'create-project-and-assign-role' },
      params: [
        { name: 'project-name', value: projectName },
        { name: 'assignment-type', value: assignmentType },
        { name: 'user-or-group-name', value: userOrGroupName },
        { name: 'user-or-group-names-json', value: JSON.stringify(userOrGroupNames) },
        { name: 'set-quota', value: 'true' },
        { name: 'cpu-request', value: quota.cpuRequest },
        { name: 'memory-request', value: quota.memoryRequest },
        { name: 'storage-request', value: quota.storageRequest },
        { name: 'role-name', value: role },
      ],
    },
  };

  const tempFile = `/tmp/pipelinerun-${Date.now()}.yaml`;
  fs.writeFileSync(tempFile, yaml.dump(pipelineRun));

  try {
    execSync(`oc apply -f ${tempFile}`, { stdio: 'pipe' });
    fs.unlinkSync(tempFile);
    return { success: true, pipelineRun: pipelineRunName };
  } catch (error) {
    fs.unlinkSync(tempFile);
    return { success: false, message: error.message };
  }
}

// Get PipelineRun status
function getPipelineRunStatus(name) {
  try {
    // Get status, reason, and namespace
    const output = execSync(`oc get pipelinerun ${name} -o jsonpath='{.status.conditions[0].type}:{.status.conditions[0].reason}:{.metadata.namespace}' 2>/dev/null || echo "Unknown:Unknown:default"`, { encoding: 'utf8' });
    const parts = output.replace(/'/g, '').split(':');
    const status = parts[0]?.trim() || 'Unknown';
    const reason = parts[1]?.trim() || '';
    const namespace = parts[2]?.trim() || 'default';
    
    return { 
      status, 
      reason,
      namespace,
      pipelineRunName: name
    };
  } catch (error) {
    return { status: 'Unknown', reason: error.message, namespace: 'default', pipelineRunName: name };
  }
}

// Get OpenShift console URL for PipelineRun
function getConsoleUrl(namespace, pipelineRunName) {
  try {
    // Get the console URL from cluster
    const consoleUrl = execSync("oc get consoles.operator.openshift.io cluster -o jsonpath='{.status.consoleURL}' 2>/dev/null || echo ''", { encoding: 'utf8' });
    if (consoleUrl.trim()) {
      return `${consoleUrl.trim().replace(/\/$/, '')}/k8s/ns/${namespace}/tekton.dev~v1beta1~PipelineRun/${pipelineRunName}`;
    }
    return '';
  } catch {
    return '';
  }
}

// Health and ready endpoints
app.get('/health', (req, res) => res.send('OK'));
app.get('/ready', (req, res) => res.send('OK'));

// Get users, groups, and roles
app.get('/api/users-groups', (req, res) => {
  const data = getUsersAndGroups();
  const roles = getRoles();
  res.json({ ...data, roles });
});

// Get logged in user info
app.get('/api/me', (req, res) => {
  const user = req.headers['x-remote-user'] || 'unknown';
  const groups = req.headers['x-remote-groups'] || '';
  res.json({ user, groups: groups.split(',').filter(g => g) });
});

// Create project via PipelineRun
app.post('/api/create-project', (req, res) => {
  const { projectName, assignmentType, userOrGroupName, userOrGroupNames, quota, role } = req.body;

  if (!projectName || !assignmentType || !userOrGroupName) {
    return res.status(400).json({ success: false, message: 'Missing required fields' });
  }

  const result = triggerPipelineRun(
    projectName, 
    assignmentType, 
    userOrGroupName, 
    userOrGroupNames || [], 
    quota || { cpuRequest: '1', memoryRequest: '4Gi', storageRequest: '10Gi' },
    role || 'edit'
  );

  if (result.success) {
    res.json({ 
      ...result, 
      projectName, 
      assignmentType, 
      userOrGroupName, 
      quota, 
      role,
      consoleUrl: getConsoleUrl('project-creator', result.pipelineRun)
    });
  } else {
    res.json(result);
  }
});

// Get PipelineRun status
app.get('/api/pipelinerun-status/:name', (req, res) => {
  const status = getPipelineRunStatus(req.params.name);
  if (status.status !== 'Unknown' && status.namespace) {
    status.consoleUrl = getConsoleUrl(status.namespace, req.params.name);
  }
  res.json(status);
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

app.listen(PORT, '0.0.0.0', () => console.log(`Server running on port ${PORT}`));
