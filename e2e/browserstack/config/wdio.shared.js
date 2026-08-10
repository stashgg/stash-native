const path = require("path");

// Shared WebdriverIO config for BrowserStack App Automate. The platform files
// (wdio.android.js / wdio.ios.js) add capabilities and spread this in.
exports.baseConfig = {
  // Credentials come from the environment, never committed. In CI these are the
  // BROWSERSTACK_USERNAME / BROWSERSTACK_ACCESS_KEY GitHub secrets.
  user: process.env.BROWSERSTACK_USERNAME,
  key: process.env.BROWSERSTACK_ACCESS_KEY,

  // Route sessions through BrowserStack. The service uploads/attaches the app
  // given by BROWSERSTACK_APP_ID (a bs://... id from app-automate/upload).
  hostname: "hub.browserstack.com",
  services: [["browserstack", { app: process.env.BROWSERSTACK_APP_ID }]],

  framework: "mocha",
  mochaOpts: { ui: "bdd", timeout: 5 * 60 * 1000 },
  reporters: ["spec"],

  specs: [path.join(__dirname, "../test/specs/**/*.e2e.js")],

  logLevel: "info",
  waitforTimeout: 30000,
  connectionRetryTimeout: 120000,
  connectionRetryCount: 1,
};
