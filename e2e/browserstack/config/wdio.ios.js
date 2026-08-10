const { baseConfig } = require("./wdio.shared");
const { iosDevices } = require("./devices");

// One session per iOS device in the matrix, all running the same specs.
exports.config = {
  ...baseConfig,
  capabilities: iosDevices.map((d) => ({
    platformName: "ios",
    "appium:automationName": "XCUITest",
    "bstack:options": {
      deviceName: d.device,
      osVersion: d.osVersion,
      projectName: "Stash Native",
      buildName: process.env.BROWSERSTACK_BUILD_NAME || "local-ios",
      sessionName: d.device,
      debug: true,
      networkLogs: true,
    },
  })),
};
