const express = require('express');
const { execSync } = require('child_process');
const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 8080;

// Detect current namespace from Kubernetes service account (dynamic, no hardcoding)
let CURRENT_NAMESPACE = 'project-creator';
try {
  CURRENT_NAMESPACE = fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'utf8').trim();
  console.log(`[ProjectApp] Detected namespace: ${CURRENT_NAMESPACE}`);
} catch {
  CURRENT_NAMESPACE = process.env.NAMESPACE || 'project-creator';
  console.log(`[ProjectApp] Namespace detection failed, using fallback: ${CURRENT_NAMESPACE}`);
}

// Allowed groups for accessing this application (configured via environment variable)
const ALLOWED_GROUPS = (process.env.ALLOWED_GROUPS || 'project-creators').split(',').map(g => g.trim());

// Valid team prefixes and their required groups (from environment variables)
const TEAM_CONFIG = {
  dev:  { prefix: process.env.TEAM_DEV_PREFIX || 'dev-',   group: process.env.TEAM_DEV_GROUP || 'group-dev' },
  test: { prefix: process.env.TEAM_TEST_PREFIX || 'test-',  group: process.env.TEAM_TEST_GROUP || 'group-test' },
  prod: { prefix: process.env.TEAM_PROD_PREFIX || 'prod-',  group: process.env.TEAM_PROD_GROUP || 'group-prod' },
};
const VALID_PREFIXES = Object.values(TEAM_CONFIG).map(t => t.prefix);

// Sanitize input for safe shell interpolation (allow only [a-z0-9-])
function sanitizeForShell(input) {
  if (typeof input !== 'string') return '';
  return input.replace(/[^a-z0-9A-Z._@-]/g, '');
}

// Health and ready endpoints (MUST be before middleware)
app.get('/health', (req, res) => res.send('OK'));
app.get('/ready', (req, res) => res.send('OK'));

