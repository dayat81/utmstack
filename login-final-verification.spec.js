const { test, expect } = require('@playwright/test');

test.describe('UTMStack Login Final Verification', () => {
  
  test('Verify frontend loads with correct backend connection', async ({ page }) => {
    const jsErrors = [];
    const networkRequests = [];
    
    // Capture errors and requests
    page.on('pageerror', (error) => jsErrors.push(error.message));
    page.on('request', (request) => {
      if (request.url().includes('/api/')) {
        networkRequests.push({
          url: request.url(),
          method: request.method()
        });
      }
    });
    
    console.log('🔍 Testing frontend with corrected backend connection...');
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(5000); // Give Angular time to initialize
    
    // Check app-root content
    const appRootInfo = await page.evaluate(() => ({
      hasContent: document.querySelector('app-root')?.innerHTML?.length > 10,
      contentLength: document.querySelector('app-root')?.innerHTML?.length || 0,
      firstChild: document.querySelector('app-root')?.firstElementChild?.tagName || 'none'
    }));
    
    console.log('📱 App-root analysis:');
    console.log(`   Has content: ${appRootInfo.hasContent}`);
    console.log(`   Content length: ${appRootInfo.contentLength} characters`);
    console.log(`   First child element: ${appRootInfo.firstChild}`);
    
    // Check for API requests to correct port
    console.log('\n📡 API Requests to port 8080:');
    const port8080Requests = networkRequests.filter(req => req.url.includes(':8080'));
    if (port8080Requests.length > 0) {
      port8080Requests.forEach(req => {
        console.log(`   ✅ ${req.method} ${req.url}`);
      });
    } else {
      console.log('   ⚠️  No requests to port 8080 detected');
    }
    
    // Check for errors
    console.log('\n🚫 JavaScript Errors:');
    if (jsErrors.length > 0) {
      jsErrors.forEach((error, index) => {
        console.log(`   ${index + 1}. ${error}`);
      });
    } else {
      console.log('   ✅ No JavaScript errors detected');
    }
    
    // Take a screenshot
    await page.screenshot({ path: 'utmstack-frontend-loaded.png', fullPage: true });
    console.log('📸 Screenshot saved as utmstack-frontend-loaded.png');
  });

  test('Look for login form after backend connection fix', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(8000); // Give more time for Angular to load
    
    console.log('🔐 Searching for login form elements...');
    
    // Wait for potential dynamic content
    try {
      await page.waitForSelector('input, button, form', { timeout: 10000 });
      console.log('✅ Input elements detected, analyzing...');
    } catch (e) {
      console.log('⚠️  No input elements detected within 10 seconds');
    }
    
    // Check for any form elements
    const formElements = await page.evaluate(() => {
      const inputs = Array.from(document.querySelectorAll('input')).map(input => ({
        type: input.type,
        name: input.name || '',
        placeholder: input.placeholder || '',
        id: input.id || '',
        visible: input.offsetParent !== null
      }));
      
      const buttons = Array.from(document.querySelectorAll('button')).map(button => ({
        text: button.textContent?.trim() || '',
        type: button.type || 'button',
        visible: button.offsetParent !== null
      }));
      
      const forms = Array.from(document.querySelectorAll('form')).map(form => ({
        action: form.action || '',
        method: form.method || 'get',
        id: form.id || '',
        visible: form.offsetParent !== null
      }));
      
      return { inputs, buttons, forms };
    });
    
    console.log('\n📝 Form Analysis:');
    console.log(`   Input fields found: ${formElements.inputs.length}`);
    console.log(`   Buttons found: ${formElements.buttons.length}`);
    console.log(`   Forms found: ${formElements.forms.length}`);
    
    if (formElements.inputs.length > 0) {
      console.log('\n📋 Input Fields:');
      formElements.inputs.forEach((input, index) => {
        const visibleStatus = input.visible ? '👁️' : '🙈';
        console.log(`   ${index + 1}. ${visibleStatus} Type: ${input.type}, Name: "${input.name}", Placeholder: "${input.placeholder}"`);
      });
    }
    
    if (formElements.buttons.length > 0) {
      console.log('\n🔘 Buttons:');
      formElements.buttons.forEach((button, index) => {
        const visibleStatus = button.visible ? '👁️' : '🙈';
        console.log(`   ${index + 1}. ${visibleStatus} "${button.text}" (${button.type})`);
      });
    }
    
    // Look specifically for login-related elements
    const loginElements = await page.$$eval('*', elements => {
      return elements
        .filter(el => {
          const text = el.textContent?.toLowerCase() || '';
          const className = el.className?.toLowerCase() || '';
          const id = el.id?.toLowerCase() || '';
          return text.includes('login') || text.includes('sign in') || 
                 className.includes('login') || id.includes('login') ||
                 text.includes('email') || text.includes('password');
        })
        .map(el => ({
          tag: el.tagName.toLowerCase(),
          text: el.textContent?.trim().substring(0, 50) || '',
          class: el.className || '',
          id: el.id || ''
        }))
        .slice(0, 10); // Limit to first 10 matches
    });
    
    if (loginElements.length > 0) {
      console.log('\n🔐 Login-related Elements:');
      loginElements.forEach((element, index) => {
        console.log(`   ${index + 1}. <${element.tag}> "${element.text}" (class: ${element.class})`);
      });
    }
  });

  test('Test authentication flow', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(5000);
    
    console.log('🔒 Testing authentication flow...');
    
    // Check if we're redirected to login
    const currentUrl = page.url();
    console.log(`Current URL: ${currentUrl}`);
    
    if (currentUrl.includes('login') || currentUrl.includes('auth')) {
      console.log('✅ Redirected to authentication page');
    } else {
      console.log('ℹ️  No automatic redirect to login detected');
    }
    
    // Try to access a protected route
    console.log('\n🔐 Testing protected route access...');
    await page.goto('http://localhost:4200/dashboard');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    
    const dashboardUrl = page.url();
    console.log(`Dashboard URL result: ${dashboardUrl}`);
    
    if (dashboardUrl.includes('login') || dashboardUrl.includes('auth')) {
      console.log('✅ Protected route redirected to login - authentication working');
    } else if (dashboardUrl.includes('dashboard')) {
      console.log('⚠️  Dashboard accessible without login');
      
      // Check if dashboard content is actually loaded
      const dashboardContent = await page.evaluate(() => ({
        hasContent: document.body.textContent?.trim().length > 100,
        title: document.title,
        contentPreview: document.body.textContent?.trim().substring(0, 200)
      }));
      
      console.log(`   Dashboard content loaded: ${dashboardContent.hasContent}`);
      if (dashboardContent.hasContent) {
        console.log(`   Content preview: "${dashboardContent.contentPreview}..."`);
      }
    }
  });

  test('Check for authentication API endpoints and responses', async ({ page }) => {
    const apiCalls = [];
    
    page.on('response', async (response) => {
      if (response.url().includes('/api/')) {
        try {
          const responseData = {
            url: response.url(),
            status: response.status(),
            statusText: response.statusText(),
            headers: response.headers(),
            body: null
          };
          
          // Try to get response body for small responses
          if (response.status() !== 200 || response.headers()['content-length'] < 1000) {
            try {
              responseData.body = await response.text();
            } catch (e) {
              responseData.body = 'Could not read body';
            }
          }
          
          apiCalls.push(responseData);
        } catch (e) {
          console.log(`Error capturing API response: ${e.message}`);
        }
      }
    });
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(5000);
    
    console.log('\n🌐 API Response Analysis:');
    if (apiCalls.length > 0) {
      apiCalls.forEach((call, index) => {
        const endpoint = call.url.split('/api/')[1] || call.url;
        console.log(`   ${index + 1}. /api/${endpoint}: ${call.status} ${call.statusText}`);
        
        if (call.body && call.body.length < 200) {
          console.log(`      Response: ${call.body}`);
        }
        
        if (call.status === 401) {
          console.log('      🔒 Authentication required');
        } else if (call.status === 200) {
          console.log('      ✅ Success');
        }
      });
    } else {
      console.log('   ℹ️  No API calls captured');
    }
  });

});
