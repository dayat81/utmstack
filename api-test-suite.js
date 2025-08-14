#!/usr/bin/env node

/**
 * UTMStack Backend API Test Suite
 * Tests all API endpoints listed in BACKEND_API.md
 * Usage: node api-test-suite.js [--host=localhost:8080] [--timeout=5000]
 */

const http = require('http');
const https = require('https');
const querystring = require('querystring');

// Configuration
const config = {
    host: process.argv.find(arg => arg.startsWith('--host='))?.split('=')[1] || 'localhost:8080',
    timeout: parseInt(process.argv.find(arg => arg.startsWith('--timeout='))?.split('=')[1]) || 5000,
    verbose: process.argv.includes('--verbose'),
    skipAuth: process.argv.includes('--skip-auth')
};

// ANSI colors for output
const colors = {
    reset: '\x1b[0m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m',
    purple: '\x1b[35m'
};

// Test results tracking
let testResults = {
    total: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    results: []
};

// API endpoints from BACKEND_API.md
const apiEndpoints = [
    // Incident Management
    { method: 'POST', path: '/api/utm-incident-alerts', category: 'Incident Management', requiresAuth: true, requiresBody: true },
    { method: 'POST', path: '/api/utm-incident-alerts/update-status', category: 'Incident Management', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/utm-incident-alerts', category: 'Incident Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-incident-alerts', category: 'Incident Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-incident-histories', category: 'Incident Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-incident-histories/count', category: 'Incident Management', requiresAuth: true },
    { method: 'POST', path: '/api/utm-incident-notes', category: 'Incident Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-incident-notes', category: 'Incident Management', requiresAuth: true },
    { method: 'POST', path: '/api/utm-incidents', category: 'Incident Management', requiresAuth: true, requiresBody: true },
    { method: 'POST', path: '/api/utm-incidents/add-alerts', category: 'Incident Management', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/utm-incidents/change-status', category: 'Incident Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-incidents', category: 'Incident Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-incidents/users-assigned', category: 'Incident Management', requiresAuth: true },

    // Alert Management
    { method: 'POST', path: '/api/utm-alerts/status', category: 'Alert Management', requiresAuth: true, requiresBody: true },
    { method: 'POST', path: '/api/utm-alerts/notes', category: 'Alert Management', requiresAuth: true, requiresBody: true },
    { method: 'POST', path: '/api/utm-alerts/tags', category: 'Alert Management', requiresAuth: true, requiresBody: true },
    { method: 'POST', path: '/api/utm-alerts/convert-to-incident', category: 'Alert Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-alerts/count-open-alerts', category: 'Alert Management', requiresAuth: true },
    { method: 'POST', path: '/api/utm-alert-tags', category: 'Alert Management', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/utm-alert-tags', category: 'Alert Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-alert-tags', category: 'Alert Management', requiresAuth: true },

    // Log Analysis
    { method: 'POST', path: '/api/log-analyzer/queries', category: 'Log Analysis', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/log-analyzer/queries', category: 'Log Analysis', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/log-analyzer/queries', category: 'Log Analysis', requiresAuth: true },
    { method: 'POST', path: '/api/log-analyzer/chart-view', category: 'Log Analysis', requiresAuth: true, requiresBody: true },

    // Asset Management
    { method: 'POST', path: '/api/utm-asset-groups', category: 'Asset Management', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/utm-asset-groups', category: 'Asset Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-asset-groups/searchGroupsByFilter', category: 'Asset Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-asset-types/all', category: 'Asset Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-network-scans', category: 'Asset Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-network-scans/count', category: 'Asset Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-network-scans/countNewAssets', category: 'Asset Management', requiresAuth: true },

    // Configuration
    { method: 'PUT', path: '/api/utm-configuration-parameters', category: 'Configuration', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-configuration-parameters', category: 'Configuration', requiresAuth: true },
    { method: 'GET', path: '/api/utm-configuration-sections', category: 'Configuration', requiresAuth: true },

    // Dashboards & Visualizations
    { method: 'POST', path: '/api/utm-dashboards', category: 'Dashboards', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/utm-dashboards', category: 'Dashboards', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-dashboards', category: 'Dashboards', requiresAuth: true },
    { method: 'POST', path: '/api/utm-visualizations', category: 'Dashboards', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/utm-visualizations', category: 'Dashboards', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-visualizations', category: 'Dashboards', requiresAuth: true },

    // Authentication & Users
    { method: 'POST', path: '/api/authenticate', category: 'Authentication', requiresAuth: false, requiresBody: true },
    { method: 'GET', path: '/api/account', category: 'Authentication', requiresAuth: true },
    { method: 'POST', path: '/api/account', category: 'Authentication', requiresAuth: true, requiresBody: true },
    { method: 'POST', path: '/api/account/change-password', category: 'Authentication', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/check-credentials', category: 'Authentication', requiresAuth: false },
    { method: 'POST', path: '/api/users', category: 'User Management', requiresAuth: true, requiresBody: true },
    { method: 'PUT', path: '/api/users', category: 'User Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/users', category: 'User Management', requiresAuth: true },
    { method: 'GET', path: '/api/users/authorities', category: 'User Management', requiresAuth: true },

    // System Health & Status
    { method: 'GET', path: '/api/ping', category: 'System Health', requiresAuth: false },
    { method: 'GET', path: '/api/healthcheck', category: 'System Health', requiresAuth: false },
    { method: 'GET', path: '/api/date-format', category: 'System Health', requiresAuth: false },
    { method: 'GET', path: '/api/isInDevelop', category: 'System Health', requiresAuth: false },

    // Overview & Reports
    { method: 'GET', path: '/api/overview/count-alerts-today-and-last-week', category: 'Overview', requiresAuth: true },
    { method: 'GET', path: '/api/overview/count-alerts-by-status', category: 'Overview', requiresAuth: true },
    { method: 'GET', path: '/api/overview/top-alerts', category: 'Overview', requiresAuth: true },
    { method: 'GET', path: '/api/overview/count-alerts-by-severity', category: 'Overview', requiresAuth: true },
    { method: 'GET', path: '/api/overview/top-alerts-by-category', category: 'Overview', requiresAuth: true },

    // Agent Management
    { method: 'GET', path: '/api/agent-manager/agents', category: 'Agent Management', requiresAuth: true },
    { method: 'GET', path: '/api/agent-manager/agents-with-commands', category: 'Agent Management', requiresAuth: true },
    { method: 'GET', path: '/api/agent-manager/agent-by-hostname', category: 'Agent Management', requiresAuth: true },
    { method: 'GET', path: '/api/agent-manager/agent-commands', category: 'Agent Management', requiresAuth: true },

    // Modules
    { method: 'PUT', path: '/api/utm-modules/activateDeactivate', category: 'Module Management', requiresAuth: true, requiresBody: true },
    { method: 'GET', path: '/api/utm-modules', category: 'Module Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-modules/moduleDetails', category: 'Module Management', requiresAuth: true },
    { method: 'GET', path: '/api/utm-modules/moduleCategories', category: 'Module Management', requiresAuth: true },
];

// Helper functions
function log(message, color = 'reset') {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

function makeRequest(method, path, headers = {}, body = null) {
    return new Promise((resolve, reject) => {
        const [hostname, port] = config.host.split(':');
        const options = {
            hostname,
            port: port || 80,
            path,
            method,
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'UTMStack-API-Test-Suite/1.0',
                ...headers
            },
            timeout: config.timeout
        };

        if (body) {
            const bodyStr = typeof body === 'string' ? body : JSON.stringify(body);
            options.headers['Content-Length'] = Buffer.byteLength(bodyStr);
        }

        const protocol = options.port === 443 ? https : http;
        const req = protocol.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                resolve({
                    statusCode: res.statusCode,
                    headers: res.headers,
                    body: data,
                    bodyParsed: (() => {
                        try { return JSON.parse(data); }
                        catch { return data; }
                    })()
                });
            });
        });

        req.on('timeout', () => {
            req.destroy();
            reject(new Error(`Request timeout after ${config.timeout}ms`));
        });

        req.on('error', reject);

        if (body) {
            req.write(typeof body === 'string' ? body : JSON.stringify(body));
        }

        req.end();
    });
}

// Generate test body based on endpoint
function generateTestBody(endpoint) {
    const sampleBodies = {
        '/api/authenticate': { login: 'test', password: 'test', rememberMe: false },
        '/api/users': { login: 'testuser', email: 'test@example.com', firstName: 'Test', lastName: 'User' },
        '/api/utm-dashboards': { name: 'Test Dashboard', description: 'Test dashboard description' },
        '/api/utm-visualizations': { name: 'Test Visualization', type: 'LINE_CHART' },
        '/api/utm-incidents': { name: 'Test Incident', description: 'Test incident description' },
        '/api/utm-alert-tags': { tagName: 'test-tag', tagColor: '#FF0000' },
        '/api/log-analyzer/queries': { name: 'Test Query', query: '*', indexPattern: 'logstash-*' },
    };

    for (const [path, body] of Object.entries(sampleBodies)) {
        if (endpoint.path.startsWith(path)) {
            return body;
        }
    }
    
    return { test: true, timestamp: new Date().toISOString() };
}

// Test single endpoint
async function testEndpoint(endpoint) {
    testResults.total++;
    
    try {
        const headers = {};
        let body = null;
        
        // Add auth header if required (mock token for testing connectivity)
        if (endpoint.requiresAuth && !config.skipAuth) {
            headers['Authorization'] = 'Bearer mock-test-token';
        }
        
        // Add body for POST/PUT requests
        if (endpoint.requiresBody && ['POST', 'PUT'].includes(endpoint.method)) {
            body = generateTestBody(endpoint);
        }

        if (config.verbose) {
            log(`Testing ${endpoint.method} ${endpoint.path}`, 'cyan');
        }

        const response = await makeRequest(endpoint.method, endpoint.path, headers, body);
        
        // Determine test result
        let status, message, color;
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
            status = 'PASS';
            message = `✓ ${response.statusCode}`;
            color = 'green';
            testResults.passed++;
        } else if (response.statusCode === 401 && endpoint.requiresAuth) {
            status = 'AUTH_REQUIRED';
            message = `⚠ 401 (Auth required - expected)`;
            color = 'yellow';
            testResults.passed++; // This is expected behavior
        } else if (response.statusCode === 404) {
            status = 'NOT_FOUND';
            message = `⚠ 404 (Endpoint not found)`;
            color = 'yellow';
            testResults.failed++;
        } else if (response.statusCode >= 400) {
            status = 'CLIENT_ERROR';
            message = `✗ ${response.statusCode}`;
            color = 'red';
            testResults.failed++;
        } else if (response.statusCode >= 500) {
            status = 'SERVER_ERROR';
            message = `✗ ${response.statusCode} (Server error)`;
            color = 'red';
            testResults.failed++;
        } else {
            status = 'UNKNOWN';
            message = `? ${response.statusCode}`;
            color = 'purple';
            testResults.failed++;
        }

        const result = {
            endpoint: `${endpoint.method} ${endpoint.path}`,
            category: endpoint.category,
            status,
            statusCode: response.statusCode,
            message,
            responseTime: Date.now() - testResults.startTime,
            requiresAuth: endpoint.requiresAuth
        };

        testResults.results.push(result);
        
        if (!config.verbose) {
            process.stdout.write(status === 'PASS' || status === 'AUTH_REQUIRED' ? 
                colors.green + '.' + colors.reset : 
                colors.red + 'F' + colors.reset
            );
        } else {
            log(`  ${message} - ${endpoint.category}`, color);
        }
        
    } catch (error) {
        testResults.failed++;
        const result = {
            endpoint: `${endpoint.method} ${endpoint.path}`,
            category: endpoint.category,
            status: 'ERROR',
            message: `✗ ${error.message}`,
            error: error.message,
            requiresAuth: endpoint.requiresAuth
        };
        testResults.results.push(result);
        
        if (config.verbose) {
            log(`  ✗ ERROR: ${error.message}`, 'red');
        } else {
            process.stdout.write(colors.red + 'E' + colors.reset);
        }
    }
}

// Generate test report
function generateReport() {
    log('\n\n' + '='.repeat(80), 'blue');
    log('UTM STACK API TEST SUITE RESULTS', 'blue');
    log('='.repeat(80), 'blue');
    
    log(`\nTest Summary:`, 'cyan');
    log(`  Total endpoints tested: ${testResults.total}`);
    log(`  Passed: ${testResults.passed}`, 'green');
    log(`  Failed: ${testResults.failed}`, 'red');
    log(`  Success rate: ${((testResults.passed / testResults.total) * 100).toFixed(1)}%`);
    log(`  Test duration: ${((Date.now() - testResults.startTime) / 1000).toFixed(2)}s`);
    
    // Group results by category
    const categories = {};
    testResults.results.forEach(result => {
        if (!categories[result.category]) {
            categories[result.category] = { passed: 0, failed: 0, total: 0, results: [] };
        }
        categories[result.category].total++;
        categories[result.category].results.push(result);
        if (result.status === 'PASS' || result.status === 'AUTH_REQUIRED') {
            categories[result.category].passed++;
        } else {
            categories[result.category].failed++;
        }
    });
    
    log('\nResults by Category:', 'cyan');
    Object.entries(categories).forEach(([category, stats]) => {
        const successRate = ((stats.passed / stats.total) * 100).toFixed(1);
        const color = stats.failed === 0 ? 'green' : stats.failed < stats.passed ? 'yellow' : 'red';
        log(`  ${category}: ${stats.passed}/${stats.total} (${successRate}%)`, color);
    });
    
    // Show failures
    const failures = testResults.results.filter(r => 
        r.status === 'ERROR' || r.status === 'SERVER_ERROR' || r.status === 'NOT_FOUND'
    );
    
    if (failures.length > 0) {
        log('\nFailed Endpoints:', 'red');
        failures.forEach(failure => {
            log(`  ${failure.endpoint} - ${failure.message}`, 'red');
            if (failure.error) {
                log(`    Error: ${failure.error}`, 'red');
            }
        });
    }
    
    // Show authentication-required endpoints (informational)
    const authRequired = testResults.results.filter(r => r.status === 'AUTH_REQUIRED');
    if (authRequired.length > 0) {
        log('\nEndpoints Requiring Authentication:', 'yellow');
        authRequired.forEach(auth => {
            log(`  ${auth.endpoint}`, 'yellow');
        });
    }
    
    log('\nService Status:', 'cyan');
    const serviceStatus = testResults.failed === 0 ? 'HEALTHY' : 
                         testResults.passed > testResults.failed ? 'PARTIALLY_HEALTHY' : 'UNHEALTHY';
    const statusColor = serviceStatus === 'HEALTHY' ? 'green' : 
                       serviceStatus === 'PARTIALLY_HEALTHY' ? 'yellow' : 'red';
    log(`  Backend API Service: ${serviceStatus}`, statusColor);
    
    log('\n' + '='.repeat(80), 'blue');
}

// Main execution
async function main() {
    log('UTMStack Backend API Test Suite', 'blue');
    log(`Testing ${apiEndpoints.length} endpoints on ${config.host}`, 'cyan');
    log(`Timeout: ${config.timeout}ms | Auth: ${config.skipAuth ? 'Skipped' : 'Mock Token'}`, 'cyan');
    log('-'.repeat(80));
    
    testResults.startTime = Date.now();
    
    // Run tests with limited concurrency to avoid overwhelming the server
    const concurrency = 5;
    for (let i = 0; i < apiEndpoints.length; i += concurrency) {
        const batch = apiEndpoints.slice(i, i + concurrency);
        await Promise.all(batch.map(testEndpoint));
    }
    
    generateReport();
    
    // Exit with appropriate code
    process.exit(testResults.failed > testResults.passed ? 1 : 0);
}

// Handle CLI help
if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log(`
UTMStack Backend API Test Suite

Usage: node api-test-suite.js [OPTIONS]

Options:
  --host=HOST:PORT     API host and port (default: localhost:8080)
  --timeout=MS         Request timeout in milliseconds (default: 5000)
  --verbose            Show detailed output for each test
  --skip-auth          Skip adding Authorization headers
  --help, -h           Show this help message

Examples:
  node api-test-suite.js
  node api-test-suite.js --host=production.utmstack.com:8080 --verbose
  node api-test-suite.js --skip-auth --timeout=10000
`);
    process.exit(0);
}

main().catch(error => {
    log(`Fatal error: ${error.message}`, 'red');
    process.exit(1);
});
