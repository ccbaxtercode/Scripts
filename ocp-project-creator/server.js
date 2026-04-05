const express = require('express');
const { execSync } = require('child_process');
const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function getUsersAndGroups() {
  try {
    const users = execSync('oc get users --no-headers 2>/dev/null || echo ""', { encoding: 'utf8' })
      .trim().split('\n').filter(l => l.trim()).map(l => l.split(/\s+/)[0]).filter(Boolean);
    const groups = execSync('oc get groups --no-headers 2>/dev/null || echo ""', { encoding: 'utf8' })
      .trim().split('\n').filter(l => l.trim()).map(l => l.split(/\s+/)[0]).filter(Boolean);
    return { users, groups };
  } catch {
    return { users: [], groups: [] };
  }
}

function triggerPipelineRun(projectName, assignmentType, userOrGroupName, userOrGroupNames, quota, setQuota) {
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
        { name: 'set-quota', value: setQuota ? 'true' : 'false' },
        { name: 'cpu-request', value: quota.cpuRequest },
        { name: 'memory-request', value: quota.memoryRequest },
        { name: 'storage-request', value: quota.storageRequest },
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

function getPipelineRunStatus(name) {
  try {
    const output = execSync(`oc get pipelinerun ${name} -o jsonpath='{.status.conditions[0].type}:{.status.conditions[0].message}' 2>/dev/null || echo "Unknown"`, { encoding: 'utf8' });
    const [status, message] = output.replace(/'/g, '').split(':');
    return { status: status.trim(), message: message?.trim() || '' };
  } catch {
    return { status: 'Unknown', message: 'Not found' };
  }
}

app.get('/health', (req, res) => res.send('OK'));
app.get('/ready', (req, res) => res.send('OK'));

app.get('/api/users-groups', (req, res) => res.json(getUsersAndGroups()));

app.get('/api/me', (req, res) => {
  const user = req.headers['x-remote-user'] || 'unknown';
  const groups = req.headers['x-remote-groups'] || '';
  res.json({ user, groups: groups.split(',').filter(g => g) });
});

app.post('/api/create-project', (req, res) => {
  const { projectName, assignmentType, userOrGroupName, userOrGroupNames, quota, setQuota } = req.body;

  if (!projectName || !assignmentType || !userOrGroupName) {
    return res.status(400).json({ success: false, message: 'Missing required fields' });
  }

  const result = triggerPipelineRun(
    projectName, assignmentType, userOrGroupName, userOrGroupNames || [],
    quota || { cpuRequest: '1', memoryRequest: '4Gi', storageRequest: '10Gi' },
    setQuota || false
  );

  if (result.success) {
    res.json({ ...result, projectName, assignmentType, userOrGroupName, quota, setQuota });
  } else {
    res.json(result);
  }
});

app.get('/api/pipelinerun-status/:name', (req, res) => {
  res.json(getPipelineRunStatus(req.params.name));
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

app.listen(PORT, '0.0.0.0', () => console.log(`Server running on port ${PORT}`));
