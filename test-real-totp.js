const { chromium } = require('playwright');

async function testRealTOTPBehavior() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🔍 Testing real TOTP behavior (no mocking)...');
    
    // Enable console and network logging
    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.log('🔴 Browser Error:', msg.text());
      } else {
        console.log('🖥️ Browser:', msg.text());
      }
    });
    
    page.on('pageerror', error => {
      console.log('💥 Page Error:', error.message);
    });
    
    // Monitor network requests
    page.on('request', request => {
      if (request.url().includes('verifyCode') || request.url().includes('tfa')) {
        console.log('📤 Request:', request.method(), request.url());
      }
    });
    
    page.on('response', response => {
      if (response.url().includes('verifyCode') || response.url().includes('tfa')) {
        console.log('📥 Response:', response.status(), response.url());
        response.text().then(body => {
          console.log('📄 Response body:', body);
        }).catch(e => console.log('❌ Could not read response body'));
      }
    });
    
    // Navigate to TOTP page
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('📍 On TOTP page, analyzing initial state...');
    
    // Check initial elements
    const formExists = await page.locator('form').count();
    const codeInput = await page.locator('input[name="code"]').count();
    const submitButton = await page.locator('button').count();
    
    console.log(`📋 Initial state: form=${formExists}, input=${codeInput}, buttons=${submitButton}`);
    
    if (formExists === 0 || codeInput === 0) {
      console.log('❌ TOTP form not found or incomplete');
      return false;
    }
    
    // Fill the TOTP code
    console.log('🔢 Filling TOTP code: 123456');
    await page.fill('input[name="code"]', '123456');
    
    // Get the filled value to confirm
    const filledValue = await page.inputValue('input[name="code"]');
    console.log(`✅ Code filled: ${filledValue}`);
    
    // Get the submit button
    const button = page.locator('button').first();
    const buttonText = await button.textContent();
    console.log(`🔘 Submit button text: "${buttonText}"`);
    
    // Check if button is disabled
    const isDisabled = await button.isDisabled();
    console.log(`🔘 Button disabled: ${isDisabled}`);
    
    // Submit the form
    console.log('🚀 Clicking submit button...');
    await button.click();
    
    // Wait for any network activity
    console.log('⏳ Waiting for response...');
    await page.waitForTimeout(5000);
    
    // Check current state after submission
    const currentUrl = page.url();
    console.log(`📍 Current URL: ${currentUrl}`);
    
    // Check for any messages
    const successMessage = await page.getByText('Authentication successful!').count();
    const errorMessage = await page.locator('.alert-danger').count();
    const toastMessages = await page.locator('[class*="toast"], [class*="alert"]').count();
    
    console.log(`✅ Success message: ${successMessage}`);
    console.log(`❌ Error messages: ${errorMessage}`);
    console.log(`📢 Toast/Alert messages: ${toastMessages}`);
    
    // If there are alerts/toasts, get their text
    if (toastMessages > 0) {
      const alertTexts = await page.locator('[class*="toast"], [class*="alert"]').allTextContents();
      console.log('📢 Alert texts:', alertTexts);
    }
    
    // Check form state
    const formStillVisible = await page.locator('form').isVisible();
    const inputStillFilled = await page.inputValue('input[name="code"]');
    
    console.log(`📋 Form still visible: ${formStillVisible}`);
    console.log(`🔢 Input still has value: ${inputStillFilled}`);
    
    // Check for any spinner/loading indicators
    const spinner = await page.locator('[class*="spinner"], [class*="loading"], .icon-spinner2').count();
    console.log(`⏳ Loading indicators: ${spinner}`);
    
    // Try to get component state if possible
    const componentState = await page.evaluate(() => {
      try {
        const totpComponent = document.querySelector('app-totp');
        if (totpComponent && window.ng) {
          const component = window.ng.getComponent(totpComponent);
          return {
            isLoggedIn: component?.isLoggedIn,
            verifying: component?.verifying,
            isLoginFailed: component?.isLoginFailed,
            errorMessage: component?.errorMessage
          };
        }
        return 'Component not accessible';
      } catch (e) {
        return 'Error accessing component: ' + e.message;
      }
    });
    
    console.log('🔧 Component state:', componentState);
    
    // Take a screenshot for visual verification
    await page.screenshot({ path: '/home/ptsec/utmstack/real-totp-test.png', fullPage: true });
    console.log('📸 Screenshot saved: real-totp-test.png');
    
    return {
      stuckOnTOTP: currentUrl.includes('/totp'),
      hasSuccessMessage: successMessage > 0,
      hasErrorMessage: errorMessage > 0,
      formVisible: formStillVisible,
      componentState,
      currentUrl
    };
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return { error: error.message };
  } finally {
    await browser.close();
  }
}

