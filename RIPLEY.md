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

Keep auto-closing checkout result handling idempotent across every page-message and deeplink route. `Android/stashnative/src/main/java/com/stash/stashnative/StashPopupJsInterface.java` uses `paymentSuccessHandled`, and `iOS/StashNative/Sources/StashNative/StashNativeCardInternal.m` uses `_paymentSuccessHandled` in `handlePaymentSuccessSignalWithOrder:` and `handlePaymentFailureSignal`; preserve their before-callback latch and their deliberate exception for `autoClose = NO`, where a live page may retry from failure to success.

**Failure:** Duplicate payment signals during an auto-closing presentation deliver more than one terminal host callback or dismissal.

## 3. bridge-surface-parity (B1)

Treat `window.stash_sdk` as a paired Android/iOS protocol. A change to its shared function set, argument coercion, result semantics, or handler name must update the Android `JS_SDK_SCRIPT` and registered `StashCheckoutJsInterface`/`StashPopupJsInterface` paths in `Android/stashnative/src/main/java/com/stash/stashnative/`, plus `stashSDKScript`, message-handler registration, and dispatch in `iOS/StashNative/Sources/StashNative/StashNativeCard.m` and `iOS/StashNative/Sources/StashNative/StashNativeCardInternal.m`; preserve and document the intentionally platform-specific missing-handler behavior.

**Failure:** Checkout JavaScript works on one native platform but silently drops or misroutes the same call on the other.

## 4. presentation-ratio-bounds (B1)

Keep every public card and modal ratio on both platforms within the documented `[0.1, 1.0]` range, including non-finite input handling. Preserve the application of Android `StashNativeCardPlugin.clampRatio` before presentation and iOS `stashClampRatio` in `StashNativeCard`'s card and modal entry points; a new ratio field needs the same boundary defense on its owning platform.

**Failure:** An out-of-range or non-finite host configuration creates invalid geometry, a native layout crash, or a presentation that differs from its public bounds.

## 5. ios-shared-state-home (B3)

Keep iOS state shared across implementation files defined once in `iOS/StashNative/Sources/StashNative/StashNativeCard.m` and declared through `iOS/StashNative/Sources/StashNative/StashNativeCardPrivate.h`; use file-local `static` storage for state a single implementation owns. Do not add a second definition or silently move an existing shared flag, sizing value, or message-handler constant into another `.m` file.

**Failure:** Two iOS implementation files observe divergent presentation state or constants during the same checkout.

## 6. ios-source-membership (B3)

When adding or renaming an Objective-C library source, keep the distribution manifests synchronized: add the file to the `StashNative` Sources build phase in `iOS/StashNative/StashNative.xcodeproj/project.pbxproj` while retaining the source-tree layout consumed by `iOS/StashNative/Package.swift`. Verify both the Xcode project and SPM product include the implementation.

**Failure:** A source file appears in one iOS distribution path but is omitted from the shipped library in the other.

## 7. release-version-parity (B3)

Change the SDK version as one synchronized value: `SDK_VERSION` in `Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java` and `+[StashNativeCard sdkVersion]` in `iOS/StashNative/Sources/StashNative/StashNativeCard.m` must report the same release string.

**Failure:** Integrators and wrappers identify equivalent Android and iOS release artifacts as different SDK versions.

## 8. safe-area-containment (B3)

Retain the physical safe-area ceiling whenever changing checkout sizing, expansion, rotation, or inset handling. Android `StashCheckoutSizing.phoneSheetMaxHeightPx` and `StashWindowCompat` reserve system-bar space, while iOS `StashNativeCard` and `StashNativeCardInternal` capture `_cardSafeAreaTop` and clamp card frames; do not replace either platform's bound with raw display dimensions.

**Failure:** A checkout sheet grows into a notch, status bar, navigation bar, or keyboard-derived inset on a supported device.

## 9. bridge-contract-consumers (B4)

For a changed checkout callback, external-browser handoff, or JavaScript bridge behavior, trace the full contract from injected script through the native handler to the host-facing API and its documented consumer. Keep `docs/stash-sdk-js.md`, `Android/stashnative/src/main/java/com/stash/stashnative/StashNativeCard.java`, `iOS/StashNative/Sources/StashNative/include/StashNativeCard.h`, and `.github/test/index.html` truthful about the behavior implemented by the two bridge paths.

**Failure:** A host or checkout page follows a stale callback or browser-handoff contract and receives the wrong lifecycle outcome.

## 10. instance-transfer-schema (B4)

Preserve the field-level portable-instance contract between the sample apps. `Android/sample/src/main/java/com/stash/stashnative/sample/MainViewModel.java` and `iOS/Sample/StashNativeSample/StashNativeSample/ViewController+Instances.swift` intentionally export and import the same named fields while regenerating local IDs and tolerating missing payloads; change producers and consumers together, not just one serializer.

**Failure:** An instance exported from one sample is rejected, loses its credential or payload, or is misclassified when imported by the other.

## 11. behavioral-fix-regression (B5)

Add a focused regression test when a material change alters deterministic SDK behavior such as URL acceptance, deeplink routing, theme propagation, sizing, bridge dispatch, or configuration defaults. Extend the relevant tests under `Android/stashnative/src/test/java/com/stash/stashnative/`, such as `UrlNormalizationTest`, `DeeplinkClassificationTest`, `ThemeParameterTest`, `CardGeometryTest`, or `StashNativeCardPluginBridgeDispatchTest`, and the corresponding iOS tests in `iOS/StashNative/Tests/StashNativeTests/`; do not require a unit test where the behavior is necessarily device/WebView-only.

**Failure:** A later change restores a material checkout or callback bug because its testable behavior was never pinned by a regression test.

## 12. ingress-secret-exposure (C3)

Keep ingress secrets and derived HMAC signatures confined to the explicit sample signing flow in `Android/sample/src/main/java/com/stash/stashnative/sample/StashHmac.java` and `iOS/Sample/StashNativeSample/StashNativeSample/StashHmac.swift`. Do not move real signing credentials into the SDK, URLs, exceptions, or logs, and do not log request headers, bodies, or generated values that can carry a secret; the samples' bundled credential remains demonstrative only, as their HMAC helpers state.

**Failure:** An ingress secret or usable credential material reaches a client artifact or observable output and can be extracted or replayed.
