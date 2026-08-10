const { baseConfig } = require("./wdio.shared");
const { androidDevices } = require("./devices");

// One session per Android device in the matrix, all running the same specs.
exports.config = {
  ...baseConfig,
  capabilities: androidDevices.map((d) => ({
    platformName: "android",
    "appium:automationName": "UiAutomator2",
    // Grant runtime permissions up front so no system dialog blocks the run.
    "appium:autoGrantPermissions": true,
    "bstack:options": {
      deviceName: d.device,
      osVersion: d.osVersion,
      projectName: "Stash Native",
      buildName: process.env.BROWSERSTACK_BUILD_NAME || "local-android",
      sessionName: d.device,
      // Captures logs/network and keeps the session inspectable.
      debug: true,
      networkLogs: true,
    },
  })),
};
