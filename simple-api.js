#!/usr/bin/env node

/**
 * Simple UTMStack API Mock Server
 * Provides mock responses for testing API connectivity
 * Usage: node simple-api.js [--port=8080]
 */

const http = require('http');
const url = require('url');

const PORT = process.argv.find(arg => arg.startsWith('--port='))?.split('=')[1] || 8080;

// Mock data and responses
const mockResponses = {
    // Health endpoints
    '/api/ping': { status: 'pong', timestamp: () => new Date().toISOString() },
    '/api/healthcheck': { status: 'healthy', version: '1.0.0', uptime: () => process.uptime() },
    '/api/date-format': { format: 'yyyy-MM-dd HH:mm:ss', timezone: 'UTC' },
    '/api/isInDevelop': { isDevelop: true, environment: 'development' },
    '/api/check-credentials': { credentialsValid: false, message: 'Authentication required' },

    // Overview endpoints
    '/api/overview/count-alerts-today-and-last-week': {
        today: 15,
        lastWeek: 87,
        trend: 'increasing'
    },
    '/api/overview/count-alerts-by-status': {
        open: 8,
        acknowledged: 5,
        closed: 2,
        total: 15
    },
    '/api/overview/top-alerts': [
        { name: 'Suspicious Login Activity', count: 5, severity: 'high' },
        { name: 'Network Anomaly Detected', count: 3, severity: 'medium' },
        { name: 'Failed Authentication Attempts', count: 7, severity: 'low' }
    ],

    // Authentication endpoints
    '/api/account': { 
        login: 'admin', 
        email: 'admin@utmstack.local', 
        firstName: 'Administrator',
        lastName: 'User',
        authorities: ['ROLE_ADMIN']
    },

    // Asset Management
    '/api/utm-asset-types/all': [
        { id: 1, name: 'Server', category: 'infrastructure' },
        { id: 2, name: 'Workstation', category: 'endpoint' },
        { id: 3, name: 'Network Device', category: 'network' }
    ],
    '/api/utm-network-scans/count': { count: 45, lastScan: () => new Date().toISOString() },
    '/api/utm-network-scans/countNewAssets': { newAssets: 3, totalAssets: 45 },

    // Configuration
    '/api/utm-configuration-sections': [
        { id: 1, name: 'General', description: 'General system settings' },
        { id: 2, name: 'Security', description: 'Security configuration' },
        { id: 3, name: 'Logging', description: 'Logging configuration' }
    ],

    // Alert Management
    '/api/utm-alerts/count-open-alerts': { count: 8, criticalCount: 2, highCount: 3 },
    '/api/utm-alert-tags': [
        { id: 1, tagName: 'malware', tagColor: '#ff4444' },
        { id: 2, tagName: 'network-anomaly', tagColor: '#ffaa44' },
        { id: 3, tagName: 'authentication', tagColor: '#44aaff' }
    ],

    // Module Management  
    '/api/utm-modules': [
        { id: 1, name: 'Alert Manager', active: true, category: 'security' },
        { id: 2, name: 'Asset Discovery', active: true, category: 'asset-management' },
        { id: 3, name: 'Log Analyzer', active: false, category: 'analysis' }
    ],
    '/api/utm-modules/moduleCategories': [
        'security', 'asset-management', 'analysis', 'reporting'
    ],

    // Agent Management
    '/api/agent-manager/agents': [
        { id: 1, hostname: 'server-01', ip: '192.168.1.10', status: 'online', lastSeen: () => new Date().toISOString() },
        { id: 2, hostname: 'workstation-02', ip: '192.168.1.25', status: 'offline', lastSeen: () => new Date(Date.now() - 3600000).toISOString() }
    ],
    '/api/agent-manager/agent-commands': [
        { id: 1, name: 'collect-logs', description: 'Collect system logs' },
        { id: 2, name: 'scan-network', description: 'Network discovery scan' }
    ],

    // User Management
    '/api/users': [
        { login: 'admin', email: 'admin@utmstack.local', firstName: 'Administrator', lastName: 'User' },
        { login: 'analyst', email: 'analyst@utmstack.local', firstName: 'Security', lastName: 'Analyst' }
    ],
    '/api/users/authorities': ['ROLE_ADMIN', 'ROLE_ANALYST', 'ROLE_USER'],

    // Dashboards
    '/api/utm-dashboards': [
        { id: 1, name: 'Security Overview', description: 'Main security dashboard' },
        { id: 2, name: 'Asset Management', description: 'Asset monitoring dashboard' }
    ],
    '/api/utm-visualizations': [
        { id: 1, name: 'Alert Trend', type: 'LINE_CHART', dashboardId: 1 },
        { id: 2, name: 'Asset Status', type: 'PIE_CHART', dashboardId: 2 }
    ]
};

