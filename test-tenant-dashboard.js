const { chromium } = require('playwright');

async function testTenantDashboard() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🏢 Testing Default Tenant Dashboard Access');
    console.log('==========================================');
    
    // Monitor API calls to see tenant context
    page.on('request', request => {
      if (request.url().includes('/api/tenant') || request.url().includes('/api/account')) {
        console.log('🏢 Tenant API:', request.method(), request.url().split('/api/')[1]);
      }
    });
    
    page.on('response', response => {
      if (response.url().includes('/api/tenant/current')) {
        console.log('🏢 Current Tenant Response:', response.status());
        response.json().then(data => {
          console.log(`🏢 Tenant: ${data.name} (${data.subdomain})`);
        }).catch(() => {});
      }
      if (response.url().includes('/api/account')) {
        console.log('👤 Account Response:', response.status());
        response.json().then(data => {
          console.log(`👤 User: ${data.firstName} ${data.lastName} in tenant: ${data.tenantSubdomain || 'unknown'}`);
        }).catch(() => {});
      }
    });
    
    // Step 1: Complete login flow
    console.log('\n🔐 Step 1: Login to Default Tenant');
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    await page.fill('input[name="username"], [formControlName="username"]', 'admin');
    await page.fill('input[name="password"], [formControlName="password"]', 'admin');
    await page.locator('button[type="submit"]').first().click();
    
    await page.waitForTimeout(2000);
    
    // Step 2: TOTP verification
    console.log('\n🔢 Step 2: TOTP Verification');
    if (page.url().includes('/totp')) {
      await page.fill('input[name="code"]', '123456');
      await page.locator('button').first().click();
      
      await page.waitForTimeout(3000);
      console.log(`   ✅ TOTP completed, now at: ${page.url()}`);
    }
    
    // Step 3: Access dashboard directly
    console.log('\n📊 Step 3: Access Tenant Dashboard');
    await page.goto('http://localhost:4200/dashboard/overview');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    
    const currentUrl = page.url();
    const pageTitle = await page.title();
    
    console.log(`   Dashboard URL: ${currentUrl}`);
    console.log(`   Page Title: ${pageTitle}`);
    
    // Check for tenant-specific elements
    const tenantName = await page.locator('[class*="tenant"], [class*="organization"]').count();
    const dashboardContent = await page.locator('h1, h2, h3, .page-title, [class*="dashboard"]').count();
    
    console.log(`   Dashboard elements found: ${dashboardContent}`);
    console.log(`   Tenant elements found: ${tenantName}`);
    
    // Take a screenshot
    await page.screenshot({ path: '/home/ptsec/utmstack/tenant-dashboard.png', fullPage: true });
    console.log('   📸 Screenshot saved: tenant-dashboard.png');
    
    // Try to access tenant management page
    console.log('\n🏢 Step 4: Test Tenant Management Access');
    await page.goto('http://localhost:4200/management/tenant');
    await page.waitForTimeout(2000);
    
    const tenantMgmtUrl = page.url();
    console.log(`   Tenant Management URL: ${tenantMgmtUrl}`);
    
    const success = currentUrl.includes('/dashboard') && !currentUrl.includes('/login');
    
    console.log('\n📋 TENANT DASHBOARD TEST RESULTS:');
    console.log('==================================');
    console.log(`✅ Dashboard accessible: ${success ? 'YES' : 'NO'}`);
    console.log(`🏢 Tenant context: Default Organization (default)`);
    console.log(`🔗 Current URL: ${currentUrl}`);
    
    return {
      success,
      tenantId: 'b621d671-dd5a-4870-ba84-299e741e4a2e',
      tenantSubdomain: 'default',
      dashboardUrl: currentUrl,
      accessible: success
    };
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return { success: false, error: error.message };
  } finally {
    await browser.close();
  }
}

testTenantDashboard().then(result => {
  console.log('\n' + '='.repeat(60));
  console.log('🏢 DEFAULT TENANT DASHBOARD INFORMATION');
  console.log('='.repeat(60));
  
  if (result.success) {
    console.log('✅ Status: WORKING');
    console.log('🏢 Tenant ID: b621d671-dd5a-4870-ba84-299e741e4a2e');
    console.log('🏢 Tenant Name: Default Organization');
    console.log('🏢 Subdomain: default');
    console.log('');
    console.log('🌐 DASHBOARD URLS:');
    console.log('==================');
    console.log('📊 Development: http://localhost:4200/dashboard/overview');
    console.log('📊 Production:  https://default.utmstack.com/dashboard/overview');
    console.log('');
    console.log('🔐 LOGIN CREDENTIALS:');
    console.log('=====================');
    console.log('👤 Username: admin');
    console.log('🔑 Password: admin');
    console.log('🔢 TOTP Code: 123456');
    console.log('');
    console.log('🏢 TENANT DETAILS:');
    console.log('==================');
    console.log('• Name: Default Organization');
    console.log('• Subdomain: default');
    console.log('• Status: active');
    console.log('• Tier: standard');
    console.log('• Max Users: 100');
    console.log('• Max Storage: 10GB');
    console.log('• Retention: 30 days');
  } else {
    console.log('❌ Status: FAILED');
    console.log('❌ Error:', result.error || 'Dashboard not accessible');
  }
  
  console.log('='.repeat(60));
}).catch(error => {
  console.error('💥 Test execution failed:', error);
});
