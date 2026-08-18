---
description: Iterative full-codebase audit that fills a ledger of confirmed problems, then fixes them from the ledger
---

# Stash Native SDK -- Comprehensive Audit

Argument (optional): `$ARGUMENTS`
- `audit` -- run investigation iterations only, stop after ledger convergence.
- `fix` -- skip investigation, implement fixes from the existing ledger.
- `status` -- print a summary of the current ledger and exit.
- (empty) -- full flow: audit until convergence, then gate, then fix.

## The ledger

Single source of truth: `AUDIT_LEDGER.md` at the repo root. Do NOT commit it unless the Developer asks. If it already exists, load it and continue from it -- never wipe prior entries.

Every finding is one entry:

```
### A-NNN [STATUS] [P0-P3] category -- one-line title
- Platform: ios | android | both | docs | sample-ios | sample-android | ci
- Location: path/to/file.ext:line (every claim must have file:line evidence)
- Description: what is wrong, concretely
- Evidence: the code/behavior that proves it (short quote or trace)
- Proposed fix: concrete change, respecting project constraints
- Verification: how to prove the fix works (build/test/manual step)
```

Statuses: `OPEN` (reported by an agent, not yet verified) -> `CONFIRMED` (main agent re-read the code and agrees) or `FALSE-POSITIVE` (keep the entry with a one-line reason so later iterations do not re-report it) -> `FIXED` / `WONTFIX` / `DEFERRED`.

Severity: `P0` crash/data-loss/security in the SDK, `P1` real bug integrators can hit, `P2` leak/perf/robustness debt, `P3` polish (dead code, docs drift, naming).

Two lenses, one ledger. Findings are either **correctness** (bugs/robustness/security, areas A-K) or **quality** (readability/cleanliness/style, areas L-P). Tag each entry's category accordingly (e.g. `quality/naming`, `quality/structure`). Quality findings are capped at `P2` -- use `P2` only for genuine maintainability debt or a public-facing style/doc gap, `P3` for local nits (formatting, a single unclear name, a stale comment). Never inflate a style nit; a subjective preference with no guideline behind it is not a finding.

## Phase 1 -- iterative investigation

Repeat iterations until convergence. Each iteration:

1. Launch a batch of 4-6 parallel read-only Explore subagents, each assigned audit areas from the checklist below. Give each agent: its areas, the relevant directories, the current ledger (so it does not re-report known entries, including FALSE-POSITIVEs), and the requirement that every finding carries file:line evidence.
2. Merge results into the ledger as `OPEN`. Dedupe against existing entries.
3. Verify: for each new OPEN entry, read the cited code yourself. Mark `CONFIRMED` or `FALSE-POSITIVE`. Do not trust agent claims without reading the code.
4. Convergence check: if a full iteration produced zero new CONFIRMED entries, the audit is done. Otherwise, next iteration -- rotate/deepen areas (e.g. follow up on hotspots the previous batch flagged).

Scope for agents: `iOS/StashNative/`, `Android/stashnative/`, `iOS/Sample/`, `Android/sample/`, `docs/`, `README*`, `.github/` (workflows + test card), consumer ProGuard rules, gradle/xcodeproj/SPM manifests.

Run BOTH lenses every iteration. Alongside the correctness agents (areas A-K), assign at least one dedicated **code-quality agent** (areas L-P) -- more if the surface is large; split by platform. Quality agents judge the code against the canonical standards, not personal taste, and must name the specific rule each finding violates:
- Android / Java: [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html) + AOSP code conventions + Android Lint expectations (resource naming, no unused resources).
- iOS / Objective-C: Apple *Coding Guidelines for Cocoa* (method naming, prefixes, `instancetype`) + complete nullability annotations (`NS_ASSUME_NONNULL_BEGIN`, `nullable`/`nonnull`) and consistent property attributes on public headers.
- iOS / Swift (samples): *Swift API Design Guidelines* (clarity at the call site, no needless words) + `swiftlint` config in the repo.
The bar is "readable, clean, and idiomatic to the platform" -- but every quality fix must be behavior-preserving and must not touch the public API (see Phase 3). Respect the existing project rules that override the style guides: terse human-style comments (not verbose docs on unchanged code), no emoji, Obj-C ivar underscore prefix, the deliberately preserved `stashNativement*` handler typo.

## Audit checklist (assign areas across agents)

Filtered to what this codebase actually is: an offline mobile payments-checkout SDK (Obj-C + Java, webviews, JS bridge, game-engine wrappers). No databases, no server code, no distributed systems.

**A. Dead & unreachable code**
- Unused methods, fields, constants, classes, resources, strings (Android `res/`), imports.
- Unreachable branches (conditions that can never be true, code after early returns).
- Leftovers from removed features (check recent git history for half-deleted features).
- Duplicate/near-duplicate logic that should share one path (esp. card vs popup vs modal paths).
- TODO/FIXME/HACK markers -- list each with an assessment (stale vs actionable).

