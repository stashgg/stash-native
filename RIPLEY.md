---
standard-version: 1.6.0
---

# Ripley review rules

Review Stash Native for a concrete integrator-visible failure only: a checkout that crashes, presents incorrectly, sends the wrong callback, loses platform compatibility, or exposes a credential. This SDK is two native implementations of one embedded-checkout contract, so concentrate on lifecycle ordering, Android/iOS parity, and the host-facing bridge; stay silent when no specific broken checkout, callback, artifact, or secret can be named. The recurring risk shapes visible in the code are malformed inputs crossing the WebView or sample-import boundary, duplicate payment signals during teardown, and changes that update only one of the two platform contract paths.

## What NOT to flag

Do not comment on formatting, import ordering, naming, static-analysis findings, or ordinary Swift/Java style: Checkstyle, SwiftLint, and the iOS analyzer already own those. Do not demand blanket coverage, table-driven tests, or tests for WebView presentation glue; CI builds both libraries and samples and runs the focused Android/iOS test suites, while device/cloud QA owns WebView behavior. Do not restate Android Lint's informational output, build failures, or package-manager mechanics. Do not flag intentionally different serializers where the portable instance format is read by field name, nor the documented Android/iOS difference in bridge behavior when a message handler is absent.

## 1. external-shape-validation (A2)

When changing decoded checkout responses, persisted sample credentials, or imported instance documents, validate the decoded container and the fields used before indexing or iterating. Preserve the root-and-array shape guard in `iOS/Sample/StashNativeSample/StashNativeSample/ViewController+Instances.swift`'s `importInstancesJson`, the tolerant `optString`/`optBoolean` extraction in `Android/sample/src/main/java/com/stash/stashnative/sample/MainViewModel.java`'s `importInstancesJson`, and the generated-URL shape check in `iOS/Sample/StashNativeSample/StashNativeSample/ViewController+Actions.swift`.

**Failure:** A parseable but wrongly shaped response or import document throws during access or turns an invalid checkout URL into a host action.

## 2. checkout-result-once (A3)

Keep auto-closing checkout result handling idempotent across every page-message and deeplink route. Trace Android's `StashCheckoutJsInterface` into `StashCheckoutActivity` and iOS's `StashCheckoutSession` in `StashNativeInternal.m`. Preserve terminal state before host callbacks and the deliberate exception for `autoClose = false`, where a live page may retry from failure to success.

**Failure:** Duplicate payment signals during an auto-closing presentation deliver more than one terminal host callback or dismissal.

## 3. bridge-surface-parity (B1)

Treat `window.stash_sdk` as a paired Android/iOS protocol. Trace Android's `StashWebViewUtils.JS_SDK_SCRIPT` through `StashCheckoutJsInterface`, and iOS's `StashBridgeScript()` in `StashNativeViewUtils.m` through session handler registration and dispatch. Update both implementations when shared functions, argument coercion, results, or handler names change; preserve documented platform-specific missing-handler behavior.

**Failure:** Checkout JavaScript works on one native platform but silently drops or misroutes the same call on the other.

## 4. presentation-dimension-bounds (B1)

Normalize and copy card content dimensions, maximum height, and edge margin before presentation, including non-finite inputs. Preserve Android's `StashPresentationOptions` validation and iOS's `StashNormalizedConfig`. Zero maximum height means all available space; current window geometry takes precedence over requested dimensions.

**Failure:** Invalid host dimensions reach native layout, or resizing ignores the available window bounds.

## 5. ios-session-ownership (B3)

Keep the active session owned by its `StashNative` instance. `StashCheckoutSession` owns callbacks, timers, WebView, and presentation lifetime; controllers own layout. Declare cross-file interfaces in `StashNativePrivate.h` and keep file-local constants `static`. Do not use the singleton's state to decide behavior for another instance.

**Failure:** A session reads another instance's state or outlives its owner without teardown.

