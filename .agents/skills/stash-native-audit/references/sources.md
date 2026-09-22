# Sources and calibration

## Adapted upstream

This skill adapts selected ideas from [hyhmrright/brooks-lint](https://github.com/hyhmrright/brooks-lint/tree/220fe716c01950966e961e020eda9c457f4dd0a7), pinned at commit `220fe716c01950966e961e020eda9c457f4dd0a7`.

| Upstream reference | Adaptation |
|---|---|
| [Shared framework](https://github.com/hyhmrright/brooks-lint/blob/220fe716c01950966e961e020eda9c457f4dd0a7/skills/_shared/common.md) | Evidence -> principle/contract -> consequence -> remedy; severity deductions adapted to Stash P0-P3 and two explicit lenses. |
| [Production risks](https://github.com/hyhmrright/brooks-lint/blob/220fe716c01950966e961e020eda9c457f4dd0a7/skills/_shared/decay-risks.md) | R1-R6 analysis applied to native hosts, bridges, callbacks, shared state, and compatibility. |
| [Test risks](https://github.com/hyhmrright/brooks-lint/blob/220fe716c01950966e961e020eda9c457f4dd0a7/skills/_shared/test-decay-risks.md) | T1-T6 analysis across JVM/Robolectric, XCTest, shared C++, Windows CTest, and real webview proof runs. |
| [Architecture guide](https://github.com/hyhmrright/brooks-lint/blob/220fe716c01950966e961e020eda9c457f4dd0a7/skills/brooks-audit/architecture-guide.md) | Dependency graph, ownership boundaries, and testability seams. |
| [Debt guide](https://github.com/hyhmrright/brooks-lint/blob/220fe716c01950966e961e020eda9c457f4dd0a7/skills/brooks-debt/debt-guide.md) | Prioritize demonstrated consequences and spread; distinguish accepted debt without erasing its score cost. |
| [Source calibration](https://github.com/hyhmrright/brooks-lint/blob/220fe716c01950966e961e020eda9c457f4dd0a7/skills/_shared/source-coverage.md) | Inspect context, exceptions, and tradeoffs before assigning a principle-based finding. |

The upstream MIT notice is preserved in [LICENSE.brooks-lint](../LICENSE.brooks-lint). Adapted instructions are kept here; using the skill does not require installing brooks-lint or downloading it on every audit.

The score rubric is Stash-specific. We do not adopt upstream lightweight-dashboard finding caps, diff-only scoring, severity overrides that conceal defects, fixed test ratios, automatic source edits, or automatic history/config writes in the repository. Database/service/organization checks are excluded unless the actual audited code introduces them.

## Principle grounding

Use these attributions only when the observed issue matches the principle. They summarize the upstream source matrix; do not fabricate page numbers, quotations, or a claim that a book was directly consulted.

| Source | Relevant principles |
|---|---|
| Brooks, The Mythical Man-Month | Conceptual integrity; coordination and change costs; unnecessary second-system generality. |
| McConnell, Code Complete | Construction clarity, defensive input/error handling, routine structure and naming. |
| Fowler, Refactoring | Divergent Change, Shotgun Surgery, Duplicate Code, Long Method, Feature Envy, Speculative Generality. |
| Martin, Clean Architecture | Dependency direction, stable boundaries, interface and behavioral contracts. |
| Hunt and Thomas, The Pragmatic Programmer | Orthogonality and duplicated knowledge, not line-count DRY. |
| Evans, Domain-Driven Design | Vocabulary, invariant ownership, context boundaries; no requirement for rich objects in a small SDK. |
| Ousterhout, A Philosophy of Software Design | Information hiding, interface complexity, deep modules, leaked decisions. |
| Winters, Manshreck and Wright, Software Engineering at Google | Compatibility, observable contracts, dependency maintenance over time. |
| Meszaros, xUnit Test Patterns | Diagnosable assertions, visible fixtures, erratic/brittle/duplicated tests, feedback cost. |
| Osherove, The Art of Unit Testing | Isolation, meaningful behavior assertions, appropriate test doubles. |
| Feathers, Working Effectively with Legacy Code | Seams and characterization before changing unclear legacy behavior. |
| Whittaker, Arbon and Carollo, How Google Tests Software | Risk-based test portfolios and change protection rather than raw coverage percentages. |

## Project and platform sources

The selected source revision's public contracts, configuration, tests, and compatibility rules establish repository intent. Check implementation against them; a stale doc is evidence to investigate, not unquestionable truth. Prefer primary platform documentation when a finding depends on OS behavior, security boundaries, or changing toolchain requirements.

- [Google Java Style](https://google.github.io/styleguide/javaguide.html) and [AOSP Java conventions](https://source.android.com/docs/setup/contribute/code-style), subordinate to repository Checkstyle and compatibility requirements.
- [Android WebView documentation](https://developer.android.com/reference/android/webkit/WebView) for threading, lifecycle, and API contracts.
- [Apple Cocoa coding guidelines](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CodingGuidelines/CodingGuidelines.html), [WebKit](https://developer.apple.com/documentation/webkit), and [AppKit](https://developer.apple.com/documentation/appkit).
- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and the repository's SwiftLint configuration.
- [Microsoft WebView2 threading model](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/threading-model) and [WebView2 process model](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/process-model) for Windows host behavior.
- [CMake/CTest documentation](https://cmake.org/cmake/help/latest/manual/ctest.1.html) and the selected toolchain's help for available flags and test discovery.
- [Agent Skills in Codex](https://learn.chatgpt.com/docs/build-skills) for repository discovery; agents without that mechanism can read the skill through `AGENTS.md`.

Verify version-sensitive claims when using these sources. If access or evidence is unavailable, state the limitation and keep the claim provisional.
