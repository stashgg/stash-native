const sample = require("../pageobjects/sample.page");
const { fillCardForm } = require("../helpers/checkoutForm");
const testCards = require("../data/testCards");

// Full happy path: open the card, enter a success test card in the checkout
// webview, pay, then confirm the sample app received the payment-success
// callback (shown as a native chip). The webview form fill is best-effort and
// may need updating against a live session; see helpers/checkoutForm.js.
describe("Card checkout purchase", () => {
  it("completes a purchase and receives the success callback", async () => {
    await driver.setOrientation("PORTRAIT");
    // Real checkout via signed payload, not the static test URL.
    await sample.generateCheckout();

    await fillCardForm(testCards.success);

    const chip = await sample.waitForPaymentSuccess();
    expect(await chip.isDisplayed()).toBe(true);
  });
});
