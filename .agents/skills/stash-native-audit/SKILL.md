---
name: stash-native-audit
description: Deep audit of the Stash Native iOS, Android, macOS, and Windows SDKs, their samples, and shared contracts. Produces verified findings and separate code-quality and SDK-health scores, or remediates existing findings when requested. Use for comprehensive audits and quality baselines, not routine edits or a narrow diff review.
---

# Stash Native audit

Audit the full checkout integration, from native entrypoints through web content and callbacks to teardown. Cover all four SDKs and all four samples, including desktop code on a separate development ref. Produce an evidence-backed ledger and a report with reproducible score arithmetic.

Canonical location: `.agents/skills/stash-native-audit/SKILL.md` from the repository root. When opened through a symlink, resolve relative links from this canonical directory, not the symlink's directory.

## Modes

Command arguments: `$ARGUMENTS`. Use them when the command host expands the placeholder; otherwise use the user's invocation. An empty invocation defaults to `audit`.

| Request | Behavior |
|---|---|
| No mode, or `audit` | Investigate, verify, score, and report. Do not change product code or proceed to fixes. |
| `status` | Read existing artifacts and summarize findings, scores, source revisions, and unfinished checks. Do not rerun the audit or change the ledger. If none exists, say so. |
| `fix` | Revalidate the existing findings and apply the user's requested scope using [remediation](references/remediation.md). A bare `fix` covers currently confirmed findings; deferred/accepted debt needs explicit inclusion. |

Honor explicit platform, path, or ref restrictions, and label a narrowed audit as partial. User instructions and host execution restrictions take precedence. An audit request does not authorize a commit, push, release, external message, or real payment.

## Load the relevant guidance

Read the repository's [project rules](../../../AGENTS.md) first. Skill-relative links below are reference files; repository paths inside them refer to the source snapshot under review.

| Reference | When to read |
|---|---|
| [Scope and shared contracts](references/scope-and-contracts.md) | Start of an audit: source refs, inventory, coverage, and cross-platform flow tracing. |
| [iOS](references/ios.md) | iOS SDK review. |
| [Android](references/android.md) | Android SDK review. |
| [Desktop](references/desktop.md) | Shared C++ contract, macOS host, Windows host, and C ABI review. |
| [Samples](references/samples.md) | Review each in-scope sample. |
| [Architecture, code, and test quality](references/quality-and-tests.md) | Every full audit, alongside platform correctness checks. |
| [Verification](references/verification.md) | Before builds, tests, analysis, or runtime checks. |
| [Reporting and scoring](references/reporting.md) | All modes; defines ledger storage, lifecycle, report, and score arithmetic. |
| [Remediation](references/remediation.md) | Only when fixes are requested. |
| [Sources and calibration](references/sources.md) | Before assigning principle-based findings; includes upstream attribution and exclusions. |

For `status`, load project rules and reporting only. A complete four-platform audit reads every audit reference; remediation is conditional.

## Audit workflow

1. **Establish the source set.** Record the current revision and working-tree changes. Locate desktop using the scope reference, resolve every ref to a commit, and record which snapshot supplies each component. Never check out another branch over the user's work.
2. **Resume and inventory.** Resolve the external artifact directory, load prior entries without discarding history, and revalidate stale evidence. Inventory first-party code, headers, tests, resources, manifests, workflows, and docs. Record every exclusion and unavailable surface.
3. **Map behavior and ownership.** Draw the dependency graph, enumerate native and JS APIs, and build a contract matrix across platforms. Trace opening, loading, processing, payment results, browser handoff, dismissal, reset, and shutdown. Include failure and reentrant paths.
4. **Review correctness and quality.** Read the source for each applicable coverage area. Apply the platform checklists and R1-R6/T1-T6 risks. Search hits, file length, or lint output locate candidates; they do not establish a finding on their own.
5. **Verify candidates.** Check callers, guards, configuration, tests, platform differences, and known constraints. Record a trigger, evidence, consequence, and compatible remedy. Deduplicate by underlying cause, then mark candidates confirmed or false-positive with reasons.
6. **Run available checks.** Use the verification reference and record commands, revision, environment, exit status, test count, and artifact paths. Keep static conclusions, executed tests, prior CI evidence, and pending runtime work distinct.
7. **Close coverage gaps.** Review remaining files and unresolved candidates; follow up on interactions exposed by findings. A quiet search or a pass with no new findings is not completion if coverage is missing. Stop with an explicit partial report when execution or available context prevents completion.
8. **Score and report.** Apply the versioned rubric to substantiated unresolved findings, without a finding cap. Include every finding in the ledger, prioritized findings in the report, coverage, the dependency graph, tests, and remediation order. Stop after reporting in audit mode.

## Review discipline

- Every claim needs source evidence: relative file and line, plus the source-set label for branch snapshots. A runtime claim also needs a reproducible trace or test result.
- Read the code behind every candidate yourself before confirming it. If the host and user permit delegation, divide bounded read-only reviews by component or concern and pass the source map, rules, ledger, and relevant references. Use the same coverage and confirmation requirements in sequential review. No particular agent tool or worker count is required.
- Public entrypoints can be called by external apps, engine wrappers, reflection, selectors, or web content. Absence of an internal caller does not establish dead code.
- Preserve justified compatibility workarounds and platform differences. Separate implementations are not automatically duplicated knowledge. Shared desktop code is one source with two consumers.
- Prefer concrete consequences over style preferences. Quality-only findings cannot exceed P2; a demonstrated behavioral defect belongs to the correctness lens.
- Missing execution evidence is a verification gap, not an automatic code defect or a passing result. Never report an unreviewed platform as 100/100.
- Reuse existing authorization for fixes. Do not insert an additional approval gate for already-requested compatible remediation.