// Test the real login flow too
async function testRealLoginFlow() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('\n🔍 Testing real login flow...');
    
    // Enable logging
    page.on('response', response => {
      if (response.url().includes('authenticate')) {
        console.log('🔐 Login Response:', response.status());
        response.text().then(body => {
          console.log('🔐 Login body:', body.substring(0, 200));
        }).catch(() => {});
      }
    });
    
    // Navigate to login
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Check if login form exists
    const loginForm = await page.locator('form').count();
    const usernameInput = await page.locator('input[name="username"], [formControlName="username"]').count();
    
    console.log(`📋 Login form elements: form=${loginForm}, username=${usernameInput}`);
    
    if (loginForm > 0 && usernameInput > 0) {
      console.log('🔐 Attempting login...');
      
      await page.fill('input[name="username"], [formControlName="username"]', 'admin');
      await page.fill('input[name="password"], [formControlName="password"]', 'admin');
      
      const loginButton = page.locator('button[type="submit"]').first();
      await loginButton.click();
      
      await page.waitForTimeout(3000);
      
      const afterLoginUrl = page.url();
      console.log(`📍 After login URL: ${afterLoginUrl}`);
      
      return {
        loginAttempted: true,
        redirectedToTOTP: afterLoginUrl.includes('/totp'),
        finalUrl: afterLoginUrl
      };
    }
    
    return { loginAttempted: false };
    
  } catch (error) {
    console.error('❌ Login test failed:', error.message);
    return { error: error.message };
  } finally {
    await browser.close();
  }
}

// Run both tests
async function runRealTests() {
  console.log('🚀 Running REAL TOTP tests (no mocking)...\n');
  
  // Test login flow first
  const loginResult = await testRealLoginFlow();
  console.log('🔐 Login test result:', loginResult);
  
  // Test TOTP behavior
  const totpResult = await testRealTOTPBehavior();
  
  console.log('\n📊 REAL TEST RESULTS:');
  console.log('=====================================');
  console.log('🔐 Login Flow:');
  if (loginResult.redirectedToTOTP) {
    console.log('  ✅ Login redirects to TOTP page');
  } else {
    console.log('  ⚠️ Login behavior:', loginResult.finalUrl);
  }
  
  console.log('\n🔢 TOTP Flow:');
  console.log(`  Stuck on TOTP page: ${totpResult.stuckOnTOTP ? '❌ YES' : '✅ NO'}`);
  console.log(`  Shows success message: ${totpResult.hasSuccessMessage ? '✅ YES' : '❌ NO'}`);
  console.log(`  Shows error message: ${totpResult.hasErrorMessage ? '✅ YES' : '❌ NO'}`);
  console.log(`  Form remains visible: ${totpResult.formVisible ? '📋 YES' : '📋 NO'}`);
  
  if (totpResult.componentState && typeof totpResult.componentState === 'object') {
    console.log('  Component state:', totpResult.componentState);
  }
  
  console.log('\n🎯 DIAGNOSIS:');
  if (totpResult.stuckOnTOTP && !totpResult.hasErrorMessage && !totpResult.hasSuccessMessage) {
    console.log('❌ ISSUE: Code submission has no visible response');
    console.log('   Likely causes: API endpoint not working, network error, or silent JS error');
  } else if (totpResult.stuckOnTOTP && totpResult.hasErrorMessage) {
    console.log('⚠️ EXPECTED: Invalid code shows error and stays on page');
  } else if (!totpResult.stuckOnTOTP) {
    console.log('✅ WORKING: Successfully redirected away from TOTP page');
  }
  
  return totpResult;
}

runRealTests().then(result => {
  console.log('\n' + '='.repeat(50));
  console.log('🏁 Real TOTP test completed');
  console.log('='.repeat(50));
}).catch(error => {
  console.error('💥 Test execution failed:', error);
});