// Create HTTP server
const server = http.createServer((req, res) => {
    const parsedUrl = url.parse(req.url, true);
    const path = parsedUrl.pathname;
    const method = req.method;

    // CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    // Handle preflight
    if (method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    console.log(`${new Date().toISOString()} ${method} ${path}`);

    // Set content type
    res.setHeader('Content-Type', 'application/json');

    // Handle authentication check
    const authHeader = req.headers.authorization;
    const requiresAuth = !path.includes('/ping') && 
                        !path.includes('/healthcheck') && 
                        !path.includes('/date-format') && 
                        !path.includes('/isInDevelop') &&
                        !path.includes('/check-credentials') &&
                        !path.includes('/authenticate');

    if (requiresAuth && (!authHeader || !authHeader.includes('Bearer'))) {
        res.writeHead(401);
        res.end(JSON.stringify({ error: 'Authentication required', message: 'Please provide valid authorization token' }));
        return;
    }

    // Handle specific endpoints
    if (mockResponses[path]) {
        let responseData = mockResponses[path];
        
        // Execute functions in response data
        if (typeof responseData === 'object' && responseData !== null) {
            responseData = JSON.parse(JSON.stringify(responseData)); // Deep copy
            Object.keys(responseData).forEach(key => {
                if (typeof responseData[key] === 'function') {
                    responseData[key] = responseData[key]();
                }
            });
        }

        res.writeHead(200);
        res.end(JSON.stringify(responseData, null, 2));
        return;
    }

    // Handle POST/PUT requests with generic success response
    if (method === 'POST' || method === 'PUT') {
        let body = '';
        req.on('data', chunk => body += chunk.toString());
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                res.writeHead(200);
                res.end(JSON.stringify({ 
                    success: true, 
                    message: `${method} request processed successfully`,
                    id: Math.floor(Math.random() * 1000),
                    receivedData: data
                }));
            } catch (error) {
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid JSON', message: error.message }));
            }
        });
        return;
    }

    // Handle authentication endpoint
    if (path === '/api/authenticate' && method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk.toString());
        req.on('end', () => {
            try {
                const { login, password } = JSON.parse(body);
                if (login && password) {
                    res.writeHead(200);
                    res.end(JSON.stringify({
                        id_token: 'mock-jwt-token-12345',
                        user: { login, firstName: 'Test', lastName: 'User' }
                    }));
                } else {
                    res.writeHead(401);
                    res.end(JSON.stringify({ error: 'Invalid credentials' }));
                }
            } catch (error) {
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid request body' }));
            }
        });
        return;
    }

    // Handle DELETE requests
    if (method === 'DELETE') {
        res.writeHead(200);
        res.end(JSON.stringify({ success: true, message: 'Resource deleted successfully' }));
        return;
    }

    // Handle unknown GET endpoints with empty array/object
    if (method === 'GET') {
        if (path.includes('/count')) {
            res.writeHead(200);
            res.end(JSON.stringify({ count: 0 }));
        } else {
            res.writeHead(200);
            res.end(JSON.stringify([]));
        }
        return;
    }

    // Default 404
    res.writeHead(404);
    res.end(JSON.stringify({ 
        error: 'Not Found', 
        message: `Endpoint ${method} ${path} not found`,
        availableEndpoints: Object.keys(mockResponses)
    }));
});

// Start server
server.listen(PORT, () => {
    console.log(`🚀 UTMStack Mock API Server running on http://localhost:${PORT}`);
    console.log(`📊 Available endpoints: ${Object.keys(mockResponses).length}`);
    console.log(`📝 Logs will show all requests`);
    console.log(`🔐 Auth required for most endpoints (use Authorization: Bearer <token>)`);
    console.log('\n📋 Sample endpoints:');
    console.log(`  GET  http://localhost:${PORT}/api/ping`);
    console.log(`  GET  http://localhost:${PORT}/api/healthcheck`);
    console.log(`  POST http://localhost:${PORT}/api/authenticate`);
    console.log('\nPress Ctrl+C to stop the server\n');
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Stopping UTMStack Mock API Server...');
    server.close(() => {
        console.log('✅ Server stopped successfully');
        process.exit(0);
    });
});
