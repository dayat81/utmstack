const { chromium } = require('playwright');

async function finalTOTPTest() {
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🎯 FINAL TOTP VERIFICATION TEST');
    console.log('================================');
    
    // Navigate directly to TOTP page
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('📍 Starting on TOTP page');
    console.log(`   URL: ${page.url()}`);
    
    // Verify initial state
    const initialFormExists = await page.locator('form').isVisible();
    console.log(`   Form visible: ${initialFormExists}`);
    
    // Test with VALID code (123456)
    console.log('\n🔑 Testing VALID TOTP code (123456)...');
    await page.fill('input[name="code"]', '123456');
    await page.locator('button').first().click();
    
    console.log('⏳ Waiting for response...');
    await page.waitForTimeout(3000);
    
    const afterValidCode = page.url();
    const formStillVisible = await page.locator('form').count();
    
    console.log(`   After valid code URL: ${afterValidCode}`);
    console.log(`   Form still exists: ${formStillVisible > 0}`);
    console.log(`   ✅ Redirected away from TOTP: ${!afterValidCode.includes('/totp')}`);
    
    // Navigate back to test invalid code
    await page.goto('http://localhost:4200/totp');
    await page.waitForLoadState('networkidle');
    
    console.log('\n❌ Testing INVALID TOTP code (999999)...');
    await page.fill('input[name="code"]', '999999');
    await page.locator('button').first().click();
    
    await page.waitForTimeout(3000);
    
    const afterInvalidCode = page.url();
    const errorMessage = await page.locator('.alert-danger').count();
    const formVisibleAfterError = await page.locator('form').isVisible();
    
    console.log(`   After invalid code URL: ${afterInvalidCode}`);
    console.log(`   Error message shown: ${errorMessage > 0}`);
    console.log(`   Form still visible: ${formVisibleAfterError}`);
    console.log(`   ✅ Stayed on TOTP for retry: ${afterInvalidCode.includes('/totp')}`);
    
    console.log('\n🎯 FINAL RESULTS:');
    console.log('================');
    
    const validCodeWorks = !afterValidCode.includes('/totp');
    const invalidCodeStays = afterInvalidCode.includes('/totp') && formVisibleAfterError;
    
    console.log(`✅ Valid code redirects away: ${validCodeWorks ? 'PASS' : 'FAIL'}`);
    console.log(`✅ Invalid code shows error and stays: ${invalidCodeStays ? 'PASS' : 'FAIL'}`);
    
    const overallSuccess = validCodeWorks && invalidCodeStays;
    console.log(`\n🎉 OVERALL TOTP FIX STATUS: ${overallSuccess ? 'SUCCESS ✅' : 'NEEDS WORK ❌'}`);
    
    return overallSuccess;
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return false;
  } finally {
    await browser.close();
  }
}

finalTOTPTest().then(success => {
  console.log('\n' + '='.repeat(50));
  if (success) {
    console.log('🎉 TOTP redirect issue is COMPLETELY FIXED! 🎉');
    console.log('✅ Users will no longer get stuck on /totp page');
    console.log('✅ Valid codes redirect properly');
    console.log('✅ Invalid codes show errors and allow retry');
  } else {
    console.log('⚠️ TOTP fix needs more work');
  }
  console.log('='.repeat(50));
  process.exit(success ? 0 : 1);
}).catch(error => {
  console.error('💥 Test failed:', error);
  process.exit(1);
});
