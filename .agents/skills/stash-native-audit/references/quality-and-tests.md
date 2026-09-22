# Architecture, code quality, and test quality

Apply these checks alongside native correctness review. The R/T risk codes come from the [adapted sources](sources.md); this guide supplies Stash-specific interpretation. Cite an applicable project rule, platform guideline, or named principle only when the evidence supports it.

## Production and architecture risks

| Code | Risk | Stash-specific investigation | Avoid false positives |
|---|---|---|---|
| R1 | Cognitive overload | State spread across flags/globals, nested lifecycle branches, opaque event/config names, mixed parsing/UI/callback logic, unclear responsibility or ownership. Explain the change a maintainer cannot safely reason about. | Linear methods can be long; numeric thresholds alone do not establish debt. Preserve public names. |
| R2 | Change propagation | Follow a bridge/config/callback change through facades, session, platform hosts, samples, docs and tests. Identify unrelated responsibilities that change together and public behavior callers depend on. | Updating all implementations of a shared protocol is expected. Composition roots and compatibility adapters may have many dependencies. |
| R3 | Knowledge duplication | Find independently maintained copies of one decision: callback guards, parsing policy, constants, defaults, URL rules, or docs that drift. Name the common owner and diverging behavior. | Similar iOS/Android implementations, transport preludes, ABI boundary declarations, and small test fixtures may need separate ownership. |
| R4 | Accidental complexity | Look for unused abstractions, pass-through layers, competing state owners, speculative configuration, redundant conversions, dead branches, and helpers exposing the details they should hide. | Wrappers that absorb OS/runtime variation have a purpose; protocol switches and defensive guards do not require polymorphism. |
| R5 | Dependency disorder | Check facade/internal boundaries, shared C++ purity, platform headers leaking into shared logic, C ABI stability, sample dependence on private SDK internals, extern state coupling, dependency upgrade constraints. | Callback/event arrows are not necessarily compile cycles. Platform hosts legitimately depend on both UI frameworks and the shared contract. |
| R6 | Domain model distortion | Compare payment success/failure, purchase processing/completion, page loading, user dismissal, reset, shutdown, and external handoff with their state transitions and documented vocabulary. | A config struct or event DTO can be data-only. This SDK does not need a new enterprise domain layer. |

Review source and relevant history when it clarifies an exception or frequently changed contract. Do not invent team ownership, maintenance pain, or change frequency. Historical evidence can support a consequence; file size and fan-out are only clues.

## Readability, idioms, and documentation

- **Dead code/resources:** investigate unused imports, constants, methods, assets, unreachable branches, commented-out code, and TODO/FIXME/HACK markers. Check reflection, selectors, ABI exports, engine callers, generated membership, and JS use before declaring an item unused.
- **Names and structure:** use consistent checkout vocabulary, descriptive internal names, clear units, early returns where they clarify, cohesive methods, and a single home for shared decisions. Identify the concrete maintenance cost of extraction proposals.
- **Java:** use repository Checkstyle first, then Google Java/AOSP conventions where applicable: imports, naming, braces, overrides, constant/resource naming, visibility and annotation consistency.
- **Objective-C/Objective-C++:** inspect Cocoa method naming, prefixes, init/instancetype, nullability, property ownership, private interfaces, ivar conventions, includes, bridging casts, and C++ lifetime interactions. Do not mechanically apply ARC rules to non-ARC interfaces.
- **Swift:** apply `.swiftlint.yml` and Swift API Design Guidelines to access control, optionals, force operations, naming at call sites, capture ownership, and UIKit/AppKit threading. Flag a force operation with a reachable failure or a configured rule, not personal taste.
- **C++:** use C++17 and the actual build's warnings/conventions. Review RAII, move/copy ownership, resource handles, signed/unsigned conversions, exception boundaries, header dependencies, constness, and ABI-facing types. Do not invent an unconfigured clang-format or clang-tidy policy.
- **Comments/docs:** explain non-obvious constraints succinctly; remove stale or misleading behavior claims from proposed fixes. Check API comments, snippets, version requirements, bridge docs, platform docs, agent rules, sample setup, packaging, and CI descriptions against the same source revision.

Purely subjective preferences are observations, not scored findings. Report recurring style issues as one supported pattern with all affected locations when the cause and remedy are shared; do not create a penalty per occurrence. A serious behavioral defect is a correctness finding even if refactoring is its remedy.

## Test-suite map

Map actual tests and execution layers before judging coverage:

- Android JVM/JUnit and Robolectric tests; distinguish shadows from default-returning android.jar stubs.
- iOS XCTest through the simulator package target; identify which tests reach real UIKit/WebKit and which stop before presentation.
- Portable C++ shared desktop tests; inspect the assertion/check mechanism under the actual build configuration.
- macOS XCTest, Objective-C++/Swift interoperability, and WKWebView proof runs.
- Windows CTest executables, facade/ABI tests, and WebView2 proof runs on Windows.
- All sample-specific tests, local JS harnesses, device/engine/manual matrices, and CI jobs that actually execute them.

Record test discovery/counts, contract coverage, runtime, isolation, and environment needs. Source-file counts are review coverage, not test coverage. Report missing branch/error-path coverage only after looking for protection at other appropriate layers.

## Test risks

| Code | Risk | Review questions and evidence |
|---|---|---|
| T1 | Test obscurity | Do names and assertions identify the scenario and expected event/state? Are singleton setup, fixtures, loopers, main queues, implicit files, clocks, and host windows visible? Could a failure identify the broken contract? |
| T2 | Test brittleness | Does a behavior-preserving change break assertions about private fields, reflection targets, incidental call order, exact source text, timing sleeps, or snapshots? Check necessity before flagging a legacy seam. |
| T3 | Test duplication | Are repeated fixtures/scenarios maintained independently without protecting different risks? Compare unit versus host versus packaged sample coverage before grouping them as duplicates. |
| T4 | Mock abuse | Can the real parser/state machine/event dispatch be broken while the test still passes? Check tests of mocks, Android stub default values, excessive setup, and production changes made solely to expose internals. A callback assertion may itself be the public behavior. |
| T5 | Coverage illusion | Trace failure branches, invalid inputs, callback order/duplicates, reentrant reopen, race/cancellation, stale sessions, host close and teardown. Detect no-op test discovery, disabled Release assertions, swallowed test exits, grep-only proof success, or tests that never reach WebKit/WebView2. |
| T6 | Architecture mismatch | Are high-risk logic and shared session transitions testable quickly, while host ownership/navigation gets real platform coverage? Are engine/desktop UI claims backed only by portable tests? Identify missing seams or characterization coverage before risky refactors. |

No mandatory unit/integration/E2E ratio applies. Multiple assertions can describe one behavior. Mocks at nondeterministic boundaries, local setup duplication, and meaningful event assertions can be appropriate. Do not declare all webview-dependent behavior untestable.

## Priority and remedies

For each confirmed issue, describe the observed symptom, supporting source/contract, concrete consequence, and smallest compatible remedy. Name the regression test or runtime observation that would fail before the fix and pass after it.

Prioritize severity first, then demonstrated reach, likelihood, and dependencies between fixes. Use observed affected components and call paths as spread evidence. If adopting a Pain x Spread note from brooks-lint, label any unmeasured pain unknown; never manufacture developer experience to produce a number. Priority notes do not change the [scoring formula](reporting.md).

Preserve behavior for quality-only fixes and require characterization of unclear legacy behavior before changing it. Do not rename supported public APIs, JS handlers, or desktop C exports to improve style scores.
