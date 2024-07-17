import { test, expect } from '@playwright/test';

test('has title', async ({ page }) => {
  await page.goto('http://localhost:65535');

  await expect(page).toHaveTitle(/The National Archives/);
});

test('explore the collection link', async ({ page }) => {
  await page.goto('http://localhost:65535/explore-the-collection');

  await expect(page.getByText('What might you find in The National Archives? Browse picture galleries, stories and in-depth articles from our experts about some of our most famous records and hidden gems.')).toBeVisible();
});
