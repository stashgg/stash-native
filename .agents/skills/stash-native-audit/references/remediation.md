# Remediation of confirmed findings

Use only when the user requests fixes. The default audit ends with findings and scores.

## Select and revalidate

- Load the existing ledger, latest report, project rules, and verification reference. If no ledger exists, explain that there is no confirmed work list; use any explicitly supplied finding as a candidate and verify it before editing. Do not launch an unrelated full audit.
- Follow the requested IDs, severities, or components. A bare `fix` includes currently CONFIRMED findings. WONTFIX/DEFERRED entries remain outside that default unless the user includes them.
- Re-read each target in the current source set, check guards/callers and prior verification, and preserve the finding ID. If already resolved, verify and record that; if invalid, retain the rejection reason.
- For desktop code on another ref, do not apply a patch to the mobile checkout or merge the desktop branch. Work in an isolated checkout under the temporary root for the selected ref and identify it in the result. Preserve user changes. A request covering fixes on that ref is sufficient authorization for an isolated workspace; it is not authorization to merge or publish it.

## Implement compatible changes

- Address P0/P1 first, then dependencies and demonstrated reach among P2/P3. Group coherent fixes so each change and its verification are reviewable.
- Preserve public Objective-C/Java/C++ APIs, engine wrappers, JS names, desktop C exports/calling conventions, event order, payloads, threading, and ownership contracts. A quality-only fix must preserve behavior and remain internal.
- Changes to shared checkout behavior need matching mobile implementations, desktop Session/script behavior where applicable, bridge docs/test pages, and contract tests in the selected release source set. Do not force intentional desktop UI differences into mobile semantics.
- Preserve iOS non-ARC compatibility, Xcode source membership, Android same-process checkout and optional-library fallbacks, narrow consumer rules, and desktop host/shared ownership boundaries.
- Add a regression or characterization test when it distinguishes the actual failure or protects unclear behavior. Do not add tests that merely reproduce implementation structure or broadly reformat unrelated files.
- Log newly discovered issues before fixing them. Keep them within the user's scope; report unrelated work separately.

## Verify and record

- Run the relevant platform tests/builds/lints from [verification](verification.md), plus the regression scenario. Shared C++ changes require shared tests and affected host verification; mobile-only success is not evidence for a Windows fix.
- Mark FIXED only after the problem's removal and required targeted verification are established. If a patch exists but necessary validation is unavailable, retain an unresolved status, record the patch and blocker, and do not claim the score improvement as verified.
- Update the ledger history and produce a new report with comparable before/after scores. Do not remove WONTFIX/DEFERRED debt from deductions merely because it is accepted.
- Report edited locations, verified behavior, and remaining execution gaps. Respect existing authorization instead of inserting another routine approval gate. Commit, push, merge, release, and external reporting require the corresponding user request.
