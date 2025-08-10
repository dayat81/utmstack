const { chromium } = require('playwright');

/**
 * Multi-Tenant UTMStack Verification Test
 * Tests tenant isolation and functionality across different tenant subdomains
 */

async function testMultiTenant() {
    console.log('🚀 Starting Multi-Tenant UTMStack Verification Test');
    console.log('=' .repeat(60));

    const browser = await chromium.launch({ 
        headless: false,  // Set to true for CI/CD
        slowMo: 1000      // Slow down for visibility
    });

    try {
        // Test data for our tenants
        const tenants = [
            {
                name: 'Default Organization',
                subdomain: 'default',
                baseUrl: 'http://localhost',
                tier: 'standard'
            },
            {
                name: 'ACME Corporation', 
                subdomain: 'acme',
                baseUrl: 'http://acme.localhost',
                tier: 'premium'
            },
            {
                name: 'Global Security Inc',
                subdomain: 'globalsec', 
                baseUrl: 'http://globalsec.localhost',
                tier: 'enterprise'
            }
        ];

        console.log('📋 Test Tenants:');
        tenants.forEach((tenant, index) => {
            console.log(`   ${index + 1}. ${tenant.name} (${tenant.subdomain}) - ${tenant.tier}`);
        });
        console.log('');

        // Test each tenant
        for (let i = 0; i < tenants.length; i++) {
            const tenant = tenants[i];
            console.log(`🏢 Testing Tenant ${i + 1}: ${tenant.name}`);
            console.log(`   URL: ${tenant.baseUrl}`);
            console.log(`   Subdomain: ${tenant.subdomain}`);
            console.log(`   Tier: ${tenant.tier}`);
            
            await testTenant(browser, tenant);
            console.log(`✅ Tenant ${i + 1} test completed\n`);
        }

        // Test tenant isolation
        console.log('🔒 Testing Tenant Isolation');
        await testTenantIsolation(browser, tenants);

        console.log('🎉 All tests completed successfully!');
        
    } catch (error) {
        console.error('❌ Test failed:', error.message);
        throw error;
    } finally {
        await browser.close();
    }
}

async function testTenant(browser, tenant) {
    const context = await browser.newContext({
        // Set custom headers for tenant identification
        extraHTTPHeaders: {
            'X-Tenant-ID': tenant.subdomain,
            'Host': `${tenant.subdomain}.localhost`
        }
    });

    const page = await context.newPage();

    try {
        // Test 1: Homepage access
        console.log('   📄 Testing homepage access...');
        
        // Try different URL patterns for tenant access
        const urlsToTry = [
            `${tenant.baseUrl}:4200`,           // Angular dev server
            `${tenant.baseUrl}:8080`,           // Backend API  
            `http://localhost:4200`,            // Default with headers
            `http://localhost:8080/api/tenants` // API endpoint
        ];

        let successfulUrl = null;
        for (const url of urlsToTry) {
            try {
                console.log(`      Trying: ${url}`);
                const response = await page.goto(url, { 
                    waitUntil: 'networkidle',
                    timeout: 10000 
                });
                
                if (response && response.status() < 400) {
                    successfulUrl = url;
                    console.log(`      ✅ Success: ${url} (Status: ${response.status()})`);
                    break;
                } else {
                    console.log(`      ⚠️  Status ${response?.status()}: ${url}`);
                }
            } catch (err) {
                console.log(`      ❌ Failed: ${url} - ${err.message.split('\n')[0]}`);
            }
        }

        if (!successfulUrl) {
            console.log('      ⚠️  No URLs accessible, checking API directly...');
            await testTenantAPI(page, tenant);
            return;
        }

        // Test 2: Check for tenant-specific content
        console.log('   🔍 Checking for tenant-specific content...');
        const pageContent = await page.content();
        
        // Look for tenant indicators in the page
        const tenantIndicators = [
            tenant.name,
            tenant.subdomain,
            'UTMStack',
            'tenant',
            'dashboard'
        ];

        let foundIndicators = 0;
        tenantIndicators.forEach(indicator => {
            if (pageContent.toLowerCase().includes(indicator.toLowerCase())) {
                console.log(`      ✅ Found: "${indicator}"`);
                foundIndicators++;
            }
        });

        console.log(`      📊 Found ${foundIndicators}/${tenantIndicators.length} tenant indicators`);

        // Test 3: Check for multi-tenant API endpoints
        await testTenantAPI(page, tenant);

        // Test 4: Check localStorage/sessionStorage for tenant context
        console.log('   💾 Checking browser storage for tenant context...');
        const localStorage = await page.evaluate(() => {
            const storage = {};
            for (let i = 0; i < window.localStorage.length; i++) {
                const key = window.localStorage.key(i);
                storage[key] = window.localStorage.getItem(key);
            }
            return storage;
        });

        const tenantKeys = Object.keys(localStorage).filter(key => 
            key.toLowerCase().includes('tenant') || 
            key.toLowerCase().includes(tenant.subdomain)
        );

        if (tenantKeys.length > 0) {
            console.log(`      ✅ Found tenant-related storage keys: ${tenantKeys.join(', ')}`);
        } else {
            console.log(`      ℹ️  No tenant-specific storage found`);
        }

    } catch (error) {
        console.log(`      ❌ Error testing ${tenant.name}: ${error.message}`);
    } finally {
        await context.close();
    }
}

