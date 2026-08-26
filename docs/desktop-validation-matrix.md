# Desktop Validation Matrix (LAU-303) And Anti-Cheat Run (LAU-304)

Manual gates for the desktop hosts. They stay open until run on real hardware; CI covers the offline bridge round trip and the navigation policy only.

## What To Run

Each cell is one flow through one engine on one OS, against a real staging checkout link. Record the date, SDK version, engine version, OS build and the event sequence observed.

| Flow | Unity / Windows | Unity / macOS | Unreal / Windows | Unreal / macOS |
|------|-----------------|---------------|------------------|----------------|
| Card purchase (sandbox card) | | | | |
| Google Pay | | n/a (see notes) | | n/a (see notes) |
| PayPal redirect and return | | | | |
| 3DS2 challenge | blocked (see notes) | blocked | blocked | blocked |
| Saved-card preselect (repeat purchase, same user id) | | | | |
| Modal, `allowDismiss = false`, `window.close` from the page | | | | |
| `autoClose = false`: failure then success on one page | | | | |
| Exclusive fullscreen: card opens, trust header intact, game restored after | | n/a | | n/a |
| Play mode (editor): window presentation | | | | |
| Domain reload with the card open (Unity) | | | n/a | n/a |

Expected event sequence for a completed purchase: `navigation -> pageLoaded -> purchaseProcessing -> paymentSuccess` with the order payload, `isCurrentlyPresented` false afterwards. PayPal: the checkout navigates to paypal.com and back inside the card (full-page redirect), no `externalPayment` event.

## Generating Staging Links

Use the sample apps (Generate Checkout URL) or curl. The samples sign with `x-stash-hmac-signature` (`v1;<appId>;<unixMillis>;<base64 HMAC-SHA256 of "<unixMillis>." + body>`, key = base64-decoded ingress secret); keys created after 2026-08-15 must use HMAC, the `X-Stash-Api-Key` header is deprecated.

- Staging API: `https://test-api.stashstaging.com`, links on `checkout.stashstaging.com/pay/{uuid}`. `test-api.stash.gg` is the test environment of the production infrastructure, not staging.
- Omit `platform` in the body: the enum only knows `IOS` / `ANDROID`; desktop is correctly `UNDEFINED` (Adyen Web channel, all wallets enabled).
- `user.id` must not contain `:` (saved payment methods are keyed `{shopId}:{user.id}`). Reuse the same id for the saved-card row.
- Sandbox card: `4242 4242 4242 4242`, `03/30`, CVC `100`.

## Notes Per Flow

- Apple Pay is not available in the macOS card (WKWebView limitation, WebKit bug 282078); the hosted page hides the button. Card, Google Pay and PayPal are available. Apple Pay is available on Windows (WebView2 renders the button; completing it needs an iPhone for the QR handoff).
- 3DS2: staging cannot force a challenge (every test PAN is frictionless and the backend requests no challenge; the checkout team's e2e has it as a known gap). The row stays blocked until the backend can force one; the in-page iframe mechanics are covered by the validation-matrix test page (`Desktop/shared/test-pages/stash_validation_matrix.html`, Validation Matrix button in both samples).
- Windows runtime validation of the hosts themselves (attached card over a game window, trust header, Esc, prewarm) is part of this matrix: the Windows host was compiled and unit-tested in CI only.

## Anti-Cheat Run (LAU-304)

Goal: confirm a protected title can present the card. The host creates child windows of the game window, injects no code into the game, and loads `StashNativeDesktop.dll` plus the WebView2 runtime processes (`msedgewebview2.exe`) spawned out of process.

1. Build the Windows sample (`cmake ... --config Release`) and copy `StashNativeDesktopSample.exe` and `StashNativeDesktop.dll` next to the protected title's executable, or load the DLL from the title itself through the C ABI.
2. Launch under the anti-cheat (EAC, BattlEye, Vanguard as applicable) and open a staging checkout with the card attached to the game window.
3. Record: whether the DLL loads, whether the WebView2 processes are allowed, whether the card renders over the game and receives input, and any anti-cheat log entries. Repeat with exclusive fullscreen.
4. If the anti-cheat blocks child windows or the WebView2 processes, note the vendor and the rule hit; the fallback is `openBrowser`.

## Where To Record Results

Paste the filled table and the event logs into the Linear issues (LAU-303, LAU-304) and link the sample run logs (`-stash-auto` output or the sample's event log).
