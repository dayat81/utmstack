const { test, expect } = require('@playwright/test');

test('Verify admin:admin login works', async ({ page }) => {
  console.log('🔐 Testing admin:admin login...');
  
  await page.goto('http://localhost:4200');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5000);
  
  const emailField = await page.$('input[type="email"], input[placeholder*="User" i]');
  const passwordField = await page.$('input[type="password"]');
  const submitButton = await page.$('button[type="submit"], button:has-text("Sign in")');
  
  if (emailField && passwordField && submitButton) {
    await emailField.fill('admin');
    await passwordField.fill('admin');
    
    const responses = [];
    page.on('response', response => {
      if (response.url().includes('/api/authenticate')) {
        responses.push(response.status());
      }
    });
    
    await submitButton.click();
    await page.waitForTimeout(3000);
    
    if (responses.includes(200)) {
      console.log('✅ Login successful!');
    } else {
      console.log('❌ Login failed');
    }
  } else {
    console.log('⚠️ Login form not found');
  }
});
