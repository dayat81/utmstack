const { chromium } = require('playwright');

/**
 * UTMStack Three Tenants GUI Dashboard Test
 * Tests the GUI dashboard for 3 different tenants in the database
 */

async function testThreeTenantsGUI() {
    console.log('🎯 UTMStack Three Tenants GUI Dashboard Test');
    console.log('===========================================\n');

    // Test configuration
    const config = {
        frontendUrl: 'http://localhost:4200',
        backendUrl: 'http://localhost:8080',
        timeout: 30000,
        screenshot: true,
        headless: false,
        slowMo: 1000
    };

    // Three test tenants for database testing
    const tenants = [
        {
            name: 'Default Organization',
            subdomain: 'default',
            id: 'b621d671-dd5a-4870-ba84-299e741e4a2e',
            tier: 'standard',
            credentials: { username: 'admin', password: 'admin' },
            totpCode: '123456'
        },
        {
            name: 'ACME Corporation',
            subdomain: 'acme',
            id: '550e8400-e29b-41d4-a716-446655440000',
            tier: 'premium',
            credentials: { username: 'acme-admin', password: 'acme123' },
            totpCode: '654321'
        },
        {
            name: 'Global Security Inc',
            subdomain: 'globalsec',
            id: '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
            tier: 'enterprise',
            credentials: { username: 'global-admin', password: 'global456' },
            totpCode: '789012'
        }
    ];

    const browser = await chromium.launch({ 
        headless: config.headless,
        slowMo: config.slowMo,
        args: ['--disable-web-security', '--disable-features=VizDisplayCompositor']
    });

    const results = [];

    try {
        console.log(`🌐 Testing frontend at: ${config.frontendUrl}`);
        console.log(`🔌 Backend API at: ${config.backendUrl}\n`);

        // Test each tenant's GUI dashboard
        for (let i = 0; i < tenants.length; i++) {
            const tenant = tenants[i];
            console.log(`🏢 Testing GUI Dashboard ${i + 1}/3: ${tenant.name}`);
            console.log(`   📋 Subdomain: ${tenant.subdomain}`);
            console.log(`   🎫 Tenant ID: ${tenant.id}`);
            console.log(`   ⭐ Tier: ${tenant.tier}\n`);
            
            const result = await testTenantGUIDashboard(browser, tenant, config);
            results.push(result);
            
            console.log(`${result.success ? '✅' : '❌'} Completed GUI test for ${tenant.name}\n`);
            
            // Wait between tests to avoid conflicts
            await new Promise(resolve => setTimeout(resolve, 2000));
        }

        // Generate comprehensive report
        await generateTestReport(tenants, results, config);

        console.log('🎉 All three tenants GUI dashboard tests completed!');

    } catch (error) {
        console.error('❌ GUI test suite failed:', error.message);
        throw error;
    } finally {
        await browser.close();
    }

    return results;
}