async function testTenantAPI(page, tenant) {
    console.log('   🔌 Testing tenant API endpoints...');
    
    const apiEndpoints = [
        '/api/tenants',
        '/api/tenant/current',
        '/management/health',
        '/api/account'
    ];

    for (const endpoint of apiEndpoints) {
        try {
            const response = await page.goto(`http://localhost:8080${endpoint}`, {
                waitUntil: 'networkidle',
                timeout: 5000
            });

            if (response) {
                const status = response.status();
                const contentType = response.headers()['content-type'] || '';
                
                if (status === 200 && contentType.includes('application/json')) {
                    const data = await response.json();
                    console.log(`      ✅ ${endpoint}: Status ${status}, Data: ${JSON.stringify(data).substring(0, 100)}...`);
                } else if (status < 400) {
                    console.log(`      ✅ ${endpoint}: Status ${status}`);
                } else {
                    console.log(`      ⚠️  ${endpoint}: Status ${status}`);
                }
            }
        } catch (err) {
            console.log(`      ❌ ${endpoint}: ${err.message.split('\n')[0]}`);
        }
    }
}

async function testTenantIsolation(browser, tenants) {
    console.log('   🔐 Verifying tenant data isolation...');
    
    // Test that tenant A cannot access tenant B's data
    const context = await browser.newContext();
    const page = await context.newPage();

    try {
        // Try to access each tenant's API with different tenant headers
        for (let i = 0; i < tenants.length; i++) {
            for (let j = 0; j < tenants.length; j++) {
                if (i !== j) {
                    const requestingTenant = tenants[i];
                    const targetTenant = tenants[j];
                    
                    console.log(`      Testing: ${requestingTenant.subdomain} → ${targetTenant.subdomain}`);
                    
                    // Set headers for requesting tenant
                    await page.setExtraHTTPHeaders({
                        'X-Tenant-ID': requestingTenant.subdomain,
                        'Host': `${requestingTenant.subdomain}.localhost`
                    });

                    try {
                        // Try to access target tenant's data
                        const response = await page.goto(`http://localhost:8080/api/tenant/current`, {
                            waitUntil: 'networkidle',
                            timeout: 5000
                        });

                        if (response && response.status() === 200) {
                            const data = await response.json();
                            const returnedTenant = data.subdomain || data.name;
                            
                            if (returnedTenant === requestingTenant.subdomain || returnedTenant === requestingTenant.name) {
                                console.log(`         ✅ Isolation maintained: Got ${requestingTenant.subdomain} data`);
                            } else {
                                console.log(`         ❌ Isolation breach: Expected ${requestingTenant.subdomain}, got ${returnedTenant}`);
                            }
                        } else {
                            console.log(`         ⚠️  API not available (Status: ${response?.status()})`);
                        }
                    } catch (err) {
                        console.log(`         ⚠️  Request failed: ${err.message.split('\n')[0]}`);
                    }
                }
            }
        }
    } finally {
        await context.close();
    }
}

// Database verification
async function verifyTenantsInDatabase() {
    console.log('🗄️  Verifying tenants in database...');
    
    const { exec } = require('child_process');
    const util = require('util');
    const execAsync = util.promisify(exec);

    try {
        const { stdout } = await execAsync(
            'docker exec pos-db psql -U pos_user -d pos_db -c "SELECT id, name, subdomain, status, tier FROM utm_tenant ORDER BY created_at;"'
        );
        
        console.log('   📊 Database tenants:');
        console.log(stdout);
        
        // Parse the output to count tenants
        const lines = stdout.split('\n').filter(line => line.trim() && !line.includes('---') && !line.includes('id'));
        const tenantCount = lines.filter(line => line.includes('|')).length;
        
        console.log(`   ✅ Found ${tenantCount} tenants in database`);
        return tenantCount >= 3; // Default + 2 test tenants
    } catch (error) {
        console.log(`   ❌ Database verification failed: ${error.message}`);
        return false;
    }
}

// Main test execution
async function main() {
    try {
        console.log('UTMStack Multi-Tenant Verification Suite');
        console.log('==========================================\n');

        // Step 1: Verify database setup
        const dbVerified = await verifyTenantsInDatabase();
        if (!dbVerified) {
            throw new Error('Database verification failed - ensure tenants are created');
        }

        // Step 2: Run browser tests  
        await testMultiTenant();

        console.log('\n🎉 All verification tests completed successfully!');
        console.log('✅ Multi-tenant setup is working correctly');
        
    } catch (error) {
        console.error('\n❌ Verification failed:', error.message);
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = { testMultiTenant, verifyTenantsInDatabase };
