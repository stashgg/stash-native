# Reporting and scoring

Rubric: `stash-native-audit/v1`. Arithmetic is deterministic for the same confirmed finding set, scope, and coverage state. Discovery and severity assessment still require engineering judgment; the score is not a probability of correctness or a certification.

## Artifact location and history

Resolve the repository's absolute root using `git rev-parse --show-toplevel` and canonicalize it with `Path.resolve()` or its platform equivalent. The checkout ID is the first 12 lowercase hexadecimal characters of SHA-256 over that absolute path's UTF-8 bytes, without a trailing newline.

The artifact directory is `${HS_TEMP:-$HOME/Temp}/stash-native-audit/<checkout-id>/`. On Windows use the nonempty `HS_TEMP` environment variable or the user's home `Temp` directory. This read-only Python example prints the directory and works from a nested repository directory:

```python
import hashlib
import os
from pathlib import Path
import subprocess

root = Path(subprocess.check_output(
    ["git", "rev-parse", "--show-toplevel"], text=True).strip()).resolve()
checkout_id = hashlib.sha256(str(root).encode("utf-8")).hexdigest()[:12]
temporary_root = Path(os.environ.get("HS_TEMP") or Path.home() / "Temp").expanduser()
print(temporary_root / "stash-native-audit" / checkout_id)
```

- `AUDIT_LEDGER.md` holds stable findings and their history. Update entries in place without removing past decisions.
- `runs/<unique-UTC-timestamp>/` holds an immutable report per completed/partial run, source map, coverage inventory, logs, and probe artifacts.
- `LATEST` contains the relative path of the latest report. Update it only after the report is written; `status` reads it and the ledger without changing them.
- Create directories only in audit/fix mode as needed. Do not commit reports or copy them into the project unless requested. Generated reports remain outside the repository even when this skill is tracked.
- If root `AUDIT_LEDGER.md` from the old command exists, read and import it once without changing the original. Preserve IDs/history and record import origin. For an ID collision representing a different issue, allocate a new ID and retain the legacy ID in its history.
- Keep one ledger writer if review is delegated. Do not let independent workers overwrite each other's findings.

Record source labels, full commits, working-tree changes, target components, rubric version, and exclusions in each run. Never claim a dirty tree has been validated solely from its base SHA. Redact sensitive evidence without deleting the information needed to understand the failure.

## Finding format

Allocate increasing `A-NNN` identifiers, never reusing deleted/rejected IDs. Use one primary lens (`correctness` or `quality`), a descriptive category, zero or more applicable R/T codes, and one or more affected component IDs from the scope guide.

```markdown
### A-NNN [CONFIRMED] [P2] quality/structure -- Concrete title
- Components: macos, windows, desktop-shared
- Risk codes: R2 (or none when no R/T principle fits)
- Source: source-label; full revision in the run's source map
- Location: path/to/file:line; additional affected locations
- Symptom: observed behavior or maintainability problem and its trigger
- Contract/principle: the violated API, project rule, configured check, or relevant principle
- Evidence: short code excerpt, call/state trace, test, or runtime observation
- Consequence: who is affected, under what conditions, and what fails or becomes harder
- Remedy: the smallest compatible change addressing the underlying cause
- Verification: a discriminating test or observation; include platform/environment
- Confirmation: who/which pass checked callers, guards, counterexamples, and source revision
- History: dated confirmation, rejection, deferral, fix, or reopening with reasons
```

An absent test can support a quality finding when it exposes a concrete unprotected contract. A missing runner is recorded in verification coverage instead. Do not claim a reachable crash, exploit, leak, or API break from an isolated pattern without following the path.

## Lifecycle and severity

| Status | Meaning and scoring |
|---|---|
| `OPEN` | Candidate not yet independently checked against its context. Excluded from deductions; unresolved candidates make the affected assessment provisional. |
| `CONFIRMED` | Evidence and consequence checked for the selected source set. Included while unresolved. |
| `FALSE-POSITIVE` | Rejected with a reason, counterexample, or duplicate-of ID. Preserve history; exclude from deductions. |
| `FIXED` | Relevant evidence shows the defect is removed and required targeted verification passed. Exclude from current deductions; preserve the previous score snapshot. |
| `WONTFIX` | Substantiated issue accepted with an explicit reason. Still deduct while the issue exists. Do not use this status to turn a supported design choice into debt. |
| `DEFERRED` | Substantiated unresolved issue postponed with a reason and next verification/action. Still deduct. |

Transitions start with OPEN -> CONFIRMED or FALSE-POSITIVE. CONFIRMED can become FIXED/WONTFIX/DEFERRED; later evidence may reopen any entry. Re-read previously rejected claims only when relevant code/context changes. Imported or stale entries need revalidation before scoring the new source set; carry their historical state and record current confirmation as pending instead of erasing it.

| Priority | Calibration |
|---|---|
| P0 | Demonstrated release-blocking failure such as an exploitable trust-boundary breach, data loss, or widespread crash in an ordinary supported flow. Explain the trigger and reach. |
| P1 | Reachable functional/security/compatibility bug an integrator can hit, including incorrect payment callbacks or broken lifecycle behavior. |
| P2 | Supported maintainability/test debt or a bounded resource, performance, or defensive-handling problem with a concrete consequence. |
| P3 | Local clarity, dead code, style, or documentation polish with evidence of a real issue. |

