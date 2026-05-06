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

// Valid team prefixes and their required groups (from environment variables)
const TEAM_CONFIG = {
  dev:  { prefix: process.env.TEAM_DEV_PREFIX || 'dev-',   group: process.env.TEAM_DEV_GROUP || 'group-dev' },
  test: { prefix: process.env.TEAM_TEST_PREFIX || 'test-',  group: process.env.TEAM_TEST_GROUP || 'group-test' },
  prod: { prefix: process.env.TEAM_PROD_PREFIX || 'prod-',  group: process.env.TEAM_PROD_GROUP || 'group-prod' },
};
const VALID_PREFIXES = Object.values(TEAM_CONFIG).map(t => t.prefix);

// Session cache TTL for users/groups/roles (5 minutes)
const USERS_GROUPS_CACHE_TTL = 300000; // 5 minutes in ms

// CSRF secret (generated once at startup, new on every restart)
const CSRF_SECRET = crypto.randomBytes(32).toString('hex');
const CSRF_TTL = 8 * 60 * 60 * 1000; // 8 hours

// Rate limiting: per-user map
const rateLimitMap = {};
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const RATE_LIMIT_MAX = 5; // max creates per window

function checkRateLimit(username) {
  const now = Date.now();
  if (!rateLimitMap[username]) rateLimitMap[username] = [];
  rateLimitMap[username] = rateLimitMap[username].filter(ts => now - ts < RATE_LIMIT_WINDOW);
  if (rateLimitMap[username].length >= RATE_LIMIT_MAX) {
    console.warn(`[ProjectApp] Rate limit exceeded for user '${username}'`);
    return false;
  }
  rateLimitMap[username].push(now);
  return true;
}

// Validate CSRF token (HMAC of username.timestamp)
function validateCsrfToken(token, username) {
  try {
    const [u, ts, sig] = token.split('.');
    if (u !== username) return false;
    if (Date.now() - parseInt(ts) > CSRF_TTL) return false;
    const expected = crypto.createHmac('sha256', CSRF_SECRET).update(`${username}.${ts}`).digest('hex');
    return sig === expected;
  } catch { return false; }
}

// Sanitize input for safe shell interpolation (allow only [a-z0-9-])
function sanitizeForShell(input) {
  if (typeof input !== 'string') return '';
  return input.replace(/[^a-z0-9A-Z._@-]/g, '');
}

// Health and ready endpoints (MUST be before middleware)
app.get('/health', (req, res) => res.send('OK'));
app.get('/ready', (req, res) => res.send('OK'));

// Get user's groups from OpenShift (with per-user cache)
const userGroupCache = {};
const USER_GROUP_CACHE_TTL = 300000;

function getUserGroups(username) {
  if (!username) return [];

  const now = Date.now();
  const cached = userGroupCache[username];
  if (cached && (now - cached.ts) < USER_GROUP_CACHE_TTL) {
    console.log(`[ProjectApp] User '${username}' groups (cached): ${cached.groups.join(', ')}`);
    return cached.groups;
  }

  try {
    const safeUsername = sanitizeForShell(username);
    const groupsRaw = execSync(
      `oc get groups -o json 2>/dev/null | jq -r '.items[] | select(.users[]? == "${safeUsername}") | .metadata.name' 2>/dev/null || echo ''`,
      { encoding: 'utf8', timeout: 10000 }
    );
    const groups = groupsRaw.split('\n').filter(Boolean);
    userGroupCache[username] = { groups, ts: now };
    console.log(`[ProjectApp] User '${username}' groups: ${groups.join(', ')}`);
    return groups;
  } catch (error) {
    console.error(`[ProjectApp] Error getting groups for user '${username}':`, error.message);
    return [];
  }
}

