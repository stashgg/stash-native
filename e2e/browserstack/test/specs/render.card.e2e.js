const sample = require("../pageobjects/sample.page");
const { capture } = require("../helpers/screenshot");
const { switchToCheckoutWebview, switchToNative } = require("../helpers/webview");

// Captures how the checkout card renders across orientations and with the
// keyboard up. Goal is to spot layout bugs: nav/status bar over the card, card
// not rotating, keyboard covering inputs. Purely visual, no assertions. Runs on
// every device in the matrix so phones and tablets are both covered.
describe("Checkout card rendering", () => {
  it("captures the card in portrait, expanded, and landscape", async () => {
    await driver.setOrientation("PORTRAIT");
    // Generate a real checkout (signed payload -> live URL), not the static test URL.
    await sample.generateCheckout();

    // Card as first shown (collapsed).
    await capture("card-collapsed");

    // Drag the card up to expand it, then capture again.
    const { width, height } = await driver.getWindowSize();
    await driver
      .action("pointer")
      .move({ x: Math.round(width / 2), y: Math.round(height * 0.5) })
      .down()
      .move({ x: Math.round(width / 2), y: Math.round(height * 0.1), duration: 600 })
      .up()
      .perform();
    await driver.pause(1000);
    await capture("card-expanded");

    // Rotate to landscape and capture the same card. The SDK card is
    // portrait-locked, so the device may refuse to rotate while it is up; that
    // is itself what we want to see, so swallow the error and capture anyway.
    try {
      await driver.setOrientation("LANDSCAPE");
    } catch (e) {
      // Rotation blocked by the portrait-locked card. Expected; capture as-is.
    }
    await driver.pause(1500);
    await capture("card-landscape");

    try {
      await driver.setOrientation("PORTRAIT");
    } catch (e) {}
    await driver.pause(1500);
  });

  it("captures the card with the keyboard shown", async () => {
    // Focus the first input in the checkout webview to raise the keyboard.
    await switchToCheckoutWebview();
    const inputs = await $$("input");
    if (inputs.length > 0) {
      await inputs[0].click();
    }
    await switchToNative();
    await driver.pause(1500);
    await capture("card-keyboard");
  });
});
