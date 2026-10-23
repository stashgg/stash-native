#!/usr/bin/env python3
"""Compile exact sample methods with synthetic network, Keychain and SDK boundaries on macOS."""

import argparse
import os
from pathlib import Path
import re
import subprocess


def member(source, name):
    """One type member at four-space indent: a func, var or let with its body or continuation."""
    lines = source.split("\n")
    declaration = re.compile(
        r"^    (?:@objc )?(?:private )?(?:static )?(?:func|var|let) " + re.escape(name) + r"\b")
    for index, line in enumerate(lines):
        if not declaration.match(line):
            continue
        start = index - 1 if index and lines[index - 1] == "    @discardableResult" else index
        end = index + 1
        while end < len(lines) and (lines[end].startswith("     ") or not lines[end].strip()):
            end += 1
        if end < len(lines) and lines[end] in ("    }", "    ]"):
            end += 1
        return "\n".join(lines[start:end]).rstrip()
    raise RuntimeError(f"Sample member not found: {name}")


def members(source, names):
    return "\n".join(member(source, name) for name in names)


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
    bundled = members(controller, [
        "defaultStashApiKey", "defaultStashAppId", "defaultStashKeyName", "bundledEntry"])
    entry = (sample / "ApiKeyEntry.swift").read_text().replace("import UIKit", "import Foundation")

    # Credential selection, the open actions and the request run verbatim; only the transport,
    # the signer and the SDK/UIKit surface are fixtures.
    request_methods = "\n".join([
        members(actions, ["cancelGenerateRequest", "performGenerateUrl", "openCardTapped",
                          "openBrowserTapped", "openScannerTapped"]),
        members(instances, ["selectedApiKey", "activeEntry", "activeApiKey", "activeAppId",
                            "isActiveKeyProduction", "activePayload"]),
        bundled])
    request_methods = request_methods.replace("URLSession.shared", "ProbeSession.shared")
    request = (tests / "RequestLifetime.swift.template").read_text().replace(
        "// INSERT_PROPERTIES", members(controller, [
            "generateRequest", "generateRequestId", "apiKeys", "selectedApiKeyId"]))
    request = request.replace("// INSERT_METHODS", request_methods)
    request = request.replace("// INSERT_LIFECYCLE", "\n".join([
        re.search(r"^    override func viewWillDisappear\b.*?^    }", controller,
                  re.MULTILINE | re.DOTALL).group(),
        re.search(r"^    deinit \{.*?^    }", controller, re.MULTILINE | re.DOTALL).group()]))

    store = (sample / "ApiKeyStore.swift").read_text()
    # Never access the developer's Keychain; substitute only the three Security API boundaries.
    for name in ["SecItemCopyMatching", "SecItemUpdate", "SecItemAdd"]:
        store = store.replace(name, "probe" + name)
    storage_methods = "\n".join([
        members(instances, [
            "instancesExportVersion", "loadApiKeys", "saveApiKeys", "importInstancesJson",
            "exportInstancesJson", "setInstanceName", "setInstanceAppId", "setInstanceSecret",
            "flushPendingInstanceEdits", "persistInstances", "saveInstancePayload"]),
        members(controller, ["supersededBundledSecrets", "isSupersededBundledSecret"]),
        bundled])
    storage = (tests / "CredentialStore.swift.template").read_text().replace(
        "// INSERT_PROPERTIES", members(controller, [
            "apiKeys", "selectedApiKeyId", "canSaveApiKeys", "hasPendingInstanceEdits",
            "didShowCredentialSaveError"]))
    storage = storage.replace("// INSERT_METHODS", storage_methods)
    # Export and malformed-import documents are shared with the Android InstanceImportTest.
    resources = tests.parents[2] / "Android" / "sample" / "src" / "test" / "resources"
    for marker, constant, file in [("// INSERT_FIXTURE", "sharedExportFixture", "instances-export-v2.json"),
                                   ("// INSERT_IMPORT_CASES", "sharedImportCases",
                                    "instances-import-cases.json")]:
        fixture = (resources / file).read_text()
        storage = storage.replace(
            marker, f'let {constant} = #"""\n' + fixture.rstrip("\n") + '\n"""#')
    # The signer compiles verbatim; only the vector harness is appended.
    hmac = (sample / "StashHmac.swift").read_text() + "\n" + (tests / "HmacVector.swift.template").read_text()
    for name, source in [("request-lifetime", entry + request), ("credential-store", entry + store + storage),
                         ("hmac-vector", hmac)]:
        source_path = output / f"{name}.swift"
        source_path.write_text(source)
        executable = output / name
        subprocess.run(["swiftc", "-swift-version", "5", "-module-cache-path", str(output / "modules"),
                        str(source_path), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