// Trigger PipelineRun to create project
function triggerPipelineRun(projectName, assignmentType, userOrGroupName, userOrGroupNames, quota, role, pipelinerunuser, teamName) {
  const sanitizedProject = projectName.toLowerCase().replace(/[^a-z0-9-]/g, '-');

  const prefix = 'create-project-';
  const suffix = `-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
  const maxProjectLen = 63 - prefix.length - suffix.length;
  let projectSegment = sanitizedProject;
  if (projectSegment.length > maxProjectLen) {
    const hash = crypto.createHash('md5').update(sanitizedProject).digest('hex').substring(0, 4);
    projectSegment = projectSegment.substring(0, maxProjectLen - 5) + '-' + hash;
  }
  const pipelineRunName = `${prefix}${projectSegment}${suffix}`;

  const pipelineRun = {
    apiVersion: 'tekton.dev/v1beta1',
    kind: 'PipelineRun',
    metadata: { 
      name: pipelineRunName,
      annotations: { 
        'pipeline.openshift.io/started-by': pipelinerunuser
      },
    },
    spec: {
      pipelineRef: { name: 'create-project-and-assign-role' },
      params: [
        { name: 'project-name', value: projectName },
        { name: 'assignment-type', value: assignmentType },
        { name: 'user-or-group-name', value: userOrGroupName },
        { name: 'user-or-group-names-json', value: JSON.stringify(userOrGroupNames) },
        { name: 'cpu-request', value: quota.cpuRequest },
        { name: 'memory-request', value: quota.memoryRequest },
        { name: 'storage-request', value: quota.storageRequest },
        { name: 'role-name', value: role },
        { name: 'project-label', value: `group=${teamName}` },
      ],
    },
  };

  const tempFile = `/tmp/pipelinerun-${Date.now()}-${crypto.randomBytes(4).toString('hex')}.yaml`;
  fs.writeFileSync(tempFile, yaml.dump(pipelineRun));

  try {
    execSync(`oc apply -f ${tempFile}`, { stdio: 'pipe', timeout: 30000 });
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
    const output = execSync(
      `oc get pipelinerun ${name} -o jsonpath='{.status.conditions[*].type}:{.status.conditions[*].status}:{.status.conditions[*].reason}:{.metadata.namespace}:{.status.completionTime}' 2>/dev/null`,
      { encoding: 'utf8', timeout: 10000 }
    );
    const parts = output.replace(/'/g, '').split(':');

    const conditionTypes = parts[0]?.trim() || '';
    const conditionStatuses = parts[1]?.trim() || '';
    const reason = parts[2]?.trim() || '';
    const namespace = parts[3]?.trim() || 'default';
    const completionTime = parts[4]?.trim() || '';

    let status = 'Running';
    let failureReason = '';

    if (conditionTypes.includes('Succeeded') && conditionStatuses.includes('True')) {
      status = 'Succeeded';
    } else if (conditionTypes.includes('Failed') || conditionStatuses.includes('False')) {
      status = 'Failed';
      failureReason = reason;
    } else if (completionTime) {
      status = 'Unknown';
    }

    const result = {
      status,
      reason: failureReason,
      namespace,
      pipelineRunName: name,
      isComplete: status === 'Succeeded' || status === 'Failed'
    };

    console.log(`[ProjectApp] PipelineRun ${name} status:`, result);
    return result;
  } catch (error) {
    return { status: 'Unknown', reason: error.message, namespace: 'default', pipelineRunName: name, isComplete: true };
  }
}

// Get OpenShift console URL for PipelineRun
function getConsoleUrl(namespace, pipelineRunName) {
  try {
    const consoleUrl = execSync("oc -n openshift-console get route console -o jsonpath='https://{.spec.host}' || oc whoami --show-console", { encoding: 'utf8', timeout: 10000 });
    if (consoleUrl.trim()) {
      return `${consoleUrl.trim().replace(/\/$/, '')}/k8s/ns/${namespace}/tekton.dev~v1beta1~PipelineRun/${pipelineRunName}`;
    }
    return '';
  } catch (error) {
    console.warn('[ProjectApp] Error getting console URL:', error.message);
    return '';
  }
}

// Middleware to check if user is logged in (SAR handles access control)
function checkGroupAccess(req, res, next) {
  if (req.path === '/health' || req.path === '/ready') {
    return next();
  }

  const username = req.headers['x-forwarded-user'] || req.headers['x-remote-user'] || '';

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
            <p>User information not found. Please log in.</p>
          </div>
        </body>
      </html>
    `);
  }

  console.log(`Access granted for user ${username}`);
  next();
}

// Apply group check middleware to all routes
app.use(checkGroupAccess);

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Cache for users and groups (refresh every 5 minutes)
let usersGroupsCache = { users: [], groups: [], roles: [], timestamp: 0 };

