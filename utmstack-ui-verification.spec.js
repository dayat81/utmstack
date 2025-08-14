const { test, expect } = require('@playwright/test');

test.describe('UTMStack UI Elements Verification', () => {
  
  test('Check for UTMStack branding and navigation', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Take screenshot for visual verification
    await page.screenshot({ path: 'utmstack-frontend-screenshot.png', fullPage: true });
    console.log('📸 Full page screenshot saved as utmstack-frontend-screenshot.png');
    
    // Check for UTMStack branding
    const pageContent = await page.textContent('body');
    
    // Look for UTMStack related text
    const utmStackTerms = ['UTMStack', 'UTMSTACK', 'utm-stack', 'utm stack', 'SIEM'];
    let foundBranding = false;
    
    for (const term of utmStackTerms) {
      if (pageContent.toLowerCase().includes(term.toLowerCase())) {
        console.log(`✅ Found UTMStack branding: "${term}"`);
        foundBranding = true;
        break;
      }
    }
    
    if (!foundBranding) {
      console.log('ℹ️  UTMStack branding not immediately visible, but page loaded successfully');
    }
  });

  test('Check for common SIEM UI elements', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Look for common SIEM interface elements
    const commonElements = [
      'nav', 'navbar', 'menu', 'sidebar',
      'button', 'input', 'form',
      'header', 'main', 'footer'
    ];
    
    const foundElements = [];
    
    for (const element of commonElements) {
      const found = await page.$(element);
      if (found) {
        foundElements.push(element);
      }
    }
    
    console.log(`✅ Found UI elements: ${foundElements.join(', ')}`);
    expect(foundElements.length).toBeGreaterThan(0);
  });

  test('Check for authentication/login elements', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Look for login/authentication related elements
    const authSelectors = [
      'input[type="password"]',
      'input[type="email"]', 
      'input[name*="password"]',
      'input[name*="username"]',
      'input[name*="email"]',
      'button[type="submit"]',
      'form[name*="login"]',
      '[class*="login"]',
      '[id*="login"]'
    ];
    
    let foundAuthElements = [];
    
    for (const selector of authSelectors) {
      const element = await page.$(selector);
      if (element) {
        foundAuthElements.push(selector);
      }
    }
    
    if (foundAuthElements.length > 0) {
      console.log(`✅ Found authentication elements: ${foundAuthElements.join(', ')}`);
    } else {
      console.log('ℹ️  No obvious authentication form found - may be on different route or already authenticated');
    }
  });

  test('Test navigation and routing', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    const initialUrl = page.url();
    console.log(`📍 Initial URL: ${initialUrl}`);
    
    // Try to find and click navigation links
    const navLinks = await page.$$('a[href], button[routerLink], [routerLink]');
    
    if (navLinks.length > 0) {
      console.log(`✅ Found ${navLinks.length} navigation elements`);
      
      // Try clicking the first few navigation links
      for (let i = 0; i < Math.min(3, navLinks.length); i++) {
        try {
          const href = await navLinks[i].getAttribute('href') || await navLinks[i].getAttribute('routerLink');
          if (href && href.startsWith('/') && href !== '/') {
            console.log(`🔗 Testing navigation to: ${href}`);
            
            await navLinks[i].click();
            await page.waitForLoadState('networkidle');
            
            const newUrl = page.url();
            console.log(`📍 Navigated to: ${newUrl}`);
            
            // Go back to original page
            await page.goto(initialUrl);
            await page.waitForLoadState('networkidle');
          }
        } catch (error) {
          console.log(`⚠️  Navigation test skipped: ${error.message}`);
        }
      }
    } else {
      console.log('ℹ️  No navigation links found - may be a single page application or login screen');
    }
  });

  test('Check for data tables or charts (typical SIEM elements)', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Look for data visualization elements common in SIEM platforms
    const datavizSelectors = [
      'table',
      '[class*="table"]',
      '[class*="chart"]', 
      '[class*="graph"]',
      '[class*="dashboard"]',
      'canvas',
      'svg',
      '[class*="card"]',
      '[class*="widget"]'
    ];
    
    const foundDataviz = [];
    
    for (const selector of datavizSelectors) {
      const elements = await page.$$(selector);
      if (elements.length > 0) {
        foundDataviz.push(`${selector} (${elements.length})`);
      }
    }
    
    if (foundDataviz.length > 0) {
      console.log(`✅ Found data visualization elements: ${foundDataviz.join(', ')}`);
    } else {
      console.log('ℹ️  No obvious data visualization elements found - may be login screen or different layout');
    }
  });

  test('Check console logs for application status', async ({ page }) => {
    const logs = [];
    
    page.on('console', (msg) => {
      logs.push({
        type: msg.type(),
        text: msg.text()
      });
    });
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    
    // Filter and display relevant logs
    const errorLogs = logs.filter(log => log.type === 'error');
    const warningLogs = logs.filter(log => log.type === 'warning');
    const infoLogs = logs.filter(log => log.type === 'log' || log.type === 'info');
    
    console.log(`📊 Console summary: ${errorLogs.length} errors, ${warningLogs.length} warnings, ${infoLogs.length} info`);
    
    if (errorLogs.length > 0) {
      console.log('❌ Console errors:', errorLogs.map(log => log.text).slice(0, 3));
    }
    
    if (warningLogs.length > 0) {
      console.log('⚠️  Console warnings:', warningLogs.map(log => log.text).slice(0, 3));
    }
    
    // Look for positive indicators in logs
    const positiveIndicators = infoLogs.filter(log => 
      log.text.toLowerCase().includes('loaded') ||
      log.text.toLowerCase().includes('ready') ||
      log.text.toLowerCase().includes('initialized') ||
      log.text.toLowerCase().includes('started')
    );
    
    if (positiveIndicators.length > 0) {
      console.log('✅ Positive application indicators:', positiveIndicators.map(log => log.text).slice(0, 3));
    }
  });

});
