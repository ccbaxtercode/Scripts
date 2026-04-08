const express = require('express');
const { execSync } = require('child_process');
const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

// Yardımcı bekleme fonksiyonu
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

const ALLOWED_GROUPS = (process.env.ALLOWED_GROUPS || 'project-creators').split(',').map(g => g.trim());

app.get('/health', (req, res) => res.send('OK'));
app.get('/ready', (req, res) => res.send('OK'));

// Kullanıcı gruplarını jq ile çekme
function getUserGroups(username) {
  try {
    // Kullanıcının içinde olduğu grupları jq ile filtrele
    const cmd = `oc get groups -o json | jq -r '.items[] | select(.users[]? == "${username}") | .metadata.name'`;
    const groupsRaw = execSync(cmd, { encoding: 'utf8' });
    return groupsRaw.split('\n').filter(Boolean);
  } catch (error) {
    console.error('Error getting user groups:', error.message);
    return [];
  }
}

function checkGroupAccess(req, res, next) {
  if (req.path === '/health' || req.path === '/ready') return next();
  const username = req.headers['x-remote-user'] || '';
  if (!username) return res.status(401).send('Unauthorized: User info not found.');

  const userGroupsList = getUserGroups(username);
  const hasAccess = userGroupsList.some(group => ALLOWED_GROUPS.includes(group));
  
  if (!hasAccess) {
    return res.status(403).send(`<h1>Access Denied</h1><p>Required: ${ALLOWED_GROUPS.join(', ')}</p>`);
  }
  next();
}

app.use(checkGroupAccess);
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// jq kullanarak kullanıcı ve grupları listeleme
function getUsersAndGroups() {
  try {
    const users = execSync("oc get users -o json | jq -r '.items[].metadata.name'", { encoding: 'utf8' });
    const groups = execSync("oc get groups -o json | jq -r '.items[].metadata.name'", { encoding: 'utf8' });
    return { 
      users: users.split('\n').filter(Boolean), 
      groups: groups.split('\n').filter(Boolean) 
    };
  } catch (error) { return { users: [], groups: [] }; }
}

// jq ile "ocp-" ile başlayan rolleri çekme
function getRoles() {
  try {
    // select(.metadata.name | startswith("ocp-")) ifadesi jq'da tam olarak istediğin şeyi yapar
    const cmd = `oc get clusterrole -o json | jq -r '.items[] | select(.metadata.name | startswith("ocp-")) | .metadata.name'`;
    const rolesOutput = execSync(cmd, { encoding: 'utf8' });
    return rolesOutput.trim().split('\n').filter(Boolean);
  } catch (error) {
    console.error('Error getting roles with jq:', error.message);
    return [];
  }
}

// PipelineRun durumunu sorgulama
function getPipelineRunStatus(name) {
  try {
    const cmd = `oc get pipelinerun ${name} -o json | jq -r '.status.conditions[0].type + ":" + .status.conditions[0].reason + ":" + .metadata.namespace + ":" + (.status.completionTime // "")'`;
    const output = execSync(cmd, { encoding: 'utf8' }).trim();
    const [type, reason, namespace, completionTime] = output.split(':');
    
    let status = 'Running';
    if (reason === 'Succeeded' || reason === 'Completed') status = 'Succeeded';
    else if (reason === 'Failed' || reason === 'Error' || reason === 'CouldntGetTask') status = 'Failed';
    else if (!completionTime) status = 'Running';

    return { 
      status, 
      reason, 
      namespace, 
      isComplete: status === 'Succeeded' || status === 'Failed' 
    };
  } catch (error) {
    return { status: 'Unknown', isComplete: false };
  }
}

// Pipeline tamamlanana kadar bekleyen döngü
async function waitForPipelineRun(name, timeoutMinutes = 10) {
  const startTime = Date.now();
  const timeoutMs = timeoutMinutes * 60 * 1000;

  while (Date.now() - startTime < timeoutMs) {
    const statusResult = getPipelineRunStatus(name);
    if (statusResult.isComplete) return statusResult;
    await delay(5000); // 5 saniye bekle
  }
  return { status: 'Timeout', reason: 'Execution exceeded 10m', isComplete: true };
}

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

  const tempFile = `/tmp/${pipelineRunName}.yaml`;
  fs.writeFileSync(tempFile, yaml.dump(pipelineRun));

  try {
    execSync(`oc apply -f ${tempFile}`);
    fs.unlinkSync(tempFile);
    return { success: true, pipelineRun: pipelineRunName };
  } catch (error) {
    if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);
    return { success: false, message: error.message };
  }
}

function getConsoleUrl(namespace, pipelineRunName) {
  try {
    const consoleUrl = execSync("oc get consoles.operator.openshift.io cluster -o json | jq -r '.status.consoleURL'", { encoding: 'utf8' });
    return consoleUrl ? `${consoleUrl.trim()}/k8s/ns/${namespace}/tekton.dev~v1beta1~PipelineRun/${pipelineRunName}` : '';
  } catch { return ''; }
}

// API Endpoints
app.get('/api/users-groups', (req, res) => {
  res.json({ ...getUsersAndGroups(), roles: getRoles() });
});

// Proje oluştur ve bitene kadar bekle
app.post('/api/create-project', async (req, res) => {
  const { projectName, assignmentType, userOrGroupName, userOrGroupNames, quota, role } = req.body;

  const triggerResult = triggerPipelineRun(
    projectName, assignmentType, userOrGroupName, 
    userOrGroupNames || [], quota, role
  );

  if (triggerResult.success) {
    // BEKLEME BAŞLIYOR
    const finalStatus = await waitForPipelineRun(triggerResult.pipelineRun);
    
    res.json({ 
      ...triggerResult, 
      status: finalStatus.status,
      reason: finalStatus.reason,
      consoleUrl: getConsoleUrl(finalStatus.namespace || 'project-creator', triggerResult.pipelineRun)
    });
  } else {
    res.status(500).json(triggerResult);
  }
});

app.get('/api/pipelinerun-status/:name', (req, res) => {
  res.json(getPipelineRunStatus(req.params.name));
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

app.listen(PORT, '0.0.0.0', () => console.log(`Server running on port ${PORT}`));
