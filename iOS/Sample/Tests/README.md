# Sample regression checks

Run on macOS with Swift installed, writing generated files under the temporary root:

```sh
python3 iOS/Sample/Tests/run_regressions.py --output "$HS_TEMP/stash-sample-regressions"
```

If `HS_TEMP` is unset, use `~/Temp/stash-sample-regressions`.

The runner extracts the current request, credential selection, open actions, credential store,
migration, import/export and the bundled-credential constants directly from the sample. It replaces
only the network transport, the signer in the request check, the Security API calls, and the
StashNative SDK and UIKit surface the open actions call (text fields, configs, alerts) with
controlled fixtures. Late completions still arrive after cancellation to verify the generation guard
independently of transport cancellation. Storage checks use synthetic credentials and never access
the Keychain.

The HMAC check compiles `StashHmac.swift` verbatim and signs the vector shared with the Android
sample test (app ID `app_test`, secret base64 of `secret-key`, body `{}`, timestamp
`1700000000000`), so the `v1;appId;millis;base64` header cannot drift between the samples. It also
asserts the accepted and rejected ingress-secret vectors that `StashHmacTest` asserts on Android.

The storage check imports `Android/sample/src/test/resources/instances-export-v2.json`, the
export document the Android `InstanceImportTest` also imports, and asserts every field and the
exporter's key set. It runs the malformed documents in `instances-import-cases.json` from the same
directory, which Android also runs. It also checks the Keychain accessibility class passed on update
and insert, the resign-active flush of typed instance edits, and the superseded-secret migration.

These checks cover request ordering, the no-fallback credential rule, manual-open supersession,
save/load failures, the shared export and import formats, and request signing. The sample still
needs its iOS simulator build and platform UI checks; this harness does not run UIKit or prove
device storage availability. Android switch accessibility checks live in `Android/sample/src/test` and run with
the sample unit tests.