**B. Documentation drift**
- `docs/*.md` vs actual code -- especially `docs/stash-sdk-js.md` as spec-of-record for `window.stash_sdk` (verify every documented function/callback exists and behaves as documented on BOTH platforms, and everything injected is documented).
- READMEs (root + per-platform + samples): integration steps, API surface, code snippets that would not compile, version numbers.
- `CLAUDE.md` build commands and stated patterns vs reality.
- Comment rot: comments describing behavior the code no longer has.

**C. Memory & resources**
- iOS: retain cycles (blocks capturing self, delegate strongness, NSTimer targets), KVO/notification observers not removed, WKWebView teardown (message handlers removed? `stopLoading`?), CADisplayLink/animator invalidation, associated objects.
- Android: WebView lifecycle (create/destroy pairing, `removeJavascriptInterface`, destroy posted not synchronous), BroadcastReceiver register/unregister pairing, ValueAnimator cancellation on teardown/rotation, Handler callbacks removed, Bitmap recycle (backdrop), static references to Activity/Context, listener leaks in the plugin singleton.
- Memory pressure: bitmap sizes, redundant copies, per-frame allocations in animation paths, webview settings that trade memory badly.
- Known context (do not re-litigate): per-frame `setLayoutParams` relayout in card resize is a known accepted cost -- pin-and-clip was tried and is unsound (see project memory).

**D. Errors, parsing, input limits**
- Unhandled exceptions: `@JavascriptInterface` methods run on a binder thread -- any throw kills the app; same for broadcast receivers, WebViewClient/WKNavigationDelegate callbacks, animator callbacks.
- Parsing robustness: URLs (malformed, empty, unicode, very long, unusual schemes), `intent://` URIs, color strings, ratio/number parsing (NaN, infinity, negatives, locale decimal separators), JSON from the JS bridge (missing keys, wrong types, nulls).
- Public API surface: what happens with null/empty/garbage arguments to every public method on `StashNativeCard` (both platforms)? Ratios outside [0.1, 1.0]? Calls in wrong order (dismiss before open, double open)?
- Silent failures: empty catch blocks, errors swallowed without logging, callbacks never invoked on failure paths.
- Reflection rule: every reflective call must catch `Throwable` (project constraint) -- flag any that only catch `Exception`.

