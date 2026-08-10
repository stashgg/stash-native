# BrowserStack App Automate tests

Appium (WebdriverIO) tests that run the Stash Native sample apps on real
BrowserStack devices. They capture how the checkout card renders across devices,
orientations, sizes, and with the keyboard up, and they run the purchase flow for
both the card and the browser checkout.

## What the tests cover

- `render.card.e2e.js` - screenshots of the card collapsed, expanded, in
  landscape, and with the keyboard shown. Visual only.
- `sizing.card.e2e.js` - card at a small and a large height; phone and tablet
  come from the device matrix.
- `purchase.card.e2e.js` - enter a test card, pay, assert the native
  "Payment Success" callback chip.
- `purchase.browser.e2e.js` - same through the browser checkout.

Screenshots land in `artifacts/screenshots/<platform>/<device>/` and are uploaded
as a build artifact in CI.

## Prerequisites

The sample apps must be built with webview inspection on. Both sample apps call
`StashNativeCard.setInspectableWebViewsEnabled(true)` on launch, so a normal
sample build is enough. Without it the purchase specs cannot enter the checkout
webview.

## Running locally

```
cd e2e/browserstack
npm install

export BROWSERSTACK_USERNAME=...      # never commit these
export BROWSERSTACK_ACCESS_KEY=...
export BROWSERSTACK_APP_ID=bs://...   # from app-automate/upload
export BROWSERSTACK_BUILD_NAME=local

npm run test:android
npm run test:ios
```

Upload an app to get `BROWSERSTACK_APP_ID`:

```
curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/upload" \
  -F "file=@/path/to/app.apk"
# -> {"app_url":"bs://<hash>"}
```

Android automation needs a signed APK; use the debug build
(`:sample:assembleDebug`). iOS can use the unsigned sample `.ipa`; BrowserStack
resigns it for App Automate.

## Running in CI

The `browserstack-e2e` workflow is manual (`workflow_dispatch`). Pick the
platform, and it builds the sample app, uploads it, runs the specs, and uploads
the screenshots. It reads `BROWSERSTACK_USERNAME` / `BROWSERSTACK_ACCESS_KEY`
from GitHub Actions secrets.

## Device matrix

Edit `config/devices.js` to change devices. One phone and one tablet per platform
to start.

## Known rough edges

- The checkout form selectors in `helpers/checkoutForm.js` are best-effort. The
  checkout page markup is not ours; confirm selectors against a live session
  (Safari Web Inspector / chrome://inspect) and tighten as needed. Card fields
  may sit in a cross-origin iframe that needs a frame switch.
- Android browser checkout uses Chrome Custom Tabs (a separate app), so returning
  to read the callback chip may need a context switch.
- Slider and card-dismiss gestures are coordinate based and may need adjusting on
  new form factors.