async function testTenantGUIDashboard(browser, tenant, config) {
    const context = await browser.newContext({
        viewport: { width: 1920, height: 1080 },
        extraHTTPHeaders: {
            'X-Tenant-ID': tenant.subdomain,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        }
    });

    const page = await context.newPage();
    const testResult = {
        tenant: tenant.name,
        subdomain: tenant.subdomain,
        success: false,
        loginSuccess: false,
        dashboardAccess: false,
        tenantDataFound: false,
        screenshotTaken: false,
        errors: []
    };

    try {
        // Monitor API calls for tenant context
        page.on('request', request => {
            if (request.url().includes('/api/tenant') || request.url().includes('/api/account')) {
                console.log(`   🔗 API Call: ${request.method()} ${request.url().split('/api/')[1]}`);
            }
        });

        page.on('response', response => {
            if (response.url().includes('/api/tenant/current')) {
                console.log(`   🏢 Tenant API Response: ${response.status()}`);
            }
            if (response.url().includes('/api/account')) {
                console.log(`   👤 Account API Response: ${response.status()}`);
            }
        });

        // Step 1: Navigate to login page
        console.log('   🔐 Step 1: Navigating to login page...');
        await page.goto(config.frontendUrl, { 
            waitUntil: 'networkidle',
            timeout: config.timeout 
        });

        // Step 2: Perform login
        console.log('   🔑 Step 2: Performing login...');
        try {
            await page.fill('input[name="username"], [formControlName="username"]', tenant.credentials.username);
            await page.fill('input[name="password"], [formControlName="password"]', tenant.credentials.password);
            await page.locator('button[type="submit"]').first().click();
            
            await page.waitForTimeout(2000);
            testResult.loginSuccess = true;
            console.log('   ✅ Login credentials submitted');
        } catch (error) {
            testResult.errors.push(`Login failed: ${error.message}`);
            console.log(`   ❌ Login failed: ${error.message}`);
        }

        // Step 3: Handle TOTP if required
        console.log('   🔢 Step 3: Checking for TOTP requirement...');
        if (page.url().includes('/totp')) {
            try {
                await page.fill('input[name="code"]', tenant.totpCode);
                await page.locator('button').first().click();
                await page.waitForTimeout(3000);
                console.log('   ✅ TOTP verification completed');
            } catch (error) {
                testResult.errors.push(`TOTP failed: ${error.message}`);
                console.log(`   ❌ TOTP failed: ${error.message}`);
            }
        } else {
            console.log('   ℹ️  No TOTP required');
        }

        // Step 4: Navigate to dashboard
        console.log('   📊 Step 4: Accessing tenant dashboard...');
        try {
            await page.goto(`${config.frontendUrl}/dashboard/overview`, {
                waitUntil: 'networkidle',
                timeout: config.timeout
            });
            await page.waitForTimeout(3000);

            const currentUrl = page.url();
            const pageTitle = await page.title();

            if (currentUrl.includes('/dashboard') && !currentUrl.includes('/login')) {
                testResult.dashboardAccess = true;
                console.log(`   ✅ Dashboard accessible at: ${currentUrl}`);
                console.log(`   📄 Page title: "${pageTitle}"`);
            } else {
                testResult.errors.push(`Dashboard not accessible, redirected to: ${currentUrl}`);
                console.log(`   ❌ Dashboard not accessible, redirected to: ${currentUrl}`);
            }
        } catch (error) {
            testResult.errors.push(`Dashboard access failed: ${error.message}`);
            console.log(`   ❌ Dashboard access failed: ${error.message}`);
        }

        // Step 5: Verify tenant-specific data
        console.log('   🔍 Step 5: Verifying tenant-specific data...');
        try {
            const pageContent = await page.content();
            const tenantIndicators = [
                tenant.name,
                tenant.subdomain,
                tenant.id,
                'dashboard'
            ];

            let foundIndicators = 0;
            for (const indicator of tenantIndicators) {
                if (pageContent.toLowerCase().includes(indicator.toLowerCase())) {
                    console.log(`      ✅ Found tenant indicator: "${indicator}"`);
                    foundIndicators++;
                }
            }

            if (foundIndicators > 0) {
                testResult.tenantDataFound = true;
                console.log(`   ✅ Tenant data verification: ${foundIndicators}/${tenantIndicators.length} indicators found`);
            } else {
                testResult.errors.push('No tenant-specific data found in dashboard');
                console.log('   ❌ No tenant-specific data found in dashboard');
            }
        } catch (error) {
            testResult.errors.push(`Tenant data verification failed: ${error.message}`);
            console.log(`   ❌ Tenant data verification failed: ${error.message}`);
        }

        // Step 6: Test tenant API calls
        console.log('   🌐 Step 6: Testing tenant API calls...');
        try {
            const apiResponse = await page.evaluate(async (backendUrl) => {
                try {
                    const response = await fetch(`${backendUrl}/api/tenant/current`);
                    const data = await response.json();
                    return { status: response.status, data };
                } catch (err) {
                    return { error: err.message };
                }
            }, config.backendUrl);

            if (apiResponse.data && apiResponse.data.subdomain === tenant.subdomain) {
                console.log(`   ✅ API confirmed tenant: ${apiResponse.data.name} (${apiResponse.data.subdomain})`);
            } else if (apiResponse.error) {
                testResult.errors.push(`API call failed: ${apiResponse.error}`);
                console.log(`   ❌ API call failed: ${apiResponse.error}`);
            } else {
                testResult.errors.push(`API returned wrong tenant data`);
                console.log(`   ❌ API returned wrong tenant data`);
            }
        } catch (error) {
            testResult.errors.push(`API test failed: ${error.message}`);
            console.log(`   ❌ API test failed: ${error.message}`);
        }

        // Step 7: Take screenshot
        console.log('   📸 Step 7: Taking screenshot...');
        try {
            if (config.screenshot) {
                await page.screenshot({ 
                    path: `/home/ptsec/utmstack/gui-test-${tenant.subdomain}.png`,
                    fullPage: true 
                });
                testResult.screenshotTaken = true;
                console.log(`   ✅ Screenshot saved: gui-test-${tenant.subdomain}.png`);
            }
        } catch (error) {
            testResult.errors.push(`Screenshot failed: ${error.message}`);
            console.log(`   ❌ Screenshot failed: ${error.message}`);
        }

        // Step 8: Test navigation between different dashboard sections
        console.log('   🧭 Step 8: Testing dashboard navigation...');
        const dashboardSections = [
            '/dashboard/analytics',
            '/dashboard/alerts', 
            '/dashboard/reports'
        ];

        for (const section of dashboardSections) {
            try {
                await page.goto(`${config.frontendUrl}${section}`, { timeout: 15000 });
                await page.waitForTimeout(1000);
                
                if (page.url().includes(section.split('/').pop())) {
                    console.log(`      ✅ ${section.split('/').pop()} section accessible`);
                } else {
                    console.log(`      ⚠️  ${section.split('/').pop()} section redirected`);
                }
            } catch (error) {
                console.log(`      ❌ ${section.split('/').pop()} section failed: ${error.message}`);
            }
        }

        // Determine overall success
        testResult.success = testResult.loginSuccess && 
                           testResult.dashboardAccess && 
                           testResult.screenshotTaken &&
                           testResult.errors.length === 0;

    } catch (error) {
        testResult.errors.push(`Test execution failed: ${error.message}`);
        console.log(`   ❌ Test execution failed: ${error.message}`);
        
        // Take error screenshot
        try {
            if (config.screenshot) {
                await page.screenshot({ 
                    path: `/home/ptsec/utmstack/error-${tenant.subdomain}.png`,
                    fullPage: true 
                });
                console.log(`   📸 Error screenshot saved: error-${tenant.subdomain}.png`);
            }
        } catch (screenshotError) {
            console.log('   ⚠️  Could not save error screenshot');
        }
    } finally {
        await context.close();
    }

    return testResult;
}

