const path = require("path");
const fs = require("fs");

// Saves a PNG under artifacts/screenshots/<platform>/<device>/, named by the
// test step and current orientation. These files are the visual report; CI
// uploads the folder as a build artifact.
async function capture(name) {
  const caps = driver.capabilities || {};
  const device = String(caps.deviceName || caps["appium:deviceName"] || "device").replace(/\s+/g, "-");
  const platform = driver.isAndroid ? "android" : "ios";
  const orientation = String(await driver.getOrientation()).toLowerCase();

  const dir = path.join(__dirname, "../../artifacts/screenshots", platform, device);
  fs.mkdirSync(dir, { recursive: true });

  const file = path.join(dir, `${name}-${orientation}.png`);
  await driver.saveScreenshot(file);
  return file;
}

module.exports = { capture };
