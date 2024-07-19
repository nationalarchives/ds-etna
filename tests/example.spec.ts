import { test, expect } from '@playwright/test';

test('has title', async ({ page }) => {
  await page.goto('http://localhost:65535');

  await expect(page).toHaveTitle(/The National Archives/);
});

test('explore the collection link', async ({ page }) => {
  await page.goto('http://localhost:65535/explore-the-collection/');

  await expect(page.getByText('What might you find in The National Archives? Browse some of our most important and unusual records right here.')).toBeVisible();
});
