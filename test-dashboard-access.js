const { chromium } = require('playwright');

async function testDashboardAccess() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🎯 Testing complete login flow with dashboard access');
    console.log('===================================================');
    
    // Enable detailed logging
    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.log('🔴 Browser Error:', msg.text());
      } else if (msg.text().includes('authorities') || msg.text().includes('ROLE')) {
        console.log('👤 Auth Log:', msg.text());
      }
    });
    
    // Monitor API calls
    page.on('request', request => {
      if (request.url().includes('/api/')) {
        console.log('📤 API Request:', request.method(), request.url().split('/api/')[1]);
      }
    });
    
    page.on('response', response => {
      if (response.url().includes('/api/account')) {
        console.log('👤 Account API Response:', response.status());
        response.json().then(data => {
          console.log('👤 User authorities:', data.authorities);
        }).catch(() => {});
      }
    });
    
    // Step 1: Login
    console.log('\n🔐 Step 1: Login');
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    await page.fill('input[name="username"], [formControlName="username"]', 'admin');
    await page.fill('input[name="password"], [formControlName="password"]', 'admin');
    await page.locator('button[type="submit"]').first().click();
    
    await page.waitForTimeout(2000);
    
    const loginResult = page.url();
    console.log(`   Result: ${loginResult.includes('/totp') ? '✅ Redirected to TOTP' : '❌ Unexpected: ' + loginResult}`);
    
    // Step 2: TOTP Verification
    console.log('\n🔢 Step 2: TOTP Verification');
    if (loginResult.includes('/totp')) {
      await page.fill('input[name="code"]', '123456');
      await page.locator('button').first().click();
      
      console.log('⏳ Waiting for TOTP verification...');
      await page.waitForTimeout(3000);
      
      const totpResult = page.url();
      console.log(`   TOTP Result: ${totpResult}`);
      console.log(`   ✅ Left TOTP page: ${!totpResult.includes('/totp')}`);
    }
    
    // Step 3: Try to access dashboard
    console.log('\n📊 Step 3: Dashboard Access');
    await page.goto('http://localhost:4200/dashboard/overview');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    
    const dashboardResult = page.url();
    console.log(`   Dashboard URL: ${dashboardResult}`);
    
    // Check for authority errors
    const hasAuthorityError = await page.getByText('User has not any of required authorities').count();
    const pageTitle = await page.locator('h1, h2, h3, .page-title').first().textContent().catch(() => 'No title found');
    
    console.log(`   Authority error: ${hasAuthorityError > 0 ? '❌ YES' : '✅ NO'}`);
    console.log(`   Page title: ${pageTitle}`);
    
    // Check if we're actually on dashboard or redirected somewhere
    const onDashboard = dashboardResult.includes('/dashboard');
    const onLogin = dashboardResult.includes('/login') || dashboardResult === 'http://localhost:4200/';
    
    console.log(`   On dashboard: ${onDashboard ? '✅ YES' : '❌ NO'}`);
    console.log(`   Redirected to login: ${onLogin ? '❌ YES' : '✅ NO'}`);
    
    // Take screenshot for verification
    await page.screenshot({ path: '/home/ptsec/utmstack/dashboard-access-test.png', fullPage: true });
    console.log('📸 Screenshot saved: dashboard-access-test.png');
    
    console.log('\n📋 FINAL ASSESSMENT:');
    console.log('====================');
    
    const loginWorks = loginResult.includes('/totp');
    const totpWorks = !page.url().includes('/totp');
    const dashboardAccessible = onDashboard && hasAuthorityError === 0;
    
    console.log(`🔐 Login flow: ${loginWorks ? '✅ WORKING' : '❌ BROKEN'}`);
    console.log(`🔢 TOTP flow: ${totpWorks ? '✅ WORKING' : '❌ BROKEN'}`);
    console.log(`📊 Dashboard access: ${dashboardAccessible ? '✅ WORKING' : '❌ BROKEN'}`);
    
    const overallSuccess = loginWorks && totpWorks && dashboardAccessible;
    console.log(`\n🎯 OVERALL STATUS: ${overallSuccess ? '🎉 FULLY WORKING' : '⚠️ NEEDS FIXES'}`);
    
    if (!dashboardAccessible && hasAuthorityError > 0) {
      console.log('\n💡 DIAGNOSIS: Authority/role issue still exists');
      console.log('   Check: User account API, JWT token, or role assignment');
    }
    
    return {
      loginWorks,
      totpWorks,
      dashboardAccessible,
      overallSuccess,
      finalUrl: page.url()
    };
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return { error: error.message };
  } finally {
    await browser.close();
  }
}

testDashboardAccess().then(result => {
  console.log('\n' + '='.repeat(60));
  if (result.overallSuccess) {
    console.log('🎉 COMPLETE SUCCESS: Login → TOTP → Dashboard all working!');
  } else if (result.loginWorks && result.totpWorks) {
    console.log('⚠️ PARTIAL SUCCESS: TOTP fixed, but dashboard access needs work');
  } else {
    console.log('❌ ISSUES REMAIN: Check the test output above');
  }
  console.log('='.repeat(60));
}).catch(error => {
  console.error('💥 Test execution failed:', error);
});
