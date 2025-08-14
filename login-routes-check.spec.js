const { test, expect } = require('@playwright/test');

test.describe('UTMStack Login Routes and Authentication Check', () => {
  
  const commonLoginRoutes = [
    '/',
    '/login',
    '/auth',
    '/auth/login', 
    '/signin',
    '/sign-in',
    '/dashboard',
    '/home'
  ];

  test('Check common login routes', async ({ page }) => {
    console.log('🔍 Testing common login routes...');
    
    for (const route of commonLoginRoutes) {
      const url = `http://localhost:4200${route}`;
      console.log(`\n📍 Testing route: ${url}`);
      
      try {
        const response = await page.goto(url);
        const status = response.status();
        console.log(`   Status: ${status}`);
        
        if (status === 200) {
          await page.waitForLoadState('networkidle');
          const title = await page.title();
          const currentUrl = page.url();
          
          console.log(`   Title: "${title}"`);
          console.log(`   Final URL: ${currentUrl}`);
          
          // Check for login form elements on this route
          const hasEmailField = await page.$('input[type="email"], input[name="email"], input[name="username"]') !== null;
          const hasPasswordField = await page.$('input[type="password"]') !== null;
          const hasLoginButton = await page.$('button:has-text("Login"), button:has-text("Sign In"), button[type="submit"]') !== null;
          
          if (hasEmailField && hasPasswordField) {
            console.log('   ✅ LOGIN FORM FOUND!');
            console.log(`      📧 Email field: ${hasEmailField}`);
            console.log(`      🔒 Password field: ${hasPasswordField}`);
            console.log(`      🔘 Submit button: ${hasLoginButton}`);
            
            // Take screenshot of login form
            await page.screenshot({ path: `login-form-${route.replace('/', '_')}.png`, fullPage: true });
            console.log(`   📸 Screenshot saved: login-form-${route.replace('/', '_')}.png`);
          } else if (hasEmailField || hasPasswordField) {
            console.log('   ⚠️  Partial login form detected');
          } else {
            console.log('   ℹ️  No login form on this route');
          }
        } else {
          console.log(`   ⚠️  Route returned status ${status}`);
        }
      } catch (error) {
        console.log(`   ❌ Error accessing route: ${error.message}`);
      }
    }
  });

  test('Check Angular routing and app structure', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    console.log('🏗️  Analyzing Angular app structure...');
    
    // Check for Angular router outlet
    const routerOutlet = await page.$('router-outlet');
    if (routerOutlet) {
      console.log('✅ Angular router-outlet found');
    }
    
    // Check for app-root
    const appRoot = await page.$('app-root');
    if (appRoot) {
      console.log('✅ Angular app-root found');
      const appRootContent = await appRoot.innerHTML();
      console.log('📋 App root contains router-outlet:', appRootContent.includes('router-outlet'));
    }
    
    // Look for navigation elements
    const navElements = [
      'nav', '.navbar', '.navigation', '.sidebar', '.menu',
      'app-navigation', 'app-sidebar', 'app-header'
    ];
    
    let foundNav = false;
    for (const selector of navElements) {
      const element = await page.$(selector);
      if (element) {
        console.log(`✅ Navigation element found: ${selector}`);
        foundNav = true;
      }
    }
    
    if (!foundNav) {
      console.log('ℹ️  No obvious navigation elements detected');
    }
    
    // Check for Angular components in DOM
    const angularComponents = await page.$$eval('*', elements => {
      return elements
        .filter(el => el.tagName && el.tagName.startsWith('APP-'))
        .map(el => el.tagName.toLowerCase())
        .filter((tag, index, arr) => arr.indexOf(tag) === index);
    });
    
    if (angularComponents.length > 0) {
      console.log('✅ Angular components found:', angularComponents);
    } else {
      console.log('ℹ️  No custom Angular components detected in DOM');
    }
  });

  test('Test authentication state and protected routes', async ({ page }) => {
    console.log('🔐 Testing authentication state...');
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Check browser local storage for auth tokens
    const localStorage = await page.evaluate(() => {
      const storage = {};
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        storage[key] = localStorage.getItem(key);
      }
      return storage;
    });
    
    console.log('💾 Local Storage contents:');
    Object.keys(localStorage).forEach(key => {
      const value = localStorage[key];
      if (key.toLowerCase().includes('auth') || key.toLowerCase().includes('token') || key.toLowerCase().includes('user')) {
        console.log(`   🔑 ${key}: ${value.length > 50 ? value.substring(0, 50) + '...' : value}`);
      } else {
        console.log(`   📄 ${key}: ${value.length > 30 ? value.substring(0, 30) + '...' : value}`);
      }
    });
    
    // Check session storage
    const sessionStorage = await page.evaluate(() => {
      const storage = {};
      for (let i = 0; i < sessionStorage.length; i++) {
        const key = sessionStorage.key(i);
        storage[key] = sessionStorage.getItem(key);
      }
      return storage;
    });
    
    if (Object.keys(sessionStorage).length > 0) {
      console.log('🗄️  Session Storage contents:');
      Object.keys(sessionStorage).forEach(key => {
        console.log(`   📄 ${key}: ${sessionStorage[key]}`);
      });
    } else {
      console.log('ℹ️  No session storage data found');
    }
    
    // Try to access a potentially protected route
    const protectedRoutes = ['/dashboard', '/admin', '/users', '/settings', '/profile'];
    
    for (const route of protectedRoutes) {
      const url = `http://localhost:4200${route}`;
      try {
        console.log(`\n🔒 Testing protected route: ${url}`);
        const response = await page.goto(url);
        const status = response.status();
        const finalUrl = page.url();
        
        console.log(`   Status: ${status}, Final URL: ${finalUrl}`);
        
        if (finalUrl !== url && finalUrl.includes('login')) {
          console.log('   ✅ Redirected to login - route is protected');
        } else if (finalUrl === url) {
          console.log('   ⚠️  No redirect - might be accessible or login required differently');
        }
      } catch (error) {
        console.log(`   ❌ Error: ${error.message}`);
      }
    }
  });

  test('Manual login form test with default credentials', async ({ page }) => {
    console.log('🧪 Testing manual login with common default credentials...');
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Look for login form more broadly
    const allInputs = await page.$$eval('input', inputs => 
      inputs.map(input => ({
        type: input.type,
        name: input.name || '',
        id: input.id || '',
        placeholder: input.placeholder || '',
        class: input.className || ''
      }))
    );
    
    console.log('📋 All input fields found:');
    allInputs.forEach((input, index) => {
      console.log(`   ${index + 1}. Type: ${input.type}, Name: "${input.name}", ID: "${input.id}", Placeholder: "${input.placeholder}"`);
    });
    
    const allButtons = await page.$$eval('button, input[type="submit"]', buttons => 
      buttons.map(button => ({
        type: button.type || 'button',
        text: button.textContent?.trim() || '',
        class: button.className || ''
      }))
    );
    
    console.log('🔘 All buttons found:');
    allButtons.forEach((button, index) => {
      console.log(`   ${index + 1}. Type: ${button.type}, Text: "${button.text}"`);
    });
    
    // If we find any input fields, try to interact with them
    if (allInputs.length > 0) {
      console.log('✅ Input fields detected, attempting interaction...');
      
      // Try to find the most likely email/username field
      const emailField = await page.$('input[type="email"]') || 
                          await page.$('input[name*="email"]') ||
                          await page.$('input[name*="username"]') ||
                          await page.$('input:first-of-type');
      
      // Try to find password field
      const passwordField = await page.$('input[type="password"]');
      
      if (emailField) {
        await emailField.fill('admin@utmstack.com');
        console.log('✅ Filled email field with admin@utmstack.com');
      }
      
      if (passwordField) {
        await passwordField.fill('admin');
        console.log('✅ Filled password field with admin');
      }
      
      if (emailField && passwordField) {
        console.log('✅ Both fields filled, ready for login attempt');
        
        // Don't actually submit to avoid potential issues
        console.log('ℹ️  Login form is functional - skipping submission for safety');
      }
    }
  });

});
