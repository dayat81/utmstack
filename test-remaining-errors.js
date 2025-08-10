const { chromium } = require('playwright');

async function testRemainingErrors() {
  console.log('🔍 Testing remaining length errors...');
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  const lengthErrors = [];
  page.on('console', msg => {
    if (msg.type() === 'error' && msg.text().includes("Cannot read properties of undefined (reading 'length')")) {
      lengthErrors.push(msg.text());
    }
  });

  try {
    await page.goto('http://localhost:4200/dashboard/overview', { 
      waitUntil: 'networkidle',
      timeout: 30000 
    });

    await page.waitForTimeout(8000);

    console.log('\n❌ REMAINING LENGTH ERRORS:');
    const uniqueErrors = [...new Set(lengthErrors)];
    uniqueErrors.forEach((error, index) => {
      console.log(`${index + 1}. ${error}`);
    });
    
    console.log(`\nTotal unique length errors: ${uniqueErrors.length}`);
    console.log(`Total length error occurrences: ${lengthErrors.length}`);

  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await browser.close();
  }
}

testRemainingErrors();
