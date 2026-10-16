#!/usr/bin/env python3
"""Compile exact sample methods with synthetic network/Keychain boundaries on macOS."""

import argparse
import os
from pathlib import Path
import re
import subprocess


def method(source, name):
    match = re.search(
        r"^(?:    @discardableResult\n)?    (?:@objc )?(?:private )?func " + name + r"\b.*?^    }",
        source, re.MULTILINE | re.DOTALL)
    if not match:
        raise RuntimeError(f"Sample method not found: {name}")
    return match.group()


def properties(source, names):
    return "\n".join(re.search(r"^    var " + name + r"\b.*$", source, re.MULTILINE).group()
                     for name in names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True,
                        help="Generated sources, binaries and module cache directory under HS_TEMP")
    args = parser.parse_args()
    temp = Path(os.environ.get("HS_TEMP") or Path.home() / "Temp").expanduser().resolve()
    output = args.output.resolve()
    if not output.is_relative_to(temp):
        parser.error(f"--output must be under {temp}")
    output.mkdir(parents=True, exist_ok=True)
    tests = Path(__file__).resolve().parent
    sample = tests.parent / "StashNativeSample" / "StashNativeSample"
    controller = (sample / "ViewController.swift").read_text()
    actions = (sample / "ViewController+Actions.swift").read_text()
    instances = (sample / "ViewController+Instances.swift").read_text()
    request_methods = "\n".join(method(actions, name) for name in
                                ["cancelGenerateRequest", "performGenerateUrl"])
    # Only the transport changes; all cancellation, response and main-queue logic stays verbatim.
    request_methods = request_methods.replace("URLSession.shared", "ProbeSession.shared")
    request = (tests / "RequestLifetime.swift.template").read_text().replace(
        "// INSERT_PROPERTIES", properties(controller, ["generateRequest", "generateRequestId"]))
    request = request.replace("// INSERT_METHODS", request_methods)
    lifecycle = re.search(r"^    override func viewWillDisappear\b.*?^    }", controller,
                          re.MULTILINE | re.DOTALL).group()
    lifecycle += "\n" + re.search(r"^    deinit \{.*?^    }", controller,
                                  re.MULTILINE | re.DOTALL).group()
    request = request.replace("// INSERT_LIFECYCLE", lifecycle)

    entry = (sample / "ApiKeyEntry.swift").read_text().replace("import UIKit", "import Foundation")
    store = (sample / "ApiKeyStore.swift").read_text()
    # Never access the developer's Keychain; substitute only the three Security API boundaries.
    for name in ["SecItemCopyMatching", "SecItemUpdate", "SecItemAdd"]:
        store = store.replace(name, "probe" + name)
    storage_methods = "\n".join(method(instances, name) for name in [
        "loadApiKeys", "saveApiKeys", "importInstancesJson", "setInstanceName", "saveInstancePayload"])
    storage = (tests / "CredentialStore.swift.template").read_text().replace(
        "// INSERT_PROPERTIES", properties(controller, [
            "apiKeys", "selectedApiKeyId", "canSaveApiKeys", "didShowCredentialSaveError"]))
    storage = storage.replace("// INSERT_METHODS", storage_methods)
    for name, source in [("request-lifetime", request), ("credential-store", entry + store + storage)]:
        source_path = output / f"{name}.swift"
        source_path.write_text(source)
        executable = output / name
        subprocess.run(["swiftc", "-swift-version", "5", "-module-cache-path", str(output / "modules"),
                        str(source_path), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