Quality-only findings are P2 or P3. If the evidence demonstrates a behavioral bug, classify it as correctness; do not add a second quality finding for the same underlying problem. Retain relevant R/T tags for analysis without multiple deductions. A public spelling preserved for compatibility is not itself a finding.

## Dedupe and component attribution

Group reports with the same underlying cause, observable problem, and remedy. Keep all affected locations and components. Similar symptoms with independent causes/fixes remain separate. Group recurring style violations by the supported pattern rather than one penalty per line.

An issue in shared desktop code may affect `desktop-shared`, `macos`, and `windows`. It is one package finding and one finding in each genuinely affected component. Do not attribute every SDK finding to samples merely because they depend on it. Assign sample-specific consequences when there is evidence. Use `package` for support-only CI/docs/distribution issues, adding affected SDK/sample components where justified.

When reviewing both current and desktop-branch support files, deduplicate identical causes rather than charging twice for copies at different refs. Count only findings relevant to the selected source set; retain out-of-scope history separately.

## Scores

For the set of substantiated unresolved findings (currently validated CONFIRMED, WONTFIX, and DEFERRED):

```text
N0, N1, N2, N3 = counts of P0, P1, P2, P3 findings
Q2, Q3         = counts of quality-lens P2 and P3 findings

SDK health   = max(0, 100 - 30*N0 - 15*N1 - 5*N2 - N3)
Code quality = max(0, 100 - 5*Q2 - Q3)
```

SDK health includes both lenses. Code quality includes maintainability, documentation, and test-quality findings assigned to the quality lens; it does not score correctness findings again. Report the two numbers separately, never add or average them. Do not label the score as the unmodified upstream brooks-lint score.

Calculate package scores from the union of unique finding IDs. Calculate component scores from their affected finding sets. Package scoring is not an average of component scores, so a shared issue is never multiplied by the number of hosts. Include the four SDK rows, four sample rows, and desktop-shared; show package-support findings in the package total.

Show every open P0/P1 prominently beside scores. A high code-quality number must not hide a correctness defect. Do not discard minor or low-ranked findings to improve the score or use upstream dashboard finding caps.

### Coverage rules

- An unreviewed/unavailable component has `not assessed`, not 100. Keep its row visible.
- A partially reviewed component can have an observed score only with `provisional`, explicit reviewed/missing areas, and pending candidates/checks.
- A reviewed component with no findings scores 100 for the reviewed scope. Unexecuted required native/device checks still make the overall assessment provisional; say what the number establishes.
- If any requested component is unreviewed or required verification is incomplete, label the package result `provisional` and show coverage. Do not infer the unknown components' scores or silently omit them.
- Intentional N/A cases need a platform contract or scope reason. No Windows machine is not an N/A reason for Windows support.
- Compare trends only with the same rubric, component scope, and compatible review/execution coverage. Otherwise describe the scope change without presenting a numeric improvement. Record source revisions for every comparison.

### Worked scoring cases

These are synthetic fixtures, not findings about this repository. Cases assume reviewed scope except where stated.

| Case | Included findings | Other records or condition | Health | Quality |
|---|---|---|---|---|
| Clean | None | Complete review/verification | 100 | 100 |
| Mixed | correctness P0 and P1; quality P2 and P3 | None | 49 | 94 |
| Shared | correctness P1; quality P2, both affecting macos/windows/desktop-shared | One ID per cause; each affected component also scores 80/95 | 80 | 95 |
| Accepted debt | correctness P1 WONTFIX; quality P2 DEFERRED | Both substantiated and still present | 80 | 95 |
| Excluded states | None | FALSE-POSITIVE P0, verified FIXED P1, OPEN P2; provisional due to OPEN | 100 | 100 |
| Health floor | Four correctness P0 findings | None | 0 | 100 |
| Quality floor | Twenty-one quality P2 findings | None | 0 | 0 |
| Missing Windows | One Android quality P3 | Windows unreviewed: Windows scores not assessed; package provisional | 99 | 99 |

For duplicate candidate reports of the same Shared-case P1, retain a duplicate-of note but keep the package at 80/95. After its P1 is verified fixed, that case becomes 95/95. Merely marking the P1 deferred leaves it at 80/95.

## Report structure

Write `AUDIT_REPORT.md` in the run directory with:

1. **Result and source set:** assessment status, date, all revisions/working changes, rubric, scope, primary risks, and open P0/P1 count. State mixed-revision scope when applicable.
2. **Scorecard:** package and each SDK/sample/shared component; health, quality, review status, verification status, and contributing IDs/counts. Show formulas/counts so the numbers can be reconstructed.
3. **Coverage:** file inventory summary, component/area matrix, exclusions, pending candidates, and native/device/engine execution gaps. Never relabel file-review percentages as test coverage.
4. **Architecture and contracts:** Mermaid dependency graph, ownership map, cross-platform API/event differences, and consequential coupling.
5. **Findings:** severity-ordered substantiated issues with the complete finding fields or links into the ledger. Keep every finding accessible; do not cap the scored set. Separate unconfirmed candidates, false positives, accepted/deferred debt, and prior fixes.
6. **Verification:** source label, environment, command/check, outcome, discovered/executed/skipped tests, and artifact path. Distinguish local results, inspected CI results, and manual steps still required.
7. **Remediation order:** compatible changes in dependency/severity order, test requirements, and explicit constraints. Do not implement them in audit mode.

`status` summarizes the latest report and current ledger, names their source revisions, and warns when they describe a different source set. It does not silently recompute scores for unreviewed changes. With no report/ledger, say that no audit exists; do not invent a baseline or start one.
