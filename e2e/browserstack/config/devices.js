// Device matrix. One phone and one tablet per platform to start.
// Add rows to widen coverage; each row becomes a separate BrowserStack session.

exports.androidDevices = [
  { device: "Google Pixel 8", osVersion: "14.0" },       // phone
  { device: "Samsung Galaxy Tab S9", osVersion: "13.0" }, // tablet
];

exports.iosDevices = [
  { device: "iPhone 15", osVersion: "17" },           // phone
  { device: "iPad Pro 12.9 2022", osVersion: "16" },  // tablet
];
