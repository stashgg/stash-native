# Sample regression checks

Run on macOS with Swift installed, writing generated files under the temporary root:

```sh
python3 iOS/Sample/Tests/run_regressions.py --output "$HS_TEMP/stash-sample-regressions"
```

If `HS_TEMP` is unset, use `~/Temp/stash-sample-regressions`.

The runner extracts the current request, credential store, and caller methods directly from the
sample. It replaces only the network transport and Security API calls with controlled fixtures.
Late completions still arrive after cancellation to verify the generation guard independently of
transport cancellation. Storage checks use synthetic credentials and never access the Keychain.

The HMAC check compiles `StashHmac.swift` verbatim and signs the vector shared with the Android
sample test (app ID `app_test`, secret base64 of `secret-key`, body `{}`, timestamp
`1700000000000`), so the `v1;appId;millis;base64` header cannot drift between the samples.

These checks cover request ordering, save/load failures, and request signing. The sample still needs its iOS
simulator build and platform UI checks; this harness does not run UIKit or prove device storage
availability. Android switch accessibility checks live in `Android/sample/src/test` and run with
the sample unit tests.
