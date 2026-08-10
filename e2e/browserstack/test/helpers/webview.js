// Switches into the checkout webview so we can drive the payment form, then back
// to native. This only works because the sample apps call
// StashNativeCard.setInspectableWebViewsEnabled(true) on launch, which makes the
// SDK webview show up as an inspectable context.

async function switchToCheckoutWebview(timeout = 20000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const contexts = await driver.getContexts();
    const web = contexts.find((c) => String(c).toUpperCase().includes("WEBVIEW"));
    if (web) {
      await driver.switchContext(web);
      return web;
    }
    await driver.pause(1000);
  }
  throw new Error("No webview context found. Is inspection enabled on the SDK webview?");
}

async function switchToNative() {
  await driver.switchContext("NATIVE_APP");
}

module.exports = { switchToCheckoutWebview, switchToNative };
