const express = require('express');
const cors = require('cors');
const app = express();

// Enable CORS for all routes
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    credentials: false
}));

// Parse JSON bodies
app.use(express.json());

// Mock API endpoints that the frontend is trying to access
app.get('/api/date-format', (req, res) => {
    console.log('GET /api/date-format');
    res.json({
        dateFormat: 'MM/dd/yyyy',
        timeFormat: 'HH:mm:ss',
        timezone: 'UTC'
    });
});

app.get('/api/system/info', (req, res) => {
    console.log('GET /api/system/info');
    res.json({
        version: '7.1.0',
        build: 'development',
        status: 'running'
    });
});

app.get('/api/health', (req, res) => {
    console.log('GET /api/health');
    res.json({
        status: 'UP',
        components: {
            database: { status: 'UP' },
            elasticsearch: { status: 'UP' }
        }
    });
});

// Mock TOTP verification endpoint
app.get('/api/tfa/verifyCode', (req, res) => {
    const code = req.query.code;
    console.log(`GET /api/tfa/verifyCode?code=${code}`);
    
    // For testing: accept 123456 as valid, reject others
    if (code === '123456') {
        res.json({
            id_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbiIsIm5hbWUiOiJBZG1pbmlzdHJhdG9yIiwiaWF0IjoxNTE2MjM5MDIyfQ.mock-jwt-token-for-testing',
            authenticated: true
        });
    } else {
        res.status(400).json({
            error: 'Invalid verification code',
            message: 'The verification code is invalid or has expired'
        });
    }
});

// Mock login endpoint
app.post('/api/authenticate', (req, res) => {
    const { username, password } = req.body;
    console.log(`POST /api/authenticate - username: ${username}`);
    
    // For testing: require TOTP for admin user
    if (username === 'admin' && password === 'admin') {
        res.json({
            authenticated: false,
            requiresTwoFactor: true,
            message: 'Two-factor authentication required'
        });
    } else {
        res.status(401).json({
            error: 'Authentication failed',
            message: 'Invalid username or password'
        });
    }
});

// Mock user account endpoint
app.get('/api/account', (req, res) => {
    console.log('GET /api/account');
    
    // Return proper user account data with authorities and tenant info
    res.json({
        activated: true,
        authorities: ['ROLE_ADMIN', 'ROLE_USER'],
        email: 'admin@localhost',
        firstName: 'Admin',
        lastName: 'User',
        login: 'admin',
        langKey: 'en',
        imageUrl: null,
        openvasUserID: 1,
        openvasUserUUID: 'admin-uuid-123',
        tenantId: 'b621d671-dd5a-4870-ba84-299e741e4a2e',
        tenantSubdomain: 'default'
    });
});

// Mock tenant endpoints
app.get('/api/tenants', (req, res) => {
    console.log('GET /api/tenants');
    res.json([
        {
            id: 'b621d671-dd5a-4870-ba84-299e741e4a2e',
            name: 'Default Organization',
            subdomain: 'default',
            status: 'active',
            tier: 'standard',
            createdAt: '2025-08-10T05:46:11.886Z',
            settings: {
                timezone: 'UTC',
                dateFormat: 'yyyy-MM-dd',
                theme: 'light'
            },
            resourceLimits: {
                maxUsers: 100,
                maxStorage: '10GB',
                maxElasticsearchIndices: 50
            }
        }
    ]);
});

app.get('/api/tenants/:id', (req, res) => {
    const tenantId = req.params.id;
    console.log(`GET /api/tenants/${tenantId}`);
    
    if (tenantId === 'b621d671-dd5a-4870-ba84-299e741e4a2e' || tenantId === 'default') {
        res.json({
            id: 'b621d671-dd5a-4870-ba84-299e741e4a2e',
            name: 'Default Organization',
            subdomain: 'default',
            status: 'active',
            tier: 'standard',
            createdAt: '2025-08-10T05:46:11.886Z',
            updatedAt: '2025-08-10T05:46:11.886Z',
            settings: {
                timezone: 'UTC',
                dateFormat: 'yyyy-MM-dd',
                theme: 'light'
            },
            resourceLimits: {
                maxUsers: 100,
                maxStorage: '10GB',
                maxElasticsearchIndices: 50
            },
            configurations: [
                { configKey: 'max_users', configValue: '100', configType: 'INTEGER' },
                { configKey: 'max_storage_gb', configValue: '10', configType: 'INTEGER' },
                { configKey: 'elasticsearch_retention_days', configValue: '30', configType: 'INTEGER' },
                { configKey: 'log_level', configValue: 'INFO', configType: 'STRING' },
                { configKey: 'enable_monitoring', configValue: 'true', configType: 'BOOLEAN' },
                { configKey: 'enable_alerting', configValue: 'true', configType: 'BOOLEAN' }
            ],
            roles: [
                { roleName: 'TENANT_ADMIN', permissions: ['READ', 'WRITE', 'DELETE', 'ADMIN', 'USER_MANAGEMENT', 'SYSTEM_CONFIG'] },
                { roleName: 'TENANT_USER', permissions: ['READ', 'WRITE'] },
                { roleName: 'TENANT_VIEWER', permissions: ['READ'] }
            ]
        });
    } else {
        res.status(404).json({ error: 'Tenant not found' });
    }
});

// Current tenant context endpoint
app.get('/api/tenant/current', (req, res) => {
    console.log('GET /api/tenant/current');
    res.json({
        id: 'b621d671-dd5a-4870-ba84-299e741e4a2e',
        name: 'Default Organization',
        subdomain: 'default',
        status: 'active',
        tier: 'standard'
    });
});

// Default handler for unknown routes
app.use((req, res) => {
    console.log(`${req.method} ${req.path}`);
    res.json({
        message: 'Mock API endpoint',
        path: req.path,
        method: req.method,
        status: 'ok'
    });
});

// Start server
const PORT = 8090;
app.listen(PORT, () => {
    console.log(`🚀 Simple API Mock listening on http://localhost:${PORT}`);
    console.log(`📡 CORS enabled for all origins`);
});
