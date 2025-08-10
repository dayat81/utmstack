const { chromium } = require('playwright');

async function simpleTOTPTest() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🔍 Simple TOTP test...');
    
    // Enable console logging
    page.on('console', msg => console.log('🖥️ Browser:', msg.text()));
    
    // Navigate to TOTP page
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('📍 On TOTP page');
    
    // Wait for form elements with corrected selectors
    await page.waitForSelector('input[name="code"]', { timeout: 10000 });
    console.log('✅ Code input found');
    
    // Find the submit button more reliably
    await page.waitForSelector('button', { timeout: 5000 });
    const buttons = await page.locator('button').count();
    console.log(`🔘 Found ${buttons} buttons`);
    
    // Fill the code
    console.log('🔢 Filling TOTP code...');
    await page.fill('input[name="code"]', '123456');
    
    // Find and click the submit button (should be the main button in the form)
    const submitButton = page.locator('button').filter({ hasText: /confirm/i }).first();
    const buttonExists = await submitButton.count();
    
    if (buttonExists === 0) {
      // Fallback to any button in the form
      console.log('🔘 Using fallback button selector...');
      const formButton = page.locator('form button').first();
      await formButton.click();
    } else {
      await submitButton.click();
    }
    
    console.log('🚀 Submit button clicked');
    
    // Wait and check what happens
    await page.waitForTimeout(3000);
    
    const currentUrl = page.url();
    console.log(`📍 Current URL: ${currentUrl}`);
    
    // Take a screenshot to see the current state
    await page.screenshot({ path: '/home/ptsec/utmstack/totp-test-screenshot.png' });
    console.log('📸 Screenshot saved as totp-test-screenshot.png');
    
    // Check for success message
    const successMessage = await page.getByText('Authentication successful!').count();
    console.log(`✅ Success message found: ${successMessage > 0}`);
    
    // Check current page content
    const pageTitle = await page.locator('h6').first().textContent();
    console.log(`📄 Page title: ${pageTitle}`);
    
    if (currentUrl.includes('/totp')) {
      console.log('📍 Still on TOTP page - checking for error message');
      const errorMessage = await page.locator('.alert-danger').count();
      console.log(`❌ Error messages found: ${errorMessage}`);
      
      if (errorMessage > 0) {
        const errorText = await page.locator('.alert-danger').first().textContent();
        console.log(`❌ Error text: ${errorText}`);
      }
    }
    
    return { 
      success: currentUrl.includes('/dashboard') || successMessage > 0,
      currentUrl,
      hasError: await page.locator('.alert-danger').count() > 0
    };
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return { success: false, error: error.message };
  } finally {
    await browser.close();
  }
}

simpleTOTPTest().then(result => {
  console.log('\n📊 Test Result:', result);
  
  if (result.success) {
    console.log('🎉 TOTP test PASSED');
  } else {
    console.log('❌ TOTP test needs attention');
  }
}).catch(error => {
  console.error('💥 Test execution failed:', error);
});
