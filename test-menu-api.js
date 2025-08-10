const { chromium } = require('playwright');

async function testMenuAPI() {
  console.log('🔍 Testing Menu API response structure...');
  
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
            console.log('📋 Menu Data Structure:');
            console.log('   Type:', typeof data);
            console.log('   Is Array:', Array.isArray(data));
            console.log('   Length:', data?.length || 'N/A');
            
            if (Array.isArray(data) && data.length > 0) {
              console.log('   First Item:', typeof data[0]);
              console.log('   First Item Keys:', Object.keys(data[0]));
              
              // Check children structure
              if (data[0].childrens !== undefined) {
                console.log('   childrens type:', typeof data[0].childrens);
                console.log('   childrens is array:', Array.isArray(data[0].childrens));
                console.log('   childrens value:', data[0].childrens);
              }
              
              // Check actions structure  
              if (data[0].actions !== undefined) {
                console.log('   actions type:', typeof data[0].actions);
                console.log('   actions is array:', Array.isArray(data[0].actions));
                console.log('   actions value:', data[0].actions);
              }
            }
            
            // Check for problematic data
            const problemMenus = data.filter(menu => {
              const hasObjectChildrens = menu.childrens && !Array.isArray(menu.childrens);
              const hasObjectActions = menu.actions && !Array.isArray(menu.actions);
              return hasObjectChildrens || hasObjectActions;
            });
            
            if (problemMenus.length > 0) {
              console.log('❌ FOUND PROBLEMATIC MENUS:');
              problemMenus.forEach((menu, index) => {
                console.log(`   Menu ${index + 1}: ${menu.name}`);
                if (menu.childrens && !Array.isArray(menu.childrens)) {
                  console.log(`      childrens is ${typeof menu.childrens}:`, menu.childrens);
                }
                if (menu.actions && !Array.isArray(menu.actions)) {
                  console.log(`      actions is ${typeof menu.actions}:`, menu.actions);
                }
              });
            } else {
              console.log('✅ All menu structures are valid arrays');
            }
            
          } catch (e) {
            console.error('❌ Failed to parse menu response:', e.message);
          }
        } else {
          console.error('❌ Menu API failed:', response.status());
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

testMenuAPI();