**E. Concurrency & state**
- Main-thread requirements: UI/WebView calls from binder or background threads without `runOnUiThread`/main-queue dispatch.
- Races: dismissal vs in-flight page load, retry timers vs teardown, rotation vs animation, double-tap opening two checkouts, stale-session callbacks firing after dismiss.
- Once-guards: result callbacks that must fire exactly once (success + cancel both firing?).
- Shared singleton mutable state (iOS globals in `StashNativeCard.m` extern'd via Private.h; Android plugin fields) -- unsynchronized cross-thread access.

**F. Security & privacy**
- WebView hardening: file/content access, JS interface exposure surface, universal access settings, mixed content.
- URL/intent handling: intent-redirection hardening (component/selector cleared), open-redirect via externally-supplied URLs, scheme allowlists.
- JS injection: any native string interpolated into `evaluateJavascript`/`evaluateJavaScript` without escaping.
- Logging: PII, tokens, or full checkout URLs in production logs.
- Secrets: hardcoded keys/tokens in samples, e2e config, BrowserStack config, workflows.

**G. Compatibility & API contracts**
- Backward compatibility of the public surface (no breaking changes -- project hard rule); anything that changed semantics silently.
- iOS ARC/non-ARC dual compatibility (Unreal): `__has_feature(objc_arc)` guards where needed.
- Deprecated APIs used without a replacement plan or API-level guard; Android API-level checks matching `minSdk`.
- ProGuard `consumer-rules.pro`: keeps exactly the public surface, nothing internal, nothing missing (obfuscation-breaking reflection?).
- Version string parity (`+sdkVersion` vs `SDK_VERSION`).
- iOS file-list sync: every `.m` in Sources present in `StashNative.xcodeproj` (SPM globs, pbxproj does not).

**H. Platform parity**
- JS bridge (`window.stash_sdk`): identical function set and semantics on both platforms and matching `docs/stash-sdk-js.md`.
- Deeplink handling, theming, safe-area handling, ratio clamping, callback semantics -- same behavior both platforms; flag divergences with evidence from both sides.

**I. Performance**
- Main-thread blocking work (synchronous I/O, heavy parsing, reflection in hot paths).
- Per-frame allocations or relayouts in animation/gesture code (beyond the known accepted card-resize cost).
- Redundant work: repeated safe-area lookups, re-parsing, re-created objects per call.

**J. Tests & CI**
- Unit-test coverage of pure-logic utils (URL classification, sizing math, color parsing) -- what testable logic has no tests?
- Weak assertions (tests that cannot fail), tests testing mocks.
- e2e suite validity (`.github` Appium/BrowserStack), workflow correctness, swiftlint config vs violations.

**K. Numeric & encoding edge cases**
- Ratio clamp correctness at boundaries, px/dp/pt rounding, division by zero in geometry, float comparison with `==`.
- Encoding: base64 paths, URL encoding/decoding round-trips, unicode in payloads/query params, `Locale` sensitivity in `String.format`/`toLowerCase`.

---

The remaining areas are the **code-quality lens** (category `quality`). Judge against the named standards; every finding needs file:line evidence and the specific rule it breaks. Fixes must be behavior-preserving and internal-only.

**L. Naming & clarity**
- Names read as documentation: no cryptic abbreviations, no single-letter names outside tight loops, booleans read as `is/has/should`.
- Platform idiom: Java lowerCamelCase members + `UPPER_SNAKE_CASE` constants; Obj-C descriptive method names with grammatical parameter phrases + `Stash` prefix on public symbols + `_ivar` underscore; Swift lowerCamelCase, no needless words, no Obj-C-isms.
- Consistent vocabulary for the same concept across files (e.g. one of "dismiss" vs "close" vs "teardown", not all three for the same thing).
- INTERNAL names only -- a public symbol with a poor name is a WONTFIX (renaming it breaks the API); note it but do not propose a rename.

**M. Structure & readability**
- Overlong methods / multiple responsibilities; deep nesting that a guard/early-return would flatten.
- Magic numbers and duplicated string/number literals that should be named constants (respect the existing `CardConstants` / iOS constant homes).
- Long parameter lists that a small value/config type would clarify.
- Member ordering and grouping; iOS `#pragma mark` sections present and accurate; related helpers co-located.
- Copy-pasted near-duplicate logic (card vs popup vs modal) that hurts readability even when not a correctness bug.

**N. Style conformance to the guides**
- Google Java Style: import order, NO wildcard imports, brace/indent consistency, line length, `@Override` present, `final` where it aids clarity, one top-level construct per file.
- AOSP/Android: `res/` naming, no unused resources/strings, lint-clean expectations.
- Obj-C: complete nullability audit on public headers (`NS_ASSUME_NONNULL_BEGIN`/`nullable`), correct/consistent property attributes (`copy` for `NSString`, `weak`/`assign` per the ARC guard), `instancetype` initializers, header include hygiene.
- Swift (samples): access control (`private`/`fileprivate` where possible), no force-unwrap/`try!` in sample paths, `guard` for early exit, `swiftlint` clean.

**O. Comment & documentation quality**
- Public API carries accurate doc comments (Javadoc / header doc); comments explain WHY, not restate the code.
- Project rule enforcement: terse human-style comments, no AI-verbose blocks, no emoji. Flag over-commented or stale/misleading comments and commented-out code.
- TODO/FIXME format and staleness (cross-reference area A).

**P. Consistency & idioms**
- The same task done the same way everywhere: threading dispatch shape, reflection-with-`Throwable` pattern, logging tag constants and level usage, error-handling shape, null-guard style.
- Modern, idiomatic constructs over legacy where it improves clarity (without changing behavior).
- Consistent formatting the repo's own tooling would enforce (swiftlint config, any checkstyle/ktlint/android-lint) -- read the configs and flag divergences from them specifically.

## Phase 2 -- gate

Present a summary: counts by severity/category, the full P0/P1 list, notable P2s. Then use `AskUserQuestion` to let the Developer choose: fix everything, fix P0-P1 only, cherry-pick, or stop (ledger stays for a later `fix` run).

## Phase 3 -- fix (from the ledger only)

Work strictly from CONFIRMED entries, ordered P0 -> P3. For each fix:

1. Respect project constraints: no breaking public API changes; both-platform parity for shared behavior; JS bridge changes mirrored on both platforms AND `docs/stash-sdk-js.md` updated; terse human comments; no emojis; reflection catches `Throwable`; new iOS `.m` files added to the pbxproj; keep samples clean.
   - Quality fixes (category `quality`) are held to a stricter bar: they MUST be purely behavior-preserving and internal-only. Never rename/reshape a public symbol, header signature, ProGuard-kept surface, or JS-bridge handler name (all breaking) -- if a public name is poor, mark WONTFIX. No opportunistic scope creep: a naming fix does not get to reformat the whole file. Keep quality diffs small and reviewable; do not add doc comments to code you did not otherwise touch.
2. After each coherent batch, verify:
   - Android: `cd Android && JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :stashnative:assembleRelease :stashnative:testDebugUnitTest :sample:assembleDebug`
   - iOS: `cd iOS/StashNative && xcodebuild -project StashNative.xcodeproj -scheme StashNative -sdk iphoneos build` and swiftlint if Swift files changed.
3. Update the entry to `FIXED` with a note of what was done, or `WONTFIX`/`DEFERRED` with the reason.
4. Do not fix things not in the ledger; if you discover something new mid-fix, add it as a new entry first.

Commit in logical batches using the `[<component>] Summary` format, no co-author trailers. Ask before pushing.
