const { localBaseConfig } = require("./wdio.local.shared");

// Local Android emulator run. Point ANDROID_APP at the built APK, e.g.
// Android/sample/build/outputs/apk/debug/sample-debug.apk. Boot an emulator
// (or plug in a device) before running.
exports.config = {
  ...localBaseConfig,
  capabilities: [
    {
      platformName: "android",
      "appium:automationName": "UiAutomator2",
      "appium:deviceName": process.env.ANDROID_DEVICE || "Android Emulator",
      "appium:app": process.env.ANDROID_APP,
      "appium:autoGrantPermissions": true,
      "appium:noReset": true,
    },
  ],
};
