const sample = require("../pageobjects/sample.page");
const { fillCardForm } = require("../helpers/checkoutForm");
const testCards = require("../data/testCards");

// Same happy path as the card purchase but through the browser checkout.
//
// Note on Android: openBrowser uses Chrome Custom Tabs, which run as a separate
// app. Appium sees the Chrome webview as its own context, so the form fill still
// works, but returning to the sample app to read the callback chip may need a
// context/app switch back. iOS uses an in-app SFSafariViewController, which stays
// in the same session. This is the most environment-sensitive spec; expect to
// tweak it against a real session.
describe("Browser checkout purchase", () => {
  it("completes a purchase and receives the success callback", async () => {
    await driver.setOrientation("PORTRAIT");
    // Real checkout via signed payload, not the static test URL.
    await sample.generateCheckoutForBrowser();

    await fillCardForm(testCards.success);

    const chip = await sample.waitForPaymentSuccess();
    expect(await chip.isDisplayed()).toBe(true);
  });
});
