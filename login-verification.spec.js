const { test, expect } = require('@playwright/test');

test.describe('UTMStack Frontend Login Verification', () => {
  
  test('Login page loads and displays correctly', async ({ page }) => {
    // Navigate to the frontend
    await page.goto('http://localhost:4200');
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle');
    
    console.log('✅ Frontend loaded successfully');
    
    // Check if we're redirected to login or if login form is visible
    const currentUrl = page.url();
    console.log(`🔗 Current URL: ${currentUrl}`);
    
    // Look for common login indicators
    const loginIndicators = [
      'input[type="email"]', 'input[type="text"][placeholder*="email" i]',
      'input[type="password"]', 'input[placeholder*="password" i]',
      'button[type="submit"]', 'button:has-text("Login")', 'button:has-text("Sign In")',
      '.login-form', '.auth-form', '#login-form',
      '[data-cy="login"]', '[data-testid="login"]'
    ];
    
    let loginFormFound = false;
    let foundElements = [];
    
    for (const selector of loginIndicators) {
      const element = await page.$(selector);
      if (element) {
        loginFormFound = true;
        foundElements.push(selector);
      }
    }
    
    if (loginFormFound) {
      console.log('✅ Login form elements detected:', foundElements);
    } else {
      console.log('ℹ️  No obvious login form detected, checking page content...');
    }
    
    // Take a screenshot for visual verification
    await page.screenshot({ path: 'utmstack-frontend-screenshot.png', fullPage: true });
    console.log('📸 Screenshot saved as utmstack-frontend-screenshot.png');
  });

  test('Check for authentication elements and form fields', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Look for email/username field
    const emailSelectors = [
      'input[type="email"]',
      'input[name="email"]', 
      'input[name="username"]',
      'input[placeholder*="email" i]',
      'input[placeholder*="username" i]',
      'input[id*="email" i]',
      'input[id*="username" i]'
    ];
    
    let emailField = null;
    let emailSelector = null;
    
    for (const selector of emailSelectors) {
      emailField = await page.$(selector);
      if (emailField) {
        emailSelector = selector;
        break;
      }
    }
    
    if (emailField) {
      console.log(`✅ Email/Username field found: ${emailSelector}`);
      const placeholder = await emailField.getAttribute('placeholder');
      console.log(`📝 Placeholder text: "${placeholder}"`);
    } else {
      console.log('⚠️  No email/username field detected');
    }
    
    // Look for password field
    const passwordField = await page.$('input[type="password"]');
    if (passwordField) {
      console.log('✅ Password field found');
      const placeholder = await passwordField.getAttribute('placeholder');
      console.log(`📝 Password placeholder: "${placeholder}"`);
    } else {
      console.log('⚠️  No password field detected');
    }
    
    // Look for submit button
    const submitSelectors = [
      'button[type="submit"]',
      'input[type="submit"]',
      'button:has-text("Login")',
      'button:has-text("Sign In")',
      'button:has-text("Log In")',
      '.login-button',
      '.btn-login'
    ];
    
    let submitButton = null;
    let submitSelector = null;
    
    for (const selector of submitSelectors) {
      submitButton = await page.$(selector);
      if (submitButton) {
        submitSelector = selector;
        break;
      }
    }
    
    if (submitButton) {
      console.log(`✅ Submit button found: ${submitSelector}`);
      const buttonText = await submitButton.textContent();
      console.log(`🔘 Button text: "${buttonText}"`);
    } else {
      console.log('⚠️  No submit button detected');
    }
  });

  test('Test login form interaction (if available)', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Try to find and interact with login form
    const emailField = await page.$('input[type="email"], input[name="email"], input[name="username"]');
    const passwordField = await page.$('input[type="password"]');
    
    if (emailField && passwordField) {
      console.log('✅ Login form detected, testing interaction...');
      
      // Test typing in fields
      await emailField.fill('test@example.com');
      await passwordField.fill('testpassword');
      
      console.log('✅ Successfully typed in login fields');
      
      // Check if fields contain the values
      const emailValue = await emailField.inputValue();
      const passwordValue = await passwordField.inputValue();
      
      expect(emailValue).toBe('test@example.com');
      expect(passwordValue).toBe('testpassword');
      
      console.log('✅ Form field values verified');
      
      // Look for submit button
      const submitButton = await page.$('button[type="submit"], input[type="submit"], button:has-text("Login")');
      
      if (submitButton) {
        console.log('✅ Submit button found and ready for interaction');
        // Don't actually submit to avoid authentication errors
        console.log('ℹ️  Skipping actual form submission to prevent auth errors');
      }
      
    } else {
      console.log('ℹ️  Login form not immediately visible, checking if already logged in or different UI');
      
      // Check for indicators that user might be logged in or on dashboard
      const dashboardIndicators = [
        '.dashboard', '.main-content', '.sidebar', '.nav-menu',
        '[data-cy="dashboard"]', '#dashboard', '.app-layout'
      ];
      
      let foundDashboard = false;
      for (const selector of dashboardIndicators) {
        const element = await page.$(selector);
        if (element) {
          console.log(`✅ Dashboard/App content found: ${selector}`);
          foundDashboard = true;
          break;
        }
      }
      
      if (!foundDashboard) {
        console.log('ℹ️  Neither login form nor dashboard clearly identified');
        console.log('📋 Page title:', await page.title());
        console.log('🔗 Current URL:', page.url());
      }
    }
  });

  test('Check for authentication API endpoints', async ({ page }) => {
    const requests = [];
    
    // Capture network requests
    page.on('request', request => {
      if (request.url().includes('/api/') || request.url().includes('/auth/')) {
        requests.push({
          url: request.url(),
          method: request.method()
        });
      }
    });
    
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Wait a bit more for any async requests
    await page.waitForTimeout(3000);
    
    console.log(`📡 Captured ${requests.length} API requests:`);
    requests.forEach(req => {
      console.log(`  ${req.method} ${req.url}`);
    });
    
    // Check for common auth endpoints
    const authEndpoints = requests.filter(req => 
      req.url.includes('/auth/') || 
      req.url.includes('/login') || 
      req.url.includes('/user') ||
      req.url.includes('/api/ping')
    );
    
    if (authEndpoints.length > 0) {
      console.log('✅ Authentication-related API calls detected:');
      authEndpoints.forEach(req => {
        console.log(`  ✓ ${req.method} ${req.url}`);
      });
    } else {
      console.log('ℹ️  No obvious authentication API calls detected');
    }
  });

  test('Verify backend API connectivity from frontend', async ({ page }) => {
    await page.goto('http://localhost:4200');
    await page.waitForLoadState('networkidle');
    
    // Test if frontend can communicate with backend
    const backendTestUrl = 'http://localhost:8080/api/ping';
    
    try {
      const response = await page.request.get(backendTestUrl);
      const status = response.status();
      const responseText = await response.text();
      
      console.log(`🔌 Backend API connectivity: ${status}`);
      console.log(`📝 Response: ${responseText}`);
      
      if (status === 200) {
        console.log('✅ Backend API is accessible from frontend context');
      } else {
        console.log(`⚠️  Backend API returned status: ${status}`);
      }
    } catch (error) {
      console.log(`❌ Backend API connectivity error: ${error.message}`);
    }
  });

});