async function generateTestReport(tenants, results, config) {
    console.log('\n📊 THREE TENANTS GUI DASHBOARD TEST REPORT');
    console.log('==========================================\n');

    const successfulTests = results.filter(r => r.success).length;
    const totalTests = results.length;

    console.log('📈 SUMMARY:');
    console.log(`   • Total tenants tested: ${totalTests}`);
    console.log(`   • Successful tests: ${successfulTests}`);
    console.log(`   • Failed tests: ${totalTests - successfulTests}`);
    console.log(`   • Success rate: ${Math.round((successfulTests / totalTests) * 100)}%\n`);

    console.log('🏢 TENANT RESULTS:');
    console.log('==================');
    
    for (let i = 0; i < results.length; i++) {
        const result = results[i];
        const tenant = tenants[i];
        
        console.log(`\n${i + 1}. ${result.tenant} (${result.subdomain})`);
        console.log(`   Overall Status: ${result.success ? '✅ PASS' : '❌ FAIL'}`);
        console.log(`   Login: ${result.loginSuccess ? '✅' : '❌'}`);
        console.log(`   Dashboard Access: ${result.dashboardAccess ? '✅' : '❌'}`);
        console.log(`   Tenant Data: ${result.tenantDataFound ? '✅' : '❌'}`);
        console.log(`   Screenshot: ${result.screenshotTaken ? '✅' : '❌'}`);
        
        if (result.errors.length > 0) {
            console.log(`   Errors:`);
            result.errors.forEach(error => console.log(`     • ${error}`));
        }
        
        console.log(`   Credentials: ${tenant.credentials.username}/${tenant.credentials.password}`);
        console.log(`   TOTP Code: ${tenant.totpCode}`);
    }

    console.log('\n📂 GENERATED FILES:');
    console.log('==================');
    
    tenants.forEach(tenant => {
        console.log(`📸 gui-test-${tenant.subdomain}.png - ${tenant.name} dashboard screenshot`);
    });

    console.log('\n🎯 DASHBOARD URLS FOR TESTING:');
    console.log('=============================');
    
    tenants.forEach(tenant => {
        console.log(`${tenant.name}:`);
        console.log(`   🌐 ${config.frontendUrl}/dashboard/overview`);
        console.log(`   🏢 X-Tenant-ID: ${tenant.subdomain}`);
        console.log(`   🎫 Tenant ID: ${tenant.id}`);
    });

    console.log('\n📋 RECOMMENDATIONS:');
    console.log('==================');
    
    if (successfulTests === totalTests) {
        console.log('✅ All tenant GUI dashboards are working correctly');
        console.log('✅ Multi-tenant isolation appears to be functioning');
        console.log('✅ Screenshots can be used for visual verification');
    } else {
        console.log('⚠️  Some tenant dashboards have issues - check error details above');
        console.log('💡 Verify backend services are running and accessible');
        console.log('💡 Check tenant database configuration');
        console.log('💡 Validate tenant authentication credentials');
    }
}

