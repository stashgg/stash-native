# Scope and shared contracts

## Select and record source snapshots

Default scope is four SDKs, four samples, the desktop shared contract, and package support files. A branch without `Desktop/` is not evidence that desktop is out of scope.

1. Read `git status --short`, the current commit, and `git ls-files`; include relevant untracked first-party files and uncommitted changes. Record a source label such as `working-tree` and its base SHA. Do not silently audit HEAD instead of modified files.
2. If the user selected a ref, use that ref for its requested components. Otherwise use desktop files in the current tree when present. If absent, prefer an available local `desktop/integration`, then `origin/desktop/integration`.
3. Discover alternatives with `git for-each-ref` and inspect their trees and history. The numbered `desktop/01-*` through `desktop/07-*` refs are development stages; the combined integration branch can contain squashed versions and later fixes. Do not require merge ancestry as proof of inclusion or audit every historical copy as a separate SDK.
4. Resolve selected refs to full SHAs. Read files with `git show <sha>:<path>` or extract a snapshot below the audit artifact directory. Do not switch the user's checkout or merge branches. If refs are missing or ambiguous, continue the independent review and request the missing target information; mark unavailable platforms explicitly.
5. Read each snapshot's manifests, bridge spec, platform docs, changelog, tests, and workflows. Keep mobile-current and desktop-branch support files distinguishable. Record whether refs are local cached refs or were refreshed; do not imply freshness that was not checked.

For a mixed source set, label findings as `source-label:path:line` and include the full SHA in the report's source map. It is a composite assessment, not the validation of one releasable commit. Version differences and APIs intentionally absent on one platform are not automatically defects. If the user later audits a unified release ref, use it for all components.

## Component inventory

Paths are relative to the source snapshot that contains them. Discover new or renamed files instead of treating this map as an exclusion list.

| Component ID | Starting points |
|---|---|
| `ios` | `iOS/StashNative/Sources`, public/private headers, Xcode project, SPM package, XCTest. |
| `android` | `Android/stashnative/src`, facade/plugin/activity, JS interfaces, support helpers, manifest, consumer rules, JUnit/Robolectric. |
| `macos` | `Desktop/macOS/Sources`, facade/core/presenter/WebKit delegates/exports, `Desktop/Package.swift`, XCTest, bundle script. |
| `windows` | `Desktop/Windows/include`, `src`, CMake, DLL exports, Win32/WebView2 host, tests, build script. |
| `desktop-shared` | `Desktop/include`, `Desktop/shared`: C ABI, versions, session, JSON/config/URL/theme, injected script, shared tests/pages. |
| `sample-ios` | `iOS/Sample`, Swift controllers, credentials, signing, resources, project and app configuration. |
| `sample-android` | `Android/sample`, Java activities/view models, settings, credentials, signing, resources and manifest. |
| `sample-macos` | `Desktop/macOS/Sample`: window, settings, event log, link generator, signer, proof runner. |
| `sample-windows` | `Desktop/Windows/Sample`: Win32 UI, link generator, signer, proof runner, sample CMake and packaged pages. |
| `package` | Root and platform docs, compatibility/changelog, agent guidance, `.github` workflows/test pages, distribution and lint configuration. |

Inventory all tracked first-party code, headers, tests, resource definitions, build/release files, and docs, plus relevant working changes. Group binary artwork by use and inspect meaningful metadata; do not claim source review of binaries. Exclude generated builds, caches, downloaded WebView2 SDKs, vendored libraries, and private credentials with reasons. Check first-party configuration that controls excluded dependencies.

Maintain a file inventory and a coverage matrix. Each component gets rows for applicable areas: contracts, lifecycle/state, ownership/threading, parsing/numerics, security/privacy, UI/accessibility/performance, compatibility/packaging, R1-R6 quality, T1-T6 tests, CI/docs, and runtime verification. Use `NOT-REVIEWED`, `REVIEWED`, `FINDINGS`, `BLOCKED`, or `N/A` with evidence and reasons. A missing host runner is `BLOCKED` for execution, not `N/A` for its code review.

## Dependency and ownership map

Draw a small Mermaid graph from observed imports, calls, callbacks, extern state, message dispatch, and build dependencies. Separate compile dependencies from asynchronous events. Group by SDK/shared contract/sample rather than making every file a node.

Trace the mobile facade/plugin/activity or singleton/internal units, and desktop facade/C ABI/core/shared `Session`/presenter/webview. Show samples consuming public APIs. Cite source locations for important edges. An Objective-C private header or a callback flowing back toward its caller does not by itself prove a dependency cycle.

Mark unreviewed nodes explicitly; absence of a finding is only meaningful on reviewed code. State which owners create, retain, close, reset, and release a session and its native surface.

## API and bridge contract matrix

Enumerate every public native entrypoint, delegate/listener event, desktop C export, injected JS function, and native bridge handler. Compare implementation, API comments, docs, tests, and sample use. Keep intentional platform differences in the matrix with their source; do not invent a universal surface.

For each operation record inputs/defaults, caller thread, state preconditions, side effects, result/callback, payload shape, callback thread, ordering, failure behavior, and lifetime. Include configuration setters and state queries, not only open/dismiss. Check the three script bodies: Android, iOS, and the shared desktop script with its two transport preludes.

Trace these scenarios end to end in every applicable implementation:

| Scenario | Evidence to follow |
|---|---|
| Open card/modal/browser | Public API -> validation -> thread dispatch -> host selection -> native surface -> navigation -> bridge injection. |
| First load and redirects | Progress/spinner, pageLoaded once, timing units, timeout/retry, transport/TLS/HTTP failure, renderer death, stale navigation identifiers. |
| Payment and processing | Processing lock/unlock, success/failure payload, autoClose on/off, failure then success, duplicate JS/deeplink events, event order and state visible inside callbacks. |
| Dismiss and reopen | Button/back/backdrop/Esc/window.close, allowDismiss, programmatic dismissal, host close, reset, shutdown, double open, callback-triggered reopen, callbacks from the previous session. |
| External handoff | openExternalBrowser versus openLink/new window, theme and URL normalization, external launch failure, return/cancel where supported, checkout ownership after handoff. |
| Lifecycle interruption | Mobile recreation/backgrounding, desktop host-window destruction/fullscreen changes, prewarm/open/shutdown overlap, process/render failure, queued callbacks after teardown. |

Cover empty/null/wrong-type inputs, NaN/infinities, numeric extremes, Unicode and embedded NUL, percent/base64/JSON encoding, locale, URL length, unsupported schemes, query/fragment handling, and exact callback payloads. Follow guards through their callers before claiming an unchecked input.

Review main-frame and subframe trust separately: script injection, bridge access, redirects, TLS failures, new windows, downloads, local files/content, custom schemes, and messages arriving from an unexpected origin/session. A broad allowlist is not automatically wrong for payment redirects; establish the intended trust boundary and consequence.

## Completion

Resolve coverage at file and area level, review the interactions exposed by findings, and perform a final deduplication/counterexample pass. Preserve pending candidates and verification gaps when a full assessment cannot finish. File-review completion, executed-test completeness, and product readiness are separate claims.
