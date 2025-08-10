const { chromium } = require('playwright');

async function verifyTOTPFix() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🔍 Verifying TOTP redirect fix implementation...');
    
    // Mock successful TOTP verification
    await page.route('**/api/tfa/verifyCode**', async route => {
      console.log('🔧 Mocking successful TOTP verification');
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id_token: 'mock-jwt-token-12345',
          authenticated: true
        })
      });
    });
    
    // Navigate to TOTP page
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('📍 On TOTP page');
    
    // Verify initial state
    await page.waitForSelector('input[name="code"]');
    const initialFormVisible = await page.locator('form').isVisible();
    const initialSuccessVisible = await page.getByText('Authentication successful!').count();
    
    console.log(`✅ Initial state: form visible=${initialFormVisible}, success message=${initialSuccessVisible}`);
    
    // Fill and submit form
    console.log('🔢 Submitting TOTP form with mocked successful response...');
    await page.fill('input[name="code"]', '123456');
    await page.locator('button').first().click();
    
    // Wait for the component state to update
    await page.waitForTimeout(1000);
    
    // Check if success message appears
    const successMessageCount = await page.getByText('Authentication successful!').count();
    const redirectMessageCount = await page.getByText('Redirecting to dashboard...').count();
    
    console.log(`✅ Success message appeared: ${successMessageCount > 0}`);
    console.log(`✅ Redirect message appeared: ${redirectMessageCount > 0}`);
    
    // Check if form is hidden (isLoggedIn = true should hide the form)
    const formVisibleAfter = await page.locator('form').isVisible();
    console.log(`✅ Form hidden after success: ${!formVisibleAfter}`);
    
    // Wait for redirect timeout (500ms in our implementation)
    console.log('⏳ Waiting for redirect...');
    await page.waitForTimeout(1000);
    
    // Check final URL - should redirect to dashboard
    const finalUrl = page.url();
    console.log(`📍 Final URL: ${finalUrl}`);
    
    // Verify our fix is working
    const fixWorking = (
      successMessageCount > 0 &&          // Success message shows
      !formVisibleAfter &&                // Form gets hidden
      finalUrl.includes('/dashboard')     // Redirects to dashboard
    );
    
    console.log('\n📊 TOTP Fix Verification Results:');
    console.log(`   Success message displays: ${successMessageCount > 0 ? '✅' : '❌'}`);
    console.log(`   Form hides on success: ${!formVisibleAfter ? '✅' : '❌'}`);
    console.log(`   Redirects to dashboard: ${finalUrl.includes('/dashboard') ? '✅' : '❌'}`);
    console.log(`   Overall fix status: ${fixWorking ? '🎉 WORKING' : '⚠️ NEEDS REVIEW'}`);
    
    return {
      fixWorking,
      successMessageShown: successMessageCount > 0,
      formHidden: !formVisibleAfter,
      redirectedToDashboard: finalUrl.includes('/dashboard'),
      finalUrl
    };
    
  } catch (error) {
    console.error('❌ Verification failed:', error.message);
    return { fixWorking: false, error: error.message };
  } finally {
    await browser.close();
  }
}

async function testOriginalIssue() {
  console.log('\n🔍 Testing original issue scenario...');
  
  const browser = await chromium.launch({ headless: false, slowMo: 500 });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  try {
    // Mock failed TOTP verification (original behavior)
    await page.route('**/api/tfa/verifyCode**', async route => {
      console.log('🔧 Mocking failed TOTP verification');
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Invalid code'
        })
      });
    });
    
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('📍 Testing failed verification behavior...');
    
    await page.fill('input[name="code"]', '999999');
    await page.locator('button').first().click();
    
    await page.waitForTimeout(2000);
    
    const staysOnTOTP = page.url().includes('/totp');
    const formStillVisible = await page.locator('form').isVisible();
    const errorShown = await page.getByText('Verification code is invalid or has expired').count();
    
    console.log(`✅ Stays on TOTP page after failure: ${staysOnTOTP}`);
    console.log(`✅ Form remains visible: ${formStillVisible}`);
    console.log(`✅ Error message shown: ${errorShown > 0}`);
    
    return {
      behavesCorrectlyOnFailure: staysOnTOTP && formStillVisible,
      errorMessageShown: errorShown > 0
    };
    
  } catch (error) {
    console.error('❌ Original issue test failed:', error.message);
    return { behavesCorrectlyOnFailure: false, error: error.message };
  } finally {
    await browser.close();
  }
}

// Run verification tests
async function runVerification() {
  console.log('🚀 Running TOTP fix verification tests...\n');
  
  const successTest = await verifyTOTPFix();
  const failureTest = await testOriginalIssue();
  
  console.log('\n🎯 FINAL VERIFICATION SUMMARY:');
  console.log('=====================================');
  
  if (successTest.fixWorking) {
    console.log('✅ TOTP SUCCESS FLOW: FIXED');
    console.log('   - Success message displays correctly');
    console.log('   - Form hides when authenticated');
    console.log('   - Properly redirects to dashboard');
  } else {
    console.log('❌ TOTP SUCCESS FLOW: NEEDS REVIEW');
  }
  
  if (failureTest.behavesCorrectlyOnFailure) {
    console.log('✅ TOTP FAILURE FLOW: WORKING');
    console.log('   - Stays on TOTP page when verification fails');
    console.log('   - Form remains visible for retry');
  } else {
    console.log('❌ TOTP FAILURE FLOW: NEEDS REVIEW');
  }
  
  const overallStatus = successTest.fixWorking && failureTest.behavesCorrectlyOnFailure;
  
  console.log('\n' + '='.repeat(40));
  console.log(`🎯 OVERALL STATUS: ${overallStatus ? '🎉 TOTP FIX VERIFIED' : '⚠️ NEEDS ATTENTION'}`);
  console.log('='.repeat(40));
  
  return overallStatus;
}

runVerification().then(success => {
  process.exit(success ? 0 : 1);
}).catch(error => {
  console.error('💥 Verification failed:', error);
  process.exit(1);
});