## 6. ios-source-membership (B3)

When adding or renaming an Objective-C library source, keep the distribution manifests synchronized: add the file to the `StashNative` Sources build phase in `iOS/StashNative/StashNative.xcodeproj/project.pbxproj` while retaining the source-tree layout consumed by `iOS/StashNative/Package.swift`. Verify both the Xcode project and SPM product include the implementation.

**Failure:** A source file appears in one iOS distribution path but is omitted from the shipped library in the other.

## 7. release-version-parity (B3)

Change the SDK version as one synchronized value: `SDK_VERSION` in `Android/stashnative/src/main/java/com/stash/stashnative/StashNative.java` and `+[StashNative sdkVersion]` in `iOS/StashNative/Sources/StashNative/StashNative.m` must report the same release string.

**Failure:** Integrators and wrappers identify equivalent Android and iOS release artifacts as different SDK versions.

## 8. safe-area-containment (B3)

Use current window bounds and insets when changing sizing, expansion, rotation, or keyboard handling. Android's `StashCheckoutSizing`, `StashPresentationController`, and `StashWindowCompat` resolve available space; iOS's geometry helpers and checkout controller resolve native sheet/content bounds. Keep interactive web content clear of system occlusions while allowing background paint through the bottom safe area.

**Failure:** A checkout sheet grows into a notch, status bar, navigation bar, or keyboard-derived inset on a supported device.

## 9. bridge-contract-consumers (B4)

For a changed checkout callback, external-browser handoff, or JavaScript bridge behavior, trace the full contract from injected script through the native handler to the host-facing API and its documented consumer. Keep `docs/stash-sdk-js.md`, `Android/stashnative/src/main/java/com/stash/stashnative/StashNative.java`, `iOS/StashNative/Sources/StashNative/include/StashNative.h`, and `.github/test/index.html` truthful about the behavior implemented by the two bridge paths.

**Failure:** A host or checkout page follows a stale callback or browser-handoff contract and receives the wrong lifecycle outcome.

## 10. instance-transfer-schema (B4)

Preserve the field-level portable-instance contract between the sample apps. `Android/sample/src/main/java/com/stash/stashnative/sample/MainViewModel.java` and `iOS/Sample/StashNativeSample/StashNativeSample/ViewController+Instances.swift` intentionally export and import the same named fields while regenerating local IDs and tolerating missing payloads; change producers and consumers together, not just one serializer.

**Failure:** An instance exported from one sample is rejected, loses its credential or payload, or is misclassified when imported by the other.

## 11. behavioral-fix-regression (B5)

Add a focused regression test when a material change alters deterministic SDK behavior such as URL acceptance, deeplink routing, theme propagation, sizing, bridge dispatch, or configuration defaults. Extend the relevant tests under `Android/stashnative/src/test/java/com/stash/stashnative/`, such as `UrlNormalizationTest`, `DeeplinkClassificationTest`, `ThemeParameterTest`, `CardGeometryTest`, or `StashNativePluginBridgeDispatchTest`, and the corresponding iOS tests in `iOS/StashNative/Tests/StashNativeTests/`; do not require a unit test where the behavior is necessarily device/WebView-only.

**Failure:** A later change restores a material checkout or callback bug because its testable behavior was never pinned by a regression test.

## 12. ingress-secret-exposure (C3)

Keep ingress secrets and derived HMAC signatures confined to the explicit sample signing flow in `Android/sample/src/main/java/com/stash/stashnative/sample/StashHmac.java` and `iOS/Sample/StashNativeSample/StashNativeSample/StashHmac.swift`. Do not move real signing credentials into the SDK, URLs, exceptions, or logs, and do not log request headers, bodies, or generated values that can carry a secret; the samples' bundled credential remains demonstrative only, as their HMAC helpers state.

**Failure:** An ingress secret or usable credential material reaches a client artifact or observable output and can be extracted or replayed.
