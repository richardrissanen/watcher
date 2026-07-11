const { chromium } = require("playwright");

(async () => {
  const url = process.env.URL;
  const selector = process.env.SELECTOR || "[data-testid='car-list-results']";

  if (!url) {
    console.error("URL environment variable is required");
    process.exit(1);
  }

  const browser = await chromium.launch({
    headless: true
  });

  try {
    const page = await browser.newPage();

    await page.goto(url, {
      waitUntil: "networkidle",
      timeout: 30000
    });

    await page.waitForSelector(selector, {
      timeout: 15000
    });

    const html = await page.content();

    process.stdout.write(html);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  } finally {
    await browser.close();
  }
})();
