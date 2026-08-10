// Page object for the Stash Native sample app.
//
// Both apps expose the same accessibility ids for the checkout controls:
//   card-url-field / card-open-button, browser-open-button, modal-open-button.
// Android sets these as contentDescription, iOS as accessibilityIdentifier, so
// the same "~id" selector works on both. Where the platforms differ (tabs,
// sliders, back, row text) we branch on driver.isAndroid.

const ANDROID_PKG = "com.stash.stashnative.sample";

class SamplePage {
  get isAndroid() {
    return driver.isAndroid;
  }

  // Inline "Open" button next to a URL row. kind: card | browser | modal.
  openButton(kind) {
    return $(`~${kind}-open-button`);
  }

  // Bottom tab bar entry. name: test | settings | instances.
  tab(name) {
    if (this.isAndroid) {
      const ids = { test: "tab_test", settings: "tab_settings", instances: "tab_api" };
      return $(`android=new UiSelector().resourceId("${ANDROID_PKG}:id/${ids[name]}")`);
    }
    const labels = { test: "Test", settings: "Settings", instances: "Instances" };
    return $(`~${labels[name]}`);
  }

  // Finds a row/element by its visible text, platform-agnostic.
  byText(text) {
    return this.isAndroid
      ? $(`android=new UiSelector().textContains("${text}")`)
      : $(`-ios predicate string:label CONTAINS "${text}"`);
  }

  async openCard() {
    await this.openButton("card").click();
    await this.waitForCard();
  }

  async openBrowser() {
    await this.openButton("browser").click();
    await this.waitForCard();
  }

  // Both platforms render two rows labelled exactly "Generate Checkout": the
  // card section first, the browser section second. Pick by index so we hit the
  // right one. Returns the nth (0-based) matching row element.
  generateRow(index) {
    return this.isAndroid
      ? $(`android=new UiSelector().text("Generate Checkout").instance(${index})`)
      : $$(`-ios predicate string:label == "Generate Checkout"`)[index];
  }

  // Signs a payload and fetches a real checkout URL, then opens the card. This
  // is the actual checkout, unlike the plain Open button which loads the static
  // test URL.
  async generateCheckout() {
    await (await this.generateRow(0)).click();
    await this.waitForCard();
  }

  // Same as generateCheckout but for the browser (Custom Tabs / Safari) flow,
  // which is the second "Generate Checkout" row.
  async generateCheckoutForBrowser() {
    await (await this.generateRow(1)).click();
    await this.waitForCard();
  }

  // The checkout webview takes a moment to attach after the card opens.
  async waitForCard() {
    await driver.pause(4000);
  }

  // Opens Settings > Card options where the size sliders live.
  async openCardOptions() {
    await this.byText("Card options").click();
    await driver.pause(1000);
  }

  // Sets the first slider on the current screen (phone card height) to a 0..1
  // fraction. iOS sliders take the value directly; Android SeekBars do not, so
  // we tap along the bar at the target fraction.
  async setFirstSliderRatio(ratio) {
    if (this.isAndroid) {
      const bar = await $('android=new UiSelector().className("android.widget.SeekBar").instance(0)');
      const loc = await bar.getLocation();
      const size = await bar.getSize();
      const x = Math.round(loc.x + size.width * ratio);
      const y = Math.round(loc.y + size.height / 2);
      await driver.action("pointer").move({ x, y }).down().up().perform();
    } else {
      const slider = await $("-ios class chain:**/XCUIElementTypeSlider[1]");
      await slider.setValue(String(ratio));
    }
  }

  // Goes back one screen (from an options screen to the list).
  async back() {
    if (this.isAndroid) {
      await driver.back();
    } else {
      await $("-ios class chain:**/XCUIElementTypeNavigationBar/XCUIElementTypeButton[1]").click();
    }
    await driver.pause(500);
  }

  // Dismisses an open checkout card.
  async dismissCard() {
    if (this.isAndroid) {
      await driver.back();
    } else {
      const { width, height } = await driver.getWindowSize();
      await driver
        .action("pointer")
        .move({ x: Math.round(width / 2), y: Math.round(height * 0.25) })
        .down()
        .move({ x: Math.round(width / 2), y: Math.round(height * 0.95), duration: 500 })
        .up()
        .perform();
    }
    await driver.pause(1000);
  }

  // Waits for the native "Payment Success" callback chip the sample shows.
  async waitForPaymentSuccess(timeout = 60000) {
    const chip = this.byText("Payment Success");
    await chip.waitForDisplayed({ timeout });
    return chip;
  }
}

module.exports = new SamplePage();
