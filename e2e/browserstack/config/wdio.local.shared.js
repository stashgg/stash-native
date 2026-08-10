const path = require("path");

// Shared config for running against a LOCAL Appium server plus an iOS simulator
// or Android emulator. No BrowserStack. The @wdio/appium-service starts and
// stops the Appium server automatically.
exports.localBaseConfig = {
  hostname: "127.0.0.1",
  port: 4723,
  path: "/",

  services: ["appium"],

  framework: "mocha",
  mochaOpts: { ui: "bdd", timeout: 5 * 60 * 1000 },
  reporters: ["spec"],

  specs: [path.join(__dirname, "../test/specs/**/*.e2e.js")],

  logLevel: "info",
  waitforTimeout: 30000,
  connectionRetryTimeout: 120000,
  connectionRetryCount: 1,
};
