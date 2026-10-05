# Sample application checks

Treat each sample as a separate integration reference with its own findings and scores. Trace what an integrator would copy. Apply [quality and test checks](quality-and-tests.md) to Java, Swift, Objective-C++, and C++ as present.

## Checks for every sample

- Build/setup instructions must select the intended SDK artifact or source target, match declared versions and OS requirements, and work without the author's local paths.
- Trace open/dismiss/browser/config controls through the public SDK API, listener/delegate registration, lifecycle teardown, and displayed callback state. Check double clicks, reopening from a callback, background/host close, and event ordering in the UI.
- Read link-generation networking: request construction, exact body bytes, signing timestamp/units, encoding, HTTP errors, response validation, retries/timeouts, cancellation, and updating UI from the correct thread. Confirm failure does not leave controls disabled or use an obsolete request result.
- Verify HMAC fixtures against the contract for the selected source revision: exact secret bytes, raw versus base64 interpretation, body bytes, timestamp, header format, Unicode, and malformed secrets. Desktop integration contains a raw-secret correction; do not copy older mobile assumptions into a desktop test or infer current backend behavior solely from a sample comment.
- Inspect credential persistence, access control, file permissions, backup behavior, import/export, clipboard, debug UI, and logs. Redact real secrets and signed URLs in audit evidence. A placeholder is not a leaked credential, and a user-entered demo secret is not proof that the SDK embeds a production key.
- Review sample-side signing warnings and production integration instructions: backend credentials must not be presented as something to ship in a client. Identify actual unsafe guidance, not the mere existence of an explicit demonstration path.
- Validate payload/instance import and export: schema/type handling, duplicate IDs, unknown fields, selected-instance consistency, partial failure, size limits, invalid JSON, and accidental credential disclosure.
- Check stored preferences/defaults against SDK configuration, UI bounds against accepted ranges, restoration after invalid inputs, and schema changes across sample versions.
- Check keyboard navigation, screen-reader labels/focus, text scaling where applicable, contrast, dark mode, small/resized windows, and actionable errors.
- Review unused resources, stale strings/comments, view ownership, notification/listener cleanup, and sample-specific tests. Do not assume SDK unit tests cover sample networking or credential behavior.

## Platform-specific sample review

| Sample | Focus |
|---|---|
| Android | MainActivity/MainViewModel division, configuration recreation, lifecycle observations, background request completion, SharedPreferences/credential storage, settings adapters, dialogs, XML resources, manifest and Gradle packaging. |
| iOS | SceneDelegate/window ownership, controller extensions, table/form state, Keychain result handling, selected credential/payload persistence, network cancellation, Swift access control/force operations, Xcode file membership and SwiftLint. |
| macOS | AppKit startup and host window, SampleSettings persistence, EventLog redaction, LinkGenerator cancellation, Swift/C ABI/delegate interaction, ProofRunner state/timeout, resource lookup from an installed sample. |
| Windows | Win32 message handling/control IDs, HWND and GDI ownership, worker-thread/UI dispatch, WinHTTP/BCrypt return handling and resource release, string conversion, settings/secret handling, EventLog redaction, ProofRunner timers, DLL/test-page copying and packaged execution. |

## Desktop proof runners

Review the proof code and the page it drives, not just CI commands. Confirm failure exits nonzero, timeout cannot become a pass, and the expected events/state come from the real SDK. Inspect sequence normalization: collapsing repeated navigation events must not discard duplicate payment callbacks or late failures. Check whether a pass on an expected prefix leaves later behavior unobserved and report the actual scope of the proof.

`local` proves an offline bridge round trip; `secure` proves the runner's two blocked-navigation cases. `remote` proves the configured remote-load scenario, not a completed purchase. Inspect both source-tree and packaged-page lookup so an absent asset cannot be concealed by a developer path.

For missing tests, name a concrete vulnerable contract and the test that would protect it. Avoid blanket demands for UI snapshots or tests that merely mirror controls. Useful scenarios include deterministic signing vectors, malformed imports, an obsolete network response after window closure, duplicated SDK events, and proof-runner failure/timeout detection.
