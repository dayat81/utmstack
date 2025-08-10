const { chromium } = require('playwright');

async function testTOTPSuccessFlow() {
  const browser = await chromium.launch({ headless: false, slowMo: 500 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🔍 Starting TOTP success flow test...');
    
    // Intercept the TOTP verification API call to simulate success
    await page.route('**/api/tfa/verifyCode**', async route => {
      console.log('🔧 Intercepting TOTP verification API call...');
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id_token: 'mock-jwt-token-for-testing',
          authenticated: true
        })
      });
    });
    
    // Navigate to login page
    console.log('📱 Navigating to login page...');
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Fill and submit login form
    console.log('🔐 Logging in...');
    await page.waitForSelector('input[name="username"], #username, [formControlName="username"]', { timeout: 10000 });
    
    const usernameField = await page.locator('input[name="username"], #username, [formControlName="username"]').first();
    const passwordField = await page.locator('input[name="password"], #password, [formControlName="password"]').first();
    
    await usernameField.fill('admin');
    await passwordField.fill('admin');
    
    const loginButton = await page.locator('button[type="submit"], .utm-button-primary, button:has-text("Login")').first();
    await loginButton.click();
    
    // Wait for TOTP page
    await page.waitForTimeout(3000);
    const totpUrl = page.url();
    console.log(`📍 After login URL: ${totpUrl}`);
    
    if (totpUrl.includes('/totp')) {
      console.log('✅ Redirected to TOTP page as expected');
      
      // Wait for TOTP form and fill it
      await page.waitForSelector('input[name="code"], #code', { timeout: 10000 });
      console.log('✅ TOTP form loaded');
      
      // Enter TOTP code and submit
      console.log('🔢 Entering TOTP code...');
      const codeField = await page.locator('input[name="code"], #code').first();
      await codeField.fill('123456');
      
      const totpButton = await page.locator('button[type="submit"], button:has-text("Confirm")').first();
      await totpButton.click();
      
      // Wait for success message to appear
      console.log('⏳ Waiting for success message...');
      try {
        await page.waitForSelector('text="Authentication successful!"', { timeout: 5000 });
        console.log('✅ Success message appeared!');
        
        // Wait for redirect
        console.log('⏳ Waiting for redirect...');
        await page.waitForTimeout(2000);
        
        // Check final URL
        const finalUrl = page.url();
        console.log(`📍 Final URL: ${finalUrl}`);
        
        if (finalUrl.includes('/dashboard')) {
          console.log('🎉 SUCCESS: Properly redirected to dashboard!');
          return true;
        } else {
          console.log(`❌ Expected dashboard redirect, but got: ${finalUrl}`);
          return false;
        }
        
      } catch (error) {
        console.log('❌ Success message did not appear within timeout');
        console.log('📍 Current URL:', page.url());
        
        // Check if there's an error message instead
        const errorVisible = await page.locator('text="invalid", text="expired"').count();
        if (errorVisible > 0) {
          console.log('⚠️ Error message displayed (API interception may not have worked)');
        }
        return false;
      }
      
    } else if (totpUrl.includes('/dashboard')) {
      console.log('✅ Directly redirected to dashboard (no 2FA required)');
      return true;
    } else {
      console.log(`❌ Unexpected redirect to: ${totpUrl}`);
      return false;
    }
    
  } catch (error) {
    console.error('❌ Test failed with error:', error.message);
    return false;
  } finally {
    await browser.close();
  }
}

// Test the current behavior
async function testCurrentBehavior() {
  const browser = await chromium.launch({ headless: false, slowMo: 500 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('\n🔍 Testing current TOTP page behavior...');
    
    // Navigate directly to TOTP page to test the fix
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('📍 Navigated to TOTP page directly');
    
    // Check if the page loads correctly
    const formExists = await page.locator('form').count();
    const titleExists = await page.locator('text="Two factor authentication"').count();
    
    if (formExists > 0 && titleExists > 0) {
      console.log('✅ TOTP page loads correctly');
      console.log('✅ Form is present and title is displayed');
      
      // Test that the form elements are working
      const codeField = await page.locator('input[name="code"], #code').first();
      await codeField.fill('test123');
      
      const fieldValue = await codeField.inputValue();
      if (fieldValue === 'test123') {
        console.log('✅ Code input field is functional');
        return true;
      } else {
        console.log('❌ Code input field not working properly');
        return false;
      }
    } else {
      console.log('❌ TOTP page not loading correctly');
      return false;
    }
    
  } catch (error) {
    console.error('❌ Current behavior test failed:', error.message);
    return false;
  } finally {
    await browser.close();
  }
}

// Run both tests
async function runAllTests() {
  console.log('🚀 Running TOTP redirect verification tests...\n');
  
  const behaviorTest = await testCurrentBehavior();
  const successTest = await testTOTPSuccessFlow();
  
  console.log('\n📊 TEST RESULTS:');
  console.log(`TOTP Page Functionality: ${behaviorTest ? '✅ PASS' : '❌ FAIL'}`);
  console.log(`TOTP Success Redirect: ${successTest ? '✅ PASS' : '❌ FAIL'}`);
  
  if (behaviorTest && successTest) {
    console.log('\n🎉 All tests PASSED - TOTP redirect fix is working!');
    process.exit(0);
  } else {
    console.log('\n❌ Some tests FAILED - needs investigation');
    process.exit(1);
  }
}

runAllTests().catch(error => {
  console.error('\n💥 Test execution failed:', error);
  process.exit(1);
});