// Get user's groups from OpenShift (direct query with jq filter)
function getUserGroups(username) {
  if (!username) return [];
  try {
    const groupsRaw = execSync(
      `oc get groups -o json 2>/dev/null | jq -r '.items[] | select(.users[]? == "${username}") | .metadata.name' 2>/dev/null || echo ''`,
      { encoding: 'utf8', timeout: 10000 }
    );
    const groups = groupsRaw.split('\n').filter(Boolean);
    console.log(`[ProjectApp] User '${username}' groups: ${groups.join(', ')}`);
    return groups;
  } catch (error) {
    console.error(`[ProjectApp] Error getting groups for user '${username}':`, error.message);
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
    console.log(`Access denied for user ${username}`);
    return res.status(403).send(`
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
            <h1>Access Denied</h1>
            <p>You do not have permission to view this page.</p>
            <p>Please contact your administrator to request access.</p>
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

// Cache for users and groups (refresh every 60 seconds)
let usersGroupsCache = { users: [], groups: [], roles: [], timestamp: 0 };

// Get users and groups from OpenShift
function getUsersAndGroups() {
  try {
    const now = Date.now();
    if (now - usersGroupsCache.timestamp > GROUPS_CACHE_TTL) {
      const usersRaw = execSync(
        `oc get users -o jsonpath='{range .items[*]}{.metadata.name}{"\\n"}{end}' 2>/dev/null || echo ''`,
        { encoding: 'utf8', timeout: 10000 }
      );
      const groupsRaw = execSync(
        `oc get groups -o jsonpath='{range .items[*]}{.metadata.name}{"\\n"}{end}' 2>/dev/null || echo ''`,
        { encoding: 'utf8', timeout: 10000 }
      );
      const rolesOutput = execSync(
        "oc get clusterrole -o jsonpath='{.items[?(@.metadata.name startsWith \"ocp-\")].metadata.name}' 2>/dev/null || echo ''",
        { encoding: 'utf8', timeout: 10000 }
      );

      usersGroupsCache.users = usersRaw.split('\n').filter(Boolean);
      usersGroupsCache.groups = groupsRaw.split('\n').filter(Boolean);
      usersGroupsCache.roles = rolesOutput.trim().split(/\s+/).filter(Boolean);
      usersGroupsCache.timestamp = now;
      console.log(`[ProjectApp] Users/Groups/Roles cache refreshed (${usersGroupsCache.users.length} users, ${usersGroupsCache.groups.length} groups, ${usersGroupsCache.roles.length} roles)`);
    }
    return usersGroupsCache;
  } catch (error) {
    console.error('Error getting users/groups:', error.message);
    return { users: [], groups: [], roles: [] };
  }
}

// Get users, groups, and roles
app.get('/api/users-groups', (req, res) => {
  const data = getUsersAndGroups();
  res.json({ users: data.users, groups: data.groups, roles: data.roles });
});

// Check if user has access to a team (group membership check)
app.get('/api/check-team-access/:team', (req, res) => {
  const team = req.params.team;
  const username = req.headers['x-remote-user'] || '';

  if (!team || !TEAM_CONFIG[team]) {
    return res.status(400).json({ authorized: false, error: `Invalid team: '${team}'. Valid teams: ${Object.keys(TEAM_CONFIG).join(', ')}` });
  }

  const requiredGroup = TEAM_CONFIG[team].group;
  const userGroups = getUserGroups(username);
  const authorized = userGroups.includes(requiredGroup);

  console.log(`[ProjectApp] Team access check: user='${username}', team='${team}', requiredGroup='${requiredGroup}', authorized=${authorized}`);
  res.json({ authorized, team, group: requiredGroup, prefix: TEAM_CONFIG[team].prefix });
});

// Check if project name already exists in OpenShift
app.get('/api/check-project-name/:name', (req, res) => {
  const name = req.params.name;

  // Server-side format validation before passing to shell
  if (!name || name.length > 63 || !/^[a-z][a-z0-9-]*[a-z0-9]$/.test(name)) {
    console.warn(`[ProjectApp] Invalid project name format rejected: '${name}'`);
    return res.status(400).json({ available: false, error: 'Invalid project name format' });
  }

  const safeName = sanitizeForShell(name);
  console.log(`[ProjectApp] Checking if project '${safeName}' exists via: oc get project ${safeName}`);
  try {
    execSync(`oc get project ${safeName} 2>/dev/null`, { encoding: 'utf8', timeout: 10000 });
    // Project exists
    console.log(`[ProjectApp] Project '${safeName}' EXISTS — returning available: false`);
    res.json({ available: false });
  } catch {
    // Project does not exist
    console.log(`[ProjectApp] Project '${safeName}' NOT FOUND — returning available: true`);
    res.json({ available: true });
  }
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
  console.log(`[ProjectApp] Create project request received — name: '${projectName}', type: '${assignmentType}', role: '${role}'`);

  if (!projectName || !assignmentType || !userOrGroupName) {
    console.warn(`[ProjectApp] Create project REJECTED — missing required fields`);
    return res.status(400).json({ success: false, message: 'Missing required fields' });
  }

  // Server-side project name validation
  const errors = [];
  if (projectName.length > 63) {
    errors.push(`project-name must be 63 characters or fewer (got ${projectName.length})`);
  }
  if (!/^[a-z][a-z0-9-]*[a-z0-9]$/.test(projectName)) {
    errors.push(`project-name '${projectName}' does not match RFC 1123: must start with lowercase letter, contain only [a-z0-9-], end with letter or digit`);
  }
  const matchedPrefix = VALID_PREFIXES.find(p => projectName.startsWith(p));
  if (!matchedPrefix) {
    errors.push(`project-name must start with one of: ${VALID_PREFIXES.join(', ')}. Got: '${projectName}'`);
  }
  if (matchedPrefix && projectName.length < matchedPrefix.length + 3) {
    errors.push(`project-name must have at least 3 characters after '${matchedPrefix}' prefix (got ${projectName.length - matchedPrefix.length})`);
  }
  if (errors.length > 0) {
    console.warn(`[ProjectApp] Create project REJECTED — validation errors:`, errors);
    return res.status(400).json({ success: false, message: errors.join('; ') });
  }
  console.log(`[ProjectApp] Validation passed for '${projectName}', triggering PipelineRun...`);

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
      consoleUrl: getConsoleUrl(CURRENT_NAMESPACE, result.pipelineRun)
    });
  } else {
    res.json({ 
      ...result, 
      projectName, 
      assignmentType, 
      userOrGroupName,
      consoleUrl: result.pipelineRun ? getConsoleUrl(CURRENT_NAMESPACE, result.pipelineRun) : ''
    });
  }
});

// Get PipelineRun status
app.get('/api/pipelinerun-status/:name', (req, res) => {
  const name = req.params.name;

  // Validate pipelinerun name format (only allow alphanumeric, hyphens, dots)
  if (!name || !/^[a-z0-9][a-z0-9.-]*[a-z0-9]$/.test(name)) {
    console.warn(`[ProjectApp] Invalid pipelinerun name format rejected: '${name}'`);
    return res.status(400).json({ status: 'Unknown', reason: 'Invalid pipelinerun name format', isComplete: true });
  }

  const safeName = sanitizeForShell(name);
  const status = getPipelineRunStatus(safeName);
  if (status.status !== 'Unknown' && status.namespace) {
    status.consoleUrl = getConsoleUrl(status.namespace, safeName);
  }
  res.json(status);
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

app.listen(PORT, '0.0.0.0', () => console.log(`Server running on port ${PORT}`));
