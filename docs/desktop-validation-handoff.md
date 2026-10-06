# Desktop payments validation: handoff for the Unity and Unreal columns

Written from the Windows native-host validation run (LAU-303, 2026-09-09) for whoever picks up the Unity and Unreal columns (Windows and macOS) of `desktop-validation-matrix.md` and the LAU-304 anti-cheat run. It exists so the discovery cost is not paid twice. Read it before starting.

## 1. Status

- Windows column through the native host and the Win32 sample: complete. Build clean, unit tests pass, both offline proofs pass, staging link generation from the sample passes, and matrix rows 1, 2, 4, 6, 7 and 8 pass. Row 3 (Apple Pay) was not run (no device). Row 5 (3DS2) is blocked by design (staging cannot force a challenge).
- A real Windows host bug was found and fixed (section 4). It does not affect Unity or Unreal over a plain game window, but read it.
- Everything was staging only. Nothing touched production.

Remaining columns: Unity/Windows, Unity/macOS, Unreal/Windows, Unreal/macOS, plus LAU-304 if a protected title is provided.

## 2. What you need that the Windows run did not have

- The Unity and Unreal test projects built with the 2.4.0 desktop package (this repository is the native host, not the engine integrations). The anti-cheat rule is explicit: the host must be loaded from inside the protected title's own process; the standalone sample next to a title does not count.
- An Apple Pay-enabled iPhone or iPad for the Windows Apple Pay row (WebView2 shows a QR code the device scans). Apple Pay is not available on macOS (WKWebView limitation, WebKit bug 282078; the hosted page hides the button).
- A protected-title build under the anti-cheat (EAC, BattlEye, Vanguard) for LAU-304.

## 3. A Windows environment that works

- Windows 11 build 26200, x64, WebView2 Evergreen runtime 152.0.4191.66. The sample ends in `networkError` if the runtime is missing.
- Branch `desktop/integration` at or after `485e54c` (raw ingress secret signer fix). The z-order fix in section 4 is PR #20 (`b80c7bb` on `windows-validation/sample-input`) and is not on `desktop/integration` until that PR merges: if the host you validate against has child windows, build from `b80c7bb`, or from the merge commit that contains #20, and record which ref you used.
- Visual Studio 2026 Community with Desktop C++ (MSVC 19.51), CMake 4.4.1.
- Build gotchas, both documented in `windows.md` and handled by `Desktop/Windows/build_plugin.ps1`:
  1. With Ninja on PATH, plain `cmake -A x64` selects Ninja and fails. Pass the Visual Studio generator explicitly (`-G "Visual Studio 18 2026"`, or the installed version; VS 2022 needs CMake 3.21+, VS 2026 needs 4.2+).
  2. A CMake without a CA bundle (WinLibs) fails TLS verification on the WebView2 NuGet fetch. Keep verification on and pass a bundle (`-DCMAKE_TLS_VERIFY=ON -DCMAKE_TLS_CAINFO=<path to ca-bundle.crt>`). Never disable verification: this fetch is a binary that links into the payments host.
- Outputs land in `Desktop/Windows/build/Sample/Release/` (sample exe, `StashNativeDesktop.dll`, `test-pages/`).
- Offline proofs (headless, no secret): `StashNativeDesktopSample.exe -stash-auto local` and `-stash-auto secure`. `-stash-auto remote -stash-url <link>` drives a real staging link (loads, then self-dismisses after 25 s), useful as a host-loads-checkout smoke without completing a purchase.

## 4. The host bug (z-order)

