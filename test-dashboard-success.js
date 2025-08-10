const { chromium } = require('playwright');

async function testDashboardSuccess() {
  console.log('🚀 Checking dashboard success messages...');
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  const allMessages = [];
  page.on('console', msg => {
    allMessages.push({
      type: msg.type(),
      text: msg.text()
    });
  });

  try {
    console.log('🌐 Navigating to dashboard...');
    await page.goto('http://localhost:4200/dashboard/overview', { 
      waitUntil: 'networkidle',
      timeout: 30000 
    });

    await page.waitForTimeout(8000);

    console.log('\n📝 ALL CONSOLE MESSAGES:');
    allMessages.forEach((msg, index) => {
      console.log(`${index + 1}. [${msg.type}] ${msg.text}`);
    });

    const successMessages = allMessages.filter(msg => 
      msg.text.includes('visualizations') || 
      msg.text.includes('rendered') ||
      msg.text.includes('loaded')
    );

    console.log('\n🎯 SUCCESS-RELATED MESSAGES:');
    successMessages.forEach(msg => {
      console.log(`✅ [${msg.type}] ${msg.text}`);
    });

  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await browser.close();
  }
}

testDashboardSuccess();
