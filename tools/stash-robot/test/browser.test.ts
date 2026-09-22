import test from "node:test";
import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { chromium, expect } from "@playwright/test";
import { build } from "esbuild";
import { startServer } from "../src/server.js";
import { createFakeAdapter } from "../src/fake.js";

test(
  "browser selects devices, takes control, compares CSS, refreshes, and ends the same session",
  { timeout: 60000 },
  async () => {
    const root = resolve(import.meta.dirname, "..");
    await build({
      entryPoints: [join(root, "web", "app.ts")],
      bundle: true,
      format: "esm",
      outfile: join(root, "dist", "web", "app.js"),
      target: "es2022",
      logLevel: "silent",
    });
    const cacheDir = await mkdtemp(join(tmpdir(), "stash-robot-browser-"));
    const server = await startServer({
      repoRoot: resolve(root, "../.."),
      cacheDir,
      enableAgent: false,
      createAdapter: (platform, hooks) =>
        createFakeAdapter({ repoRoot: root, cacheDir, ...hooks }, platform),
    });
    const browser = await chromium.launch({ headless: true });
    try {
      const page = await browser.newPage({
        viewport: { width: 1400, height: 1050 },
      });
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(`${server.url}#token=${server.token}`);
      await expect(page.locator("#startPlatform")).toBeEnabled();
      await page.locator(".platform-card").filter({ hasText: "iOS" }).click();
      await expect(page.locator("#startPlatform")).toHaveText("Start iOS");
      await page.getByText("Advanced settings", { exact: true }).click();
      await page.locator("#device").selectOption("fake");
      assert.equal(
        server.session.snapshot().phase,
        "selecting",
        "selecting a platform does not launch it before overrides",
      );
      await page.locator("#startPlatform").click();
      await expect(page.locator("#phase")).toHaveText("ready · ios");
      await expect(page.locator("#screen")).toBeVisible();
      await page.locator("#takeControl").click();
      await expect(page.locator("#controlMode")).toHaveText("Manual control");
      await page.locator("#screen").click();
      await expect(page.locator("#target")).toHaveCount(1);
      await page
        .getByText("WebView diagnostics and logs", { exact: true })
        .click();
      await expect(page.locator("#applyCss")).toBeEnabled();
      await page.locator("#css").fill("body { outline: 12px solid magenta; }");
      await page.locator("#applyCss").click();
      await expect(page.locator("#comparison")).toBeVisible();
      await expect
        .poll(() =>
          page
            .locator("#afterImage")
            .evaluate((image: HTMLImageElement) => image.naturalWidth),
        )
        .toBe(320);
      await expect(page.locator("#activeCss")).toContainText("12px");
      const sessionId = server.session.snapshot().id;
      await page.reload();
      await expect(page.locator("#phase")).toHaveText("ready · ios");
      await expect(page.locator("#controlMode")).toHaveText("Manual control");
      assert.equal(server.session.snapshot().id, sessionId);
      await page
        .getByText("WebView diagnostics and logs", { exact: true })
        .click();
      await expect(page.locator("#resetCss")).toBeEnabled();
      await page.locator("#resetCss").click();
      await expect(page.locator("#activeCss")).toHaveText(
        "No active CSS override",
      );
      await page.locator('[data-action="rotate"]').click();
      await expect
        .poll(() =>
          page
            .locator("#screen")
            .evaluate((image: HTMLImageElement) => image.naturalWidth),
        )
        .toBe(640);
      const artifacts = resolve(root, "../../build/stash-robot/acceptance");
      await mkdir(artifacts, { recursive: true });
      await page.screenshot({
        path: join(artifacts, "browser.png"),
        fullPage: true,
      });
      await page.locator("#endSession").click();
      await expect(page.locator("#ended")).toBeVisible();
      assert.deepEqual(errors, []);
    } finally {
      await browser.close();
      await server.close();
      await rm(cacheDir, { recursive: true, force: true });
    }
  },
);