- Symptom: in a host window that has its own child windows, the attached card was created below those siblings in z-order, so they intercepted mouse input and the card was inert.
- Why Unity and Unreal were unaffected: a game render window has no sibling child controls in its client area, so a freshly created card was already on top. The bug surfaced only in the control-heavy Win32 sample and would in any embedding host with child windows.
- Fix: raise the card and backdrop to the top of the sibling z-order on present and re-assert on layout (`Desktop/Windows/src/StashNativeCardWindow.cpp`, PR #20).
- Implication: if the engine build hosts the card over a window that owns child windows (some editor or overlay setups), validate against a host that includes the fix.
- Residual, sample only, unfixed: a click in the dimmed margin still reaches a control beneath the layered backdrop, and backdrop-click-to-dismiss does not fire in the sample (Esc and the close button work). Harmless over a real game; macOS avoids it with a hit-testing NSView backdrop.

## 5. Staging: shop, signing, saved-card gotcha

- Shop and App ID (the shop id): `33aa5976-62a5-40a3-892e-779d494d2148` (`desktop-ci-test`, staging).
- API `https://test-api.stashstaging.com`, links on `checkout.stashstaging.com/pay/<uuid>`. Not `test-api.stash.gg` (the production infrastructure's test tier).
- Ingress secret: through the `STASH_INGRESS_SECRET` environment variable or typed into the sample's session-only field. Never paste it into chat or logs. Get a freshly rotated key from the operator.
- Sandbox card `4242 4242 4242 4242`, expiry `03/30`, CVC `100`.
- HMAC signing (verified against staging): key = the ingress secret's raw UTF-8 bytes, not base64-decoded (Studio keys use the URL-safe alphabet). Message = `"<unixMillis>." + body`. Header `x-stash-hmac-signature: v1;<shopId>;<unixMillis>;<standard base64 HMAC-SHA256>`. Sign the exact bytes you POST. Omit `platform` (desktop is UNDEFINED). Reference: `Desktop/Windows/Sample/src/StashHmac.cpp`. Endpoint `POST /sdk/server/checkout_links/generate_quick_pay_url`.
- Saved-card gotcha: saved payment methods are keyed `{shopId}:{user.id}`. A returning `user.id` opens the checkout with its saved card preselected (row 6, expected). For a fresh card-entry run (row 1) mint with a new `user.id` (a UUID, no `:`), then reuse that id for the saved-card row.

## 6. Per-flow notes

- Card purchase: events `navigation -> pageLoaded -> purchaseProcessing -> paymentSuccess`, `isCurrentlyPresented` false after. Use a fresh `user.id` so the card form appears.
- Google Pay and PayPal: separate buttons; a preselected saved card does not block them. PayPal does a full-page redirect to paypal.com and back inside the card; there is no `externalPayment` event; confirm the return lands.
- Apple Pay: Windows only (WebView2 QR handoff). Not available on macOS.
- 3DS2: blocked on staging (frictionless test PANs); record "blocked".
- `allowDismiss = false` plus `window.close`: not user-dismissable, must close when the page asks.
- `autoClose = false`: a failed then successful attempt on one page; the card stays open between them.
- Exclusive fullscreen (Windows): card renders and takes input, game restored afterwards. Not exercisable from the Win32 sample (no fullscreen toggle); an engine build has one.

## 7. LAU-304 anti-cheat (only with a protected title)

Follow the "Anti-Cheat Run" section of `desktop-validation-matrix.md`. `StashNativeDesktop.dll` must be loaded by the game process itself (a Unity or Unreal build with the 2.4.0 package, or the title binding the C ABI). Record whether the DLL loads, whether the `msedgewebview2.exe` processes are allowed, whether the card renders over the game and takes input, and any anti-cheat log entries; repeat in exclusive fullscreen. If blocked, note the vendor and the rule; the fallback is `openBrowser`.

## 8. Ground rules

Staging only. Code changes go on a `windows-validation/<topic>` branch as a diff for the reviewer; get an explicit OK before pushing anything. Never log or chat the ingress secret.

## 9. Time budget from the Windows run

Environment, clone and build including the two gotchas: about 20 minutes. Offline proofs and link generation: about 5 minutes. The z-order bug (diagnose, fix, rebuilds): about 35 minutes, which should not recur. Interactive payment flows: about 15 minutes per engine and OS once a build is in hand. Budget more for first-time Unity and Unreal project setup and for anti-cheat.