async function main() {
    try {
        console.log('UTMStack Three Tenants GUI Dashboard Test');
        console.log('========================================\n');

        // Pre-flight checks
        console.log('🔍 Pre-flight checks...');
        const { exec } = require('child_process');
        const util = require('util');
        const execAsync = util.promisify(exec);

        try {
            const { stdout: frontendCheck } = await execAsync('curl -s -o /dev/null -w "%{http_code}" http://localhost:4200');
            const { stdout: backendCheck } = await execAsync('curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/management/health');
            
            console.log(`✅ Frontend status: ${frontendCheck === '200' ? 'OK' : frontendCheck}`);
            console.log(`✅ Backend status: ${backendCheck === '200' ? 'OK' : backendCheck}`);
        } catch (err) {
            console.log('⚠️  Pre-flight checks failed - continuing anyway\n');
        }

        // Run the three tenant GUI tests
        const results = await testThreeTenantsGUI();

        const allPassed = results.every(r => r.success);
        
        if (allPassed) {
            console.log('\n🎉 ALL THREE TENANTS GUI DASHBOARD TESTS PASSED!');
            console.log('✅ Multi-tenant GUI system is working correctly');
        } else {
            console.log('\n⚠️  SOME TESTS FAILED - CHECK RESULTS ABOVE');
            console.log('💡 Review error details and fix issues before production');
        }

        return results;

    } catch (error) {
        console.error('\n❌ Test suite execution failed:', error.message);
        console.error('💡 Ensure both frontend (port 4200) and backend (port 8080) are running');
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = { testThreeTenantsGUI, testTenantGUIDashboard };
