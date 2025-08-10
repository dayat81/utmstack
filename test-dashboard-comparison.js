const { chromium } = require('playwright');

async function testDashboardComparison() {
  console.log('🚀 Starting dashboard comparison test...');
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  const originalErrors = [
    'Cannot read properties of undefined (reading \'diskSpace\')',
    'response.body.sort is not a function',
    'Cannot read properties of undefined (reading \'length\')',
    'Cannot convert undefined or null to object'
  ];

  const consoleMessages = [];
  page.on('console', msg => {
    if (msg.type() === 'error') {
      consoleMessages.push(msg.text());
    }
  });

  try {
    console.log('🌐 Navigating to dashboard...');
    await page.goto('http://localhost:4200/dashboard/overview', { 
      waitUntil: 'networkidle',
      timeout: 30000 
    });

    await page.waitForTimeout(8000);

    console.log('\n📊 ERROR ANALYSIS:');
    console.log(`Total console errors found: ${consoleMessages.length}`);
    
    let fixedErrors = 0;
    let remainingErrors = 0;
    
    // Check for original errors
    originalErrors.forEach(errorPattern => {
      const found = consoleMessages.some(msg => msg.includes(errorPattern));
      if (!found) {
        console.log(`✅ FIXED: "${errorPattern}"`);
        fixedErrors++;
      } else {
        console.log(`❌ STILL EXISTS: "${errorPattern}"`);
        remainingErrors++;
      }
    });

    // Check for dashboard rendering success - need to check all messages, not just errors
    const allMessages = [];
    page.on('console', msg => {
      allMessages.push(msg.text());
    });
    
    // Re-run to capture all messages including success logs
    await page.reload();
    await page.waitForTimeout(5000);
    
    const hasSuccessMessage = allMessages.some(msg => 
      msg.includes('All the visualizations data has loaded') ||
      msg.includes('All the visualizations now has rendered')
    );

    console.log('\n🎯 VERIFICATION RESULTS:');
    console.log(`✅ Fixed errors: ${fixedErrors}/${originalErrors.length}`);
    console.log(`❌ Remaining original errors: ${remainingErrors}`);
    console.log(`📈 Dashboard rendering: ${hasSuccessMessage ? 'SUCCESS' : 'FAILED'}`);

    // Check for new error types
    const newErrorTypes = new Set();
    consoleMessages.forEach(msg => {
      if (!originalErrors.some(pattern => msg.includes(pattern))) {
        // Extract error type
        if (msg.includes('Error trying to diff')) {
          newErrorTypes.add('NgFor iteration error (different component)');
        }
      }
    });

    if (newErrorTypes.size > 0) {
      console.log('\n🔍 NEW ERRORS DETECTED (different from original):');
      newErrorTypes.forEach(error => console.log(`⚠️  ${error}`));
    }

    console.log('\n🏆 SUMMARY:');
    if (fixedErrors === originalErrors.length && hasSuccessMessage) {
      console.log('✅ SUCCESS: All original dashboard errors have been fixed!');
      console.log('✅ Dashboard loads and renders properly');
    } else {
      console.log('❌ Some original errors still exist or dashboard failed to load');
    }

  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await browser.close();
  }
}

testDashboardComparison();
