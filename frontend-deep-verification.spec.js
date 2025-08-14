const { test, expect } = require('@playwright/test');

test.describe('UTMStack Frontend Deep Verification', () => {
  
  test('Wait for Angular application to fully load', async ({ page }) => {
    // Set longer timeout for this test
    test.setTimeout(60000);
    
    await page.goto('http://localhost:4200');
    
    console.log('⏳ Waiting for network to be idle...');
    await page.waitForLoadState('networkidle');
    
    console.log('⏳ Waiting additional time for Angular to initialize...');
    await page.waitForTimeout(5000);
    
    // Check if Angular has bootstrapped by looking for any content in app-root
    const appRoot = await page.$('app-root');
    expect(appRoot).toBeTruthy();
    console.log('✅ app-root element found');
    
    // Check if app-root has any content
    const appRootContent = await page.textContent('app-root');
    console.log(`📄 app-root content length: ${appRootContent ? appRootContent.length : 0} characters`);
    
    if (appRootContent && appRootContent.trim().length > 0) {
      console.log('✅ Angular application has rendered content');
      console.log(`📝 Sample content: "${appRootContent.substring(0, 100)}..."`);
    } else {
      console.log('⚠️  Angular app-root is empty - may still be loading or have routing issues');
    }
    
    // Check for any visible elements on the page
    const allElements = await page.$$('*');
    const visibleElements = [];
    
    for (let element of allElements.slice(0, 20)) { // Check first 20 elements
      const isVisible = await element.isVisible();
      if (isVisible) {
        const tagName = await element.evaluate(el => el.tagName);
        visibleElements.push(tagName);
      }
    }
    
    console.log(`👁️  Visible elements: ${visibleElements.slice(0, 10).join(', ')}`);
    
    // Take another screenshot after waiting
    await page.screenshot({ path: 'utmstack-frontend-loaded.png', fullPage: true });
    console.log('📸 Updated screenshot saved as utmstack-frontend-loaded.png');
  });
  
  test('Check for Angular routing and navigation', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    
    // Try different route paths that might exist
    const testRoutes = [
      '/',
      '/login',
      '/dashboard', 
      '/auth',
      '/home'
    ];
    
    for (const route of testRoutes) {
      console.log(`🔍 Testing route: ${route}`);
      
      try {
        const response = await page.goto(`http://localhost:4200${route}`);
        console.log(`📍 ${route}: HTTP ${response.status()}`);
        
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(2000);
        
        const pageContent = await page.textContent('body');
        const contentLength = pageContent ? pageContent.length : 0;
        
        console.log(`📄 ${route}: Content length ${contentLength} characters`);
        
        if (contentLength > 100) {
          console.log(`✅ ${route} has substantial content`);
          break; // Found a route with content
        }
      } catch (error) {
        console.log(`❌ ${route}: Navigation failed - ${error.message}`);
      }
    }
  });
  
  test('Detailed HTML structure analysis', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    
    // Get the full HTML structure
    const htmlContent = await page.content();
    console.log(`📄 Total HTML length: ${htmlContent.length} characters`);
    
    // Check for specific Angular indicators
    const hasAngularZone = htmlContent.includes('ng-version') || htmlContent.includes('_ngcontent');
    const hasAppRoot = htmlContent.includes('<app-root');
    const hasAngularScripts = htmlContent.includes('main.js') && htmlContent.includes('vendor.js');
    
    console.log(`🔍 Angular indicators:`);
    console.log(`   - Angular Zone: ${hasAngularZone ? '✅' : '❌'}`);
    console.log(`   - App Root: ${hasAppRoot ? '✅' : '❌'}`);
    console.log(`   - Angular Scripts: ${hasAngularScripts ? '✅' : '❌'}`);
    
    // Check what's inside app-root
    const appRootHTML = await page.innerHTML('app-root').catch(() => '');
    console.log(`📦 app-root innerHTML length: ${appRootHTML.length} characters`);
    
    if (appRootHTML.length > 0) {
      console.log(`📝 app-root content preview: "${appRootHTML.substring(0, 200)}..."`);
    }
    
    // Check for Angular router outlet
    const hasRouterOutlet = appRootHTML.includes('router-outlet');
    console.log(`🔀 Router outlet present: ${hasRouterOutlet ? '✅' : '❌'}`);
  });
  
  test('Check browser console for Angular bootstrap', async ({ page }) => {
    const logs = [];
    
    page.on('console', (msg) => {
      logs.push({
        type: msg.type(),
        text: msg.text(),
        timestamp: Date.now()
      });
    });
    
    page.on('pageerror', (error) => {
      logs.push({
        type: 'pageerror',
        text: error.message,
        timestamp: Date.now()
      });
    });
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(5000);
    
    console.log(`📊 Captured ${logs.length} console messages`);
    
    // Look for Angular-specific messages
    const angularMessages = logs.filter(log => 
      log.text.toLowerCase().includes('angular') ||
      log.text.toLowerCase().includes('bootstrap') ||
      log.text.toLowerCase().includes('zone') ||
      log.text.toLowerCase().includes('ng') ||
      log.text.includes('defineInjectable')
    );
    
    if (angularMessages.length > 0) {
      console.log('🅰️ Angular-related messages:');
      angularMessages.slice(0, 5).forEach(msg => {
        console.log(`   [${msg.type}] ${msg.text}`);
      });
    }
    
    // Look for errors that might prevent rendering
    const errors = logs.filter(log => log.type === 'error' || log.type === 'pageerror');
    if (errors.length > 0) {
      console.log('❌ JavaScript errors:');
      errors.slice(0, 3).forEach(error => {
        console.log(`   ${error.text}`);
      });
    }
    
    // Check if there are any success indicators
    const successIndicators = logs.filter(log => 
      log.text.toLowerCase().includes('compiled') ||
      log.text.toLowerCase().includes('ready') ||
      log.text.toLowerCase().includes('started')
    );
    
    if (successIndicators.length > 0) {
      console.log('✅ Success indicators:');
      successIndicators.slice(0, 3).forEach(msg => {
        console.log(`   [${msg.type}] ${msg.text}`);
      });
    }
  });

});
