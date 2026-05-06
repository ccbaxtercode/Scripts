const express = require('express');
const { execSync } = require('child_process');
const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

// Allowed groups for accessing this application (configured via environment variable)
const ALLOWED_GROUPS = (process.env.ALLOWED_GROUPS || 'project-creators').split(',').map(g => g.trim());

// Health and ready endpoints (MUST be before middleware)
app.get('/health', (req, res) => res.send('OK'));
app.get('/ready', (req, res) => res.send('OK'));

// Get user's groups from OpenShift
function getUserGroups(username) {
  try {
    // Get groups that contain this user
    const groupsRaw = execSync(
      `oc get groups -o jsonpath='{range .items[?(@.users[0] == "${username}")]}{.metadata.name}{"\\n"}{end}' 2>/dev/null || echo ''`,
      { encoding: 'utf8' }
    );
    const groups = groupsRaw.split('\n').filter(Boolean);
    return groups;
  } catch (error) {
    console.error('Error getting user groups:', error.message);
    return [];
  }
}

// Middleware to check if user is in allowed group
function checkGroupAccess(req, res, next) {
  // Skip health and ready endpoints
  if (req.path === '/health' || req.path === '/ready') {
    return next();
  }

  // Get username from header
  const username = req.headers['x-remote-user'] || '';
  
  if (!username) {
    return res.status(401).send(`
      <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 100px 20px; background: #f5f5f5; }
            .container { max-width: 500px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            h1 { color: #cc0000; margin-bottom: 20px; }
            p { color: #666; line-height: 1.6; }
            .logo { width: 80px; margin-bottom: 20px; }
          </style>
        </head>
        <body>
          <div class="container">
            <img src="https://images.seeklogo.com/logo-png/34/1/red-hat-openshift-logo-png_seeklogo-347513.png" alt="OpenShift" class="logo">
            <h1>Unauthorized</h1>
            <p>User information not found. Please log in through OpenShift.</p>
          </div>
        </body>
      </html>
    `);
  }

  // Query OpenShift API for user's groups
  console.log(`Checking group membership for user: ${username}`);
  const userGroupsList = getUserGroups(username);
  
  const hasAccess = userGroupsList.some(group => ALLOWED_GROUPS.includes(group));
  
  if (!hasAccess) {
    console.log(`Access denied for user ${username} (groups: ${userGroupsList.join(', ')})`);
    return res.status(403).send(`
      <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 100px 20px; background: #f5f5f5; }
            .container { max-width: 500px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            h1 { color: #cc0000; margin-bottom: 20px; }
            p { color: #666; line-height: 1.8; }
            .logo { width: 80px; margin-bottom: 20px; }
          </style>
        </head>
        <body>
          <div class="container">
            <img src="https://images.seeklogo.com/logo-png/34/1/red-hat-openshift-logo-png_seeklogo-347513.png" alt="OpenShift" class="logo">
            <h1>Access Denied</h1>
            <p>You do not have permission to access this page.</p>
            <p><strong>Required group:</strong> ${ALLOWED_GROUPS.join(' or ')}</p>
            <p><strong>Your groups:</strong> ${userGroupsList.join(', ') || 'None'}</p>
            <p style="margin-top: 30px; font-size: 12px; color: #999;">Contact your administrator to request access.</p>
          </div>
        </body>
      </html>
    `);
  }
  
  console.log(`Access granted for user ${username} (groups: ${userGroupsList.join(', ')})`);
  next();
}

// Apply group check middleware to all routes
app.use(checkGroupAccess);

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Get users and groups from OpenShift
function getUsersAndGroups() {
  try {
    // Get users - one name per line (handles spaces in names)
    const usersRaw = execSync(
      `oc get users -o jsonpath='{range .items[*]}{.metadata.name}{"\\n"}{end}' 2>/dev/null || echo ''`,
      { encoding: 'utf8' }
    );
    const users = usersRaw.split('\n').filter(Boolean);

    // Get groups - one name per line (handles spaces in names)
    const groupsRaw = execSync(
      `oc get groups -o jsonpath='{range .items[*]}{.metadata.name}{"\\n"}{end}' 2>/dev/null || echo ''`,
      { encoding: 'utf8' }
    );
    const groups = groupsRaw.split('\n').filter(Boolean);

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
    // Get full status, reason, namespace, and completion time
    const output = execSync(
      `oc get pipelinerun ${name} -o jsonpath='{.status.conditions[*].type}:{.status.conditions[*].reason}:{.metadata.namespace}:{.status.completionTime}' 2>/dev/null || echo "Unknown:Unknown:default:"`,
      { encoding: 'utf8' }
    );
    const parts = output.replace(/'/g, '').split(':');
    
    // Check if pipeline is still running or completed
    const conditionType = parts[0]?.trim() || '';
    const reason = parts[1]?.trim() || '';
    const namespace = parts[2]?.trim() || 'default';
    const completionTime = parts[3]?.trim() || '';
    
    // Determine final status based on reason (since type is usually just 'Succeeded')
    let status = 'Unknown';
    if (reason.includes('Succeeded') || reason.includes('Completed')) {
      status = 'Succeeded';
    } else if (reason.includes('Failed') || reason.includes('Error')) {
      status = 'Failed';
    } else if (reason.includes('Running') || !completionTime) {
      // Still running
      status = 'Running';
    } else {
      status = 'Unknown';
    }
    
    return { 
      status, 
      reason: status === 'Running' ? 'Running' : (reason || ''),
      namespace,
      pipelineRunName: name,
      isComplete: status === 'Succeeded' || status === 'Failed'
    };
  } catch (error) {
    return { status: 'Unknown', reason: error.message, namespace: 'default', pipelineRunName: name, isComplete: true };
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
    res.json({ 
      ...result, 
      projectName, 
      assignmentType, 
      userOrGroupName,
      consoleUrl: result.pipelineRun ? getConsoleUrl('project-creator', result.pipelineRun) : ''
    });
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
