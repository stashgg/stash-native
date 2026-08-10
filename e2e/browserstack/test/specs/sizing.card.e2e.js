const sample = require("../pageobjects/sample.page");
const { capture } = require("../helpers/screenshot");

// Opens the card at a small and a large phone height to check the SDK clamps and
// lays out sizes correctly. Because it runs on both phones and tablets in the
// matrix, the same spec also shows the tablet-specific default ratios.
describe("Checkout card sizing", () => {
  it("captures a small and a large card", async () => {
    await driver.setOrientation("PORTRAIT");

    // Smallest height.
    await sample.tab("settings").click();
    await sample.openCardOptions();
    await sample.setFirstSliderRatio(0.1);
    await sample.back();
    await sample.tab("test").click();
    await sample.generateCheckout();
    await capture("card-size-small");
    await sample.dismissCard();

    // Largest height.
    await sample.tab("settings").click();
    await sample.openCardOptions();
    await sample.setFirstSliderRatio(1.0);
    await sample.back();
    await sample.tab("test").click();
    await sample.generateCheckout();
    await capture("card-size-large");
    await sample.dismissCard();
  });
});
