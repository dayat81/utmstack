const { test, expect } = require('@playwright/test');

test.describe('UTMStack Frontend Debug Analysis', () => {
  
  test('Debug Angular application loading', async ({ page }) => {
    const jsErrors = [];
    const consoleMessages = [];
    const networkFailures = [];
    
    // Capture JavaScript errors
    page.on('pageerror', (error) => {
      jsErrors.push(error.message);
    });
    
    // Capture console messages
    page.on('console', (msg) => {
      consoleMessages.push(`${msg.type()}: ${msg.text()}`);
    });
    
    // Capture network failures
    page.on('requestfailed', (request) => {
      networkFailures.push(`${request.method()} ${request.url()} - ${request.failure()?.errorText}`);
    });
    
    console.log('🔍 Starting frontend debug analysis...');
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Wait for Angular to potentially load
    await page.waitForTimeout(5000);
    
    // Check if Angular is loaded
    const angularPresent = await page.evaluate(() => {
      return {
        hasAngular: typeof window.ng !== 'undefined',
        hasAppRoot: document.querySelector('app-root') !== null,
        appRootContent: document.querySelector('app-root')?.innerHTML || 'No content',
        scriptTags: Array.from(document.querySelectorAll('script')).map(s => s.src || 'inline'),
        bodyContent: document.body.innerHTML.length
      };
    });
    
    console.log('\n📊 Angular Analysis:');
    console.log(`   Angular present: ${angularPresent.hasAngular}`);
    console.log(`   App-root element: ${angularPresent.hasAppRoot}`);
    console.log(`   App-root content length: ${angularPresent.appRootContent.length} chars`);
    console.log(`   Body content length: ${angularPresent.bodyContent} chars`);
    console.log(`   Script tags loaded: ${angularPresent.scriptTags.length}`);
    
    if (angularPresent.appRootContent.length < 100) {
      console.log(`   ⚠️  App-root content: "${angularPresent.appRootContent}"`);
    }
    
    console.log('\n🚫 JavaScript Errors:');
    if (jsErrors.length > 0) {
      jsErrors.forEach((error, index) => {
        console.log(`   ${index + 1}. ${error}`);
      });
    } else {
      console.log('   ✅ No JavaScript errors detected');
    }
    
    console.log('\n🌐 Network Failures:');
    if (networkFailures.length > 0) {
      networkFailures.forEach((failure, index) => {
        console.log(`   ${index + 1}. ${failure}`);
      });
    } else {
      console.log('   ✅ No network failures detected');
    }
    
    console.log('\n📝 Console Messages (last 10):');
    const recentMessages = consoleMessages.slice(-10);
    if (recentMessages.length > 0) {
      recentMessages.forEach((msg, index) => {
        console.log(`   ${index + 1}. ${msg}`);
      });
    } else {
      console.log('   ℹ️  No console messages captured');
    }
  });

  test('Check if Angular modules and services are loaded', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    
    const moduleInfo = await page.evaluate(() => {
      const result = {
        windowObjects: Object.keys(window).filter(key => 
          key.toLowerCase().includes('angular') || 
          key.toLowerCase().includes('utm') ||
          key.toLowerCase().includes('app')
        ),
        angularElements: Array.from(document.querySelectorAll('*')).filter(el => 
          el.tagName && el.tagName.toLowerCase().startsWith('app-')
        ).map(el => el.tagName.toLowerCase()),
        hasBootstrap: typeof window.bootstrap !== 'undefined',
        hasJQuery: typeof window.$ !== 'undefined',
        scripts: Array.from(document.querySelectorAll('script[src]')).map(s => ({
          src: s.src,
          loaded: s.readyState === 'complete' || !s.readyState
        }))
      };
      
      return result;
    });
    
    console.log('\n🔧 Module Analysis:');
    console.log(`   Window objects with Angular/UTM/App: ${moduleInfo.windowObjects}`);
    console.log(`   Angular components in DOM: ${moduleInfo.angularElements}`);
    console.log(`   Bootstrap loaded: ${moduleInfo.hasBootstrap}`);
    console.log(`   jQuery loaded: ${moduleInfo.hasJQuery}`);
    
    console.log('\n📦 Script Loading Status:');
    moduleInfo.scripts.forEach((script, index) => {
      const fileName = script.src.split('/').pop();
      console.log(`   ${index + 1}. ${fileName}: ${script.loaded ? '✅' : '⏳'}`);
    });
  });

  test('Test direct API calls to understand backend connectivity', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    console.log('\n🔌 Testing backend API endpoints...');
    
    const apiEndpoints = [
      '/api/ping',
      '/api/auth/login',
      '/api/user/current',
      '/api/config',
      '/api/health'
    ];
    
    for (const endpoint of apiEndpoints) {
      try {
        const response = await page.request.get(`http://localhost:8080${endpoint}`);
        const status = response.status();
        const contentType = response.headers()['content-type'] || 'unknown';
        
        console.log(`   ${endpoint}: ${status} (${contentType})`);
        
        if (status === 200 && contentType.includes('json')) {
          try {
            const jsonBody = await response.json();
            console.log(`     Data: ${JSON.stringify(jsonBody).substring(0, 100)}...`);
          } catch (e) {
            const textBody = await response.text();
            console.log(`     Data: ${textBody.substring(0, 100)}...`);
          }
        }
      } catch (error) {
        console.log(`   ${endpoint}: ❌ ${error.message}`);
      }
    }
  });

  test('Check for loading states and spinners', async ({ page }) => {
    await page.goto('http://localhost:4200');
    
    console.log('\n⏳ Checking for loading states...');
    
    // Check immediately after navigation
    let immediateCheck = await page.evaluate(() => ({
      hasLoader: document.querySelector('.loader, .loading, .spinner, .fa-spinner') !== null,
      appRootChildren: document.querySelector('app-root')?.children.length || 0
    }));
    
    console.log(`   Immediate check - Loader: ${immediateCheck.hasLoader}, App children: ${immediateCheck.appRootChildren}`);
    
    // Wait and check again
    await page.waitForTimeout(2000);
    
    let delayedCheck = await page.evaluate(() => ({
      hasLoader: document.querySelector('.loader, .loading, .spinner, .fa-spinner') !== null,
      appRootChildren: document.querySelector('app-root')?.children.length || 0,
      totalElements: document.querySelectorAll('*').length
    }));
    
    console.log(`   After 2s - Loader: ${delayedCheck.hasLoader}, App children: ${delayedCheck.appRootChildren}, Total elements: ${delayedCheck.totalElements}`);
    
    // Final check after full load
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    
    let finalCheck = await page.evaluate(() => ({
      hasLoader: document.querySelector('.loader, .loading, .spinner, .fa-spinner') !== null,
      appRootChildren: document.querySelector('app-root')?.children.length || 0,
      totalElements: document.querySelectorAll('*').length,
      visibleElements: Array.from(document.querySelectorAll('*')).filter(el => {
        const style = window.getComputedStyle(el);
        return style.display !== 'none' && style.visibility !== 'hidden';
      }).length
    }));
    
    console.log(`   Final check - Loader: ${finalCheck.hasLoader}, App children: ${finalCheck.appRootChildren}, Total: ${finalCheck.totalElements}, Visible: ${finalCheck.visibleElements}`);
    
    if (finalCheck.appRootChildren === 0) {
      console.log('   ⚠️  Angular app may not be loading properly - app-root is empty');
    }
  });

});
