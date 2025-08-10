const { chromium } = require('playwright');

async function debugTOTPFlow() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🔍 Debugging TOTP flow...');
    
    // Enable console logging
    page.on('console', msg => console.log('🖥️  Browser Console:', msg.text()));
    page.on('pageerror', error => console.log('💥 Page Error:', error.message));
    
    // Navigate directly to TOTP page to simulate being logged in
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('📍 On TOTP page, checking elements...');
    
    // Check all elements
    const elements = await page.evaluate(() => {
      const form = document.querySelector('form');
      const codeInput = document.querySelector('input[name="code"], #code');
      const submitButton = document.querySelector('button[type="submit"], button:has-text("Confirm")');
      const isLoggedInDiv = document.querySelector('*[ng-reflect-ng-if="isLoggedIn"]');
      
      return {
        formExists: !!form,
        codeInputExists: !!codeInput,
        submitButtonExists: !!submitButton,
        isLoggedInVisible: !!isLoggedInDiv,
        formHTML: form ? form.outerHTML.substring(0, 200) + '...' : 'NO FORM',
        inputHTML: codeInput ? codeInput.outerHTML : 'NO INPUT'
      };
    });
    
    console.log('📋 Element analysis:', elements);
    
    // Wait for form elements
    await page.waitForSelector('input[name="code"], #code');
    await page.waitForSelector('button[type="submit"], button:has-text("Confirm")');
    
    // Fill the code
    console.log('🔢 Filling TOTP code...');
    const codeField = await page.locator('input[name="code"], #code').first();
    await codeField.fill('123456');
    
    // Get the submit button
    const submitButton = await page.locator('button[type="submit"], button:has-text("Confirm")').first();
    
    // Monitor network requests
    console.log('📡 Monitoring network requests...');
    page.on('request', request => {
      if (request.url().includes('verifyCode')) {
        console.log('🌐 TOTP API Request:', request.url(), request.method());
      }
    });
    
    page.on('response', response => {
      if (response.url().includes('verifyCode')) {
        console.log('📨 TOTP API Response:', response.status(), response.url());
      }
    });
    
    // Click submit and watch what happens
    console.log('🚀 Clicking submit button...');
    await submitButton.click();
    
    // Wait and observe
    await page.waitForTimeout(5000);
    
    const currentUrl = page.url();
    console.log(`📍 URL after submit: ${currentUrl}`);
    
    // Check if success message appeared
    const successMessageExists = await page.locator('text="Authentication successful!"').count();
    console.log(`✅ Success message count: ${successMessageExists}`);
    
    // Check if isLoggedIn changed
    const isLoggedInState = await page.evaluate(() => {
      const component = window.ng?.getComponent?.(document.querySelector('app-totp'));
      return component ? component.isLoggedIn : 'Component not found';
    });
    console.log(`🔐 isLoggedIn state: ${isLoggedInState}`);
    
    // Check for any error messages
    const errorMessages = await page.locator('.alert-danger, .text-danger, text*="invalid", text*="expired"').count();
    console.log(`❌ Error message count: ${errorMessages}`);
    
    return true;
    
  } catch (error) {
    console.error('❌ Debug failed:', error.message);
    return false;
  } finally {
    await browser.close();
  }
}

debugTOTPFlow().catch(error => {
  console.error('💥 Debug execution failed:', error);
  process.exit(1);
});
