const { chromium } = require('playwright');

async function testMenuResponse() {
  console.log('🔍 Testing detailed Menu API response...');
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log('🌐 Navigating to dashboard...');
    await page.goto('http://localhost:4200/dashboard/overview', { 
      waitUntil: 'networkidle',
      timeout: 30000 
    });

    // Listen for API responses
    page.on('response', async response => {
      if (response.url().includes('/api/menu/all')) {
        console.log('📡 Menu API Request:', response.url());
        console.log('📊 Response Status:', response.status());
        
        if (response.ok()) {
          try {
            const data = await response.json();
            console.log('📋 Raw Menu Response:');
            console.log(JSON.stringify(data, null, 2));
            
          } catch (e) {
            console.error('❌ Failed to parse menu response:', e.message);
          }
        } else {
          console.error('❌ Menu API failed:', response.status());
          const errorText = await response.text();
          console.log('Error details:', errorText);
        }
      }
    });

    await page.waitForTimeout(8000);

  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await browser.close();
  }
}

testMenuResponse();
