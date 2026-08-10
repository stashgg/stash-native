const { localBaseConfig } = require("./wdio.local.shared");

// Local iOS simulator run. Point IOS_APP at the built .app for the simulator,
// e.g. .../Build/Products/Debug-iphonesimulator/StashNativeSample.app.
// Override the device with IOS_DEVICE / IOS_VERSION if needed.
exports.config = {
  ...localBaseConfig,
  capabilities: [
    {
      platformName: "ios",
      "appium:automationName": "XCUITest",
      "appium:deviceName": process.env.IOS_DEVICE || "iPhone 17",
      "appium:platformVersion": process.env.IOS_VERSION || undefined,
      "appium:app": process.env.IOS_APP,
      // Reuse an already-booted simulator instead of shutting it down after.
      "appium:noReset": true,
    },
  ],
};
