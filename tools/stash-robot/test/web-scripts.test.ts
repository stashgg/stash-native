import test from "node:test";
import assert from "node:assert/strict";
import { chromium } from "@playwright/test";
import {
  CSS_ID,
  cssScript,
  inspectScript,
  resetCssScript,
} from "../src/web-scripts.js";

test("live CSS replacement/reset preserves original page styles and safely quotes CSS", async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent(
      '<style>button { color: rgb(1, 2, 3) }</style><button id="checkout">Pay</button>',
    );
    const evaluate = (script: string) => page.evaluate(script);
    await evaluate(cssScript("button { color: rgb(20, 30, 40) !important; }"));
    assert.equal(
      await page.$eval("button", (element) => getComputedStyle(element).color),
      "rgb(20, 30, 40)",
    );
    await evaluate(
      cssScript(
        'button::after { content: "quotes \\\" and </style>"; } button {color: rgb(50, 60, 70) !important;}',
      ),
    );
    assert.equal(await page.locator(`#${CSS_ID}`).count(), 1);
    assert.equal(
      await page.$eval("button", (element) => getComputedStyle(element).color),
      "rgb(50, 60, 70)",
    );
    const inspected: any = await evaluate(inspectScript("#checkout"));
    assert.equal(inspected.elements[0].text, "Pay");
    assert.equal(inspected.elements[0].styles.color, "rgb(50, 60, 70)");
    assert.ok(inspected.elements[0].bounds.width > 0);
    await evaluate(resetCssScript);
    assert.equal(
      await page.$eval("button", (element) => getComputedStyle(element).color),
      "rgb(1, 2, 3)",
    );
    assert.equal(await page.locator(`#${CSS_ID}`).count(), 0);
  } finally {
    await browser.close();
  }
});
