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

These checks cover request ordering and save/load failures. The sample still needs its iOS
simulator build and platform UI checks; this harness does not run UIKit or prove device storage
availability. Android switch accessibility checks live in `Android/sample/src/test` and run with
the sample unit tests.
