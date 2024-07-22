import { test, expect } from '@playwright/test';

test('has title', async ({ page }) => {
  await page.goto('/');

  await expect(page).toHaveTitle("The National Archives");

  // expect(await page.innerHTML('.tna-global-header')).toMatchSnapshot();

});
