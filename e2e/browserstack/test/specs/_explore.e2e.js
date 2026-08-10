const sample = require("../pageobjects/sample.page");
const { fillCardForm } = require("../helpers/checkoutForm");
const { capture } = require("../helpers/screenshot");
const testCards = require("../data/testCards");

// Throwaway: fill + pay, then screenshot the result at intervals.
describe("explore pay result", () => {
  it("fills, pays, screenshots", async () => {
    await sample.generateCheckout();
    await fillCardForm(testCards.success);
    await driver.pause(3000);
    await capture("pay-after-3s");
    await driver.pause(5000);
    await capture("pay-after-8s");
    await driver.pause(6000);
    await capture("pay-after-14s");
  });
});