// Get users and groups from OpenShift
function getUsersAndGroups() {
  try {
    const now = Date.now();
    if (now - usersGroupsCache.timestamp > USERS_GROUPS_CACHE_TTL) {
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
  const username = req.headers['x-forwarded-user'] || req.headers['x-remote-user'] || '';

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
  const user = req.headers['x-forwarded-user'] || req.headers['x-remote-user'] || 'unknown';
  const groups = req.headers['x-remote-groups'] || '';
  res.json({ user, groups: groups.split(',').filter(g => g) });
});

// Get CSRF token for form submission
app.get('/api/csrf-token', (req, res) => {
  const username = req.headers['x-forwarded-user'] || req.headers['x-remote-user'] || '';
  if (!username) return res.status(401).json({ error: 'Not authenticated' });
  const ts = Date.now();
  const sig = crypto.createHmac('sha256', CSRF_SECRET).update(`${username}.${ts}`).digest('hex');
  res.json({ token: `${username}.${ts}.${sig}` });
});

// Create project via PipelineRun
app.post('/api/create-project', (req, res) => {
  const { projectName, assignmentType, userOrGroupName, userOrGroupNames, quota, role } = req.body;
  console.log(`[ProjectApp] Create project request received — name: '${projectName}', type: '${assignmentType}', role: '${role}'`);

  if (!projectName || !assignmentType || !userOrGroupName) {
    console.warn(`[ProjectApp] Create project REJECTED — missing required fields`);
    return res.status(400).json({ success: false, message: 'Missing required fields' });
  }

  // CSRF token validation
  const username = req.headers['x-forwarded-user'] || req.headers['x-remote-user'] || '';
  const csrfToken = req.headers['x-csrf-token'] || '';
  if (!validateCsrfToken(csrfToken, username)) {
    console.warn(`[ProjectApp] Create project REJECTED — invalid CSRF token`);
    return res.status(403).json({ success: false, message: 'Invalid CSRF token' });
  }

  // Rate limiting
  if (!checkRateLimit(username)) {
    return res.status(429).json({ success: false, message: 'Too many requests. Please wait.' });
  }

  // Validate userOrGroupName against known lists
  const cachedData = getUsersAndGroups();
  const valueNames = Array.isArray(userOrGroupNames) && userOrGroupNames.length > 0 ? userOrGroupNames : userOrGroupName.split(',').map(s => s.trim());
  for (const name of valueNames) {
    const valid = assignmentType === 'user'
      ? cachedData.users.includes(name)
      : cachedData.groups.includes(name);
    if (!valid) {
      console.warn(`[ProjectApp] Create project REJECTED — invalid ${assignmentType} name: '${name}'`);
      return res.status(400).json({ success: false, message: `Invalid ${assignmentType} name: '${name}'` });
    }
  }

  // Validate quota values
  const finalQuota = quota || { cpuRequest: '1', memoryRequest: '4Gi', storageRequest: '10Gi' };
  const quotaErrors = [];
  if (!/^\d+(\.\d+)?$/.test(finalQuota.cpuRequest))
    quotaErrors.push(`Invalid CPU: '${finalQuota.cpuRequest}' (must be number, e.g. 1, 0.5, 2)`);
  if (!/^\d+(\.\d+)?[GM]i$/.test(finalQuota.memoryRequest))
    quotaErrors.push(`Invalid memory: '${finalQuota.memoryRequest}' (must be number followed by Gi/Mi, e.g. 4Gi, 512Mi)`);
  if (!/^\d+(\.\d+)?[GM]i$/.test(finalQuota.storageRequest))
    quotaErrors.push(`Invalid storage: '${finalQuota.storageRequest}' (must be number followed by Gi/Mi, e.g. 10Gi, 100Gi)`);
  if (quotaErrors.length > 0) {
    console.warn(`[ProjectApp] Create project REJECTED — quota validation errors:`, quotaErrors);
    return res.status(400).json({ success: false, message: quotaErrors.join('; ') });
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

  // Authorization: check if user is member of the required team group
  const matchedTeam = Object.entries(TEAM_CONFIG).find(([_, cfg]) => projectName.startsWith(cfg.prefix));
  if (!matchedTeam) {
    console.warn(`[ProjectApp] Create project REJECTED — no matching team for prefix`);
    return res.status(400).json({ success: false, message: 'Invalid team prefix' });
  }
  const [teamName, teamConfig] = matchedTeam;
  const userGroups = getUserGroups(username);
  if (!userGroups.includes(teamConfig.group)) {
    console.warn(`[ProjectApp] Create project REJECTED — user '${username}' not in '${teamConfig.group}'`);
    return res.status(403).json({ success: false, message: `Access denied: you are not a member of ${teamConfig.group}` });
  }

  console.log(`[ProjectApp] Validation passed for '${projectName}', triggering PipelineRun...`);

  const pipelinerunuser = username;

  const result = triggerPipelineRun(
    projectName, 
    assignmentType, 
    userOrGroupName, 
    userOrGroupNames || [], 
    finalQuota,
    role || 'edit',
    pipelinerunuser,
    teamName
  );

  if (result.success) {
    res.json({ 
      ...result, 
      projectName, 
      assignmentType, 
      userOrGroupName, 
      quota: finalQuota, 
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
