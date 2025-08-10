const { chromium } = require('playwright');

async function testDashboard() {
  console.log('Starting Playwright test for dashboard...');
  
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('Navigating to dashboard...');
    await page.goto('http://localhost:4200/dashboard/overview', { 
      waitUntil: 'networkidle',
      timeout: 30000 
    });

    // Wait for page to load
    await page.waitForTimeout(5000);

    // Check for console errors
    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.log('Console error:', msg.text());
      }
    });

    // Check for page errors
    page.on('pageerror', exception => {
      console.log('Page error:', exception.message);
    });

    // Take a screenshot
    await page.screenshot({ path: 'dashboard-error.png' });

    // Check if there are any visible error messages
    const errorElements = await page.$$('[class*="error"], .alert-danger, .error-message');
    if (errorElements.length > 0) {
      console.log('Found error elements on page');
      for (let i = 0; i < errorElements.length; i++) {
        const text = await errorElements[i].textContent();
        console.log(`Error ${i + 1}:`, text);
      }
    }

    // Check if the page title contains error information
    const title = await page.title();
    console.log('Page title:', title);

    // Check the current URL (might have redirected)
    const currentUrl = page.url();
    console.log('Current URL:', currentUrl);

    // Check if main content is loading
    const mainContent = await page.$('main, .main-content, .dashboard-content');
    if (mainContent) {
      console.log('Main content found');
    } else {
      console.log('Main content not found - possible loading issue');
    }

    console.log('Test completed successfully');

  } catch (error) {
    console.error('Test failed with error:', error.message);
  } finally {
    await browser.close();
  }
}

testDashboard();
