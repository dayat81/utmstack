import { test, expect } from '@playwright/test';

test('homepage has title', async ({ page }) => {
  await page.goto('http://localhost:4200/');

  // Expect a title "UTMStack"
  await expect(page).toHaveTitle(/UTMSTACK Technology/);
});
