const { chromium } = require('playwright');

async function testDashboardDetailed() {
  console.log('Starting detailed Playwright test for dashboard...');
  
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  // Capture all console messages
  const consoleMessages = [];
  page.on('console', msg => {
    consoleMessages.push({
      type: msg.type(),
      text: msg.text(),
      location: msg.location()
    });
    if (msg.type() === 'error') {
      console.log('❌ Console error:', msg.text());
    }
  });

  // Capture page errors
  const pageErrors = [];
  page.on('pageerror', exception => {
    pageErrors.push(exception.message);
    console.log('❌ Page error:', exception.message);
  });

  // Capture failed requests
  const failedRequests = [];
  page.on('response', response => {
    if (!response.ok()) {
      failedRequests.push({
        url: response.url(),
        status: response.status(),
        statusText: response.statusText()
      });
      console.log(`❌ Failed request: ${response.status()} ${response.url()}`);
    }
  });

  try {
    console.log('🌐 Navigating to dashboard...');
    await page.goto('http://localhost:4200/dashboard/overview', { 
      waitUntil: 'networkidle',
      timeout: 30000 
    });

    // Wait for Angular to load
    console.log('⏳ Waiting for Angular application...');
    await page.waitForTimeout(5000);

    // Check if we're on login page instead
    const currentUrl = page.url();
    console.log('📍 Current URL:', currentUrl);

    if (currentUrl.includes('/login')) {
      console.log('🔐 Redirected to login page - authentication required');
      // Try to login with default credentials
      await page.fill('input[name="username"], input[type="email"]', 'admin');
      await page.fill('input[name="password"], input[type="password"]', 'admin');
      await page.click('button[type="submit"], .btn-primary');
      await page.waitForTimeout(3000);
    }

    // Take screenshot
    await page.screenshot({ path: 'dashboard-detailed.png', fullPage: true });

    // Check page content
    const bodyText = await page.textContent('body');
    if (bodyText.includes('error') || bodyText.includes('Error')) {
      console.log('❌ Error text found in page body');
    }

    // Check for Angular loading errors
    const angularElement = await page.$('app-root');
    if (!angularElement) {
      console.log('❌ Angular app-root not found');
    } else {
      console.log('✅ Angular app-root found');
    }

    // Check for specific dashboard components
    const dashboardComponents = [
      'app-dashboard',
      '.dashboard-container',
      '.overview-content',
      '[class*="dashboard"]'
    ];

    for (const selector of dashboardComponents) {
      const element = await page.$(selector);
      if (element) {
        console.log(`✅ Found dashboard component: ${selector}`);
      } else {
        console.log(`❌ Missing dashboard component: ${selector}`);
      }
    }

    // Summary
    console.log('\n📊 Summary:');
    console.log(`Console messages: ${consoleMessages.length}`);
    console.log(`Page errors: ${pageErrors.length}`);
    console.log(`Failed requests: ${failedRequests.length}`);

    if (consoleMessages.length > 0) {
      console.log('\n📝 All console messages:');
      consoleMessages.forEach((msg, index) => {
        console.log(`${index + 1}. [${msg.type}] ${msg.text}`);
      });
    }

    if (failedRequests.length > 0) {
      console.log('\n🚫 Failed requests:');
      failedRequests.forEach((req, index) => {
        console.log(`${index + 1}. ${req.status} ${req.url}`);
      });
    }

  } catch (error) {
    console.error('❌ Test failed with error:', error.message);
  } finally {
    await browser.close();
  }
}

testDashboardDetailed();
