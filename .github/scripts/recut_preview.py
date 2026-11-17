"""Replace a mutable preview only after its replacement artifacts pass validation."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def run(*args, input=None):
    try:
        return subprocess.run(args, input=input, text=True, capture_output=True, check=True).stdout.strip()
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"{args[0]} {args[1]} failed: {error.stderr.strip()}") from error


def metadata(release):
    return {key: release.get(key) for key in (
        "id", "name", "tag_name", "target_commitish", "body", "draft", "prerelease", "immutable",
    )}


def fingerprint(release):
    assets = [{key: asset.get(key) for key in (
        "id", "name", "label", "size", "digest", "state", "updated_at",
    )} for asset in release["assets"]]
    return metadata(release), release["updated_at"], sorted(assets, key=lambda asset: asset["name"])


class Recut:
    def __init__(self):
        self.repository = os.environ["GITHUB_REPOSITORY"]
        self.version = os.environ["VERSION"]
        self.sha = os.environ["GITHUB_SHA"]
        self.tag = f"refs/tags/{self.version}"
        self.branch = f"refs/heads/release/{self.version}"
        self.directory = Path(os.environ["HS_TEMP"]) / "release-preview"
        self.names = sorted(f"{name}-{self.version}.{extension}"
                            for name in ("StashNative", "StashNativeCodeLink")
                            for extension in ("aar", "xcframework.zip"))

    def api(self, path, payload=None):
        args = ["gh", "api", f"repos/{self.repository}/{path}"]
        if payload is not None:
            args.extend(["--method", "PATCH", "--input", "-"])
        return json.loads(run(*args, input=json.dumps(payload) if payload is not None else None))

    def release(self):
        return self.api(f"releases/tags/{self.version}")

    def refs(self):
        output = run("git", "ls-remote", "origin", self.tag, self.branch, "refs/heads/main")
        return {ref: sha for sha, ref in (line.split() for line in output.splitlines())}

    def require_preview(self, release, complete=True):
        if (release["tag_name"] != self.version or not release["prerelease"]
                or release["draft"] or release.get("immutable", False)):
            raise RuntimeError("Recutting requires an existing published, mutable prerelease")
        names = sorted(asset["name"] for asset in release["assets"])
        if (complete and names != self.names) or not set(names).issubset(self.names):
            raise RuntimeError("The preview must contain exactly the four expected SDK assets")

    def output(self, skip, recut=False):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"skip={str(skip).lower()}\nrecut={str(recut).lower()}\n")

    def check(self):
        requested = os.environ.get("RECUT_PREVIEW") == "true"
        if os.environ.get("RELEASE_UNRELEASED") == "true":
            if requested:
                raise RuntimeError("An Unreleased entry cannot replace a preview")
            self.output(skip=True)
            return
        refs = self.refs()
        if not requested:
            self.output(skip=self.tag in refs)
            return
        if (os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
                or os.environ.get("GITHUB_REF") != "refs/heads/main"
                or os.environ.get("RELEASE_PREVIEW") == "true"):
            raise RuntimeError("Recutting requires a manual run on main with a stable changelog entry")
        if self.tag not in refs or self.branch not in refs or refs.get("refs/heads/main") != self.sha:
            raise RuntimeError("Expected the existing preview refs and the selected main commit")
        release = self.release()
        self.require_preview(release)
        self.directory.mkdir(parents=True, exist_ok=True)
        (self.directory / "state.json").write_text(json.dumps({"release": release, "refs": refs}, indent=2))
        self.output(skip=False, recut=True)

    def require_unchanged(self, state):
        current = self.release()
        self.require_preview(current)
        if fingerprint(current) != fingerprint(state["release"]) or self.refs() != state["refs"]:
            raise RuntimeError("The preview or its refs changed during validation; refusing to replace it")

    def verify_assets(self, release, directory):
        assets = {asset["name"]: asset for asset in release["assets"]}
        if sorted(assets) != self.names:
            raise RuntimeError("Release asset names do not match the four SDK artifacts")
        for name in self.names:
            contents = (directory / name).read_bytes()
            digest = "sha256:" + hashlib.sha256(contents).hexdigest()
            if (assets[name]["state"] != "uploaded" or assets[name]["size"] != len(contents)
                    or assets[name].get("digest") != digest):
                raise RuntimeError(f"Release asset verification failed: {name}")

    def push_refs(self, expected, desired):
        run("git", "push", "--atomic", "origin",
            f"--force-with-lease={self.tag}:{expected[self.tag]}",
            f"--force-with-lease={self.branch}:{expected[self.branch]}",
            f"{desired[self.tag]}:{self.tag}", f"{desired[self.branch]}:{self.branch}")

    def upload(self, directory):
        run("gh", "release", "upload", self.version, "--repo", self.repository, "--clobber",
            *(str(directory / name) for name in self.names))

    def published(self, release, desired, artifacts, body):
        if (release["name"] != f"Stash Native {self.version}" or release["body"] != body
                or release["tag_name"] != self.version or release["draft"] or release["prerelease"]
                or self.refs() != desired):
            return False
        self.verify_assets(release, artifacts)
        return self.api("releases/latest")["id"] == release["id"]

    def restore(self, state, desired, backup):
        current = self.release()
        self.require_preview(current, complete=False)
        if metadata(current) != metadata(state["release"]):
            raise RuntimeError("Release metadata changed; use the saved backup for recovery")
        current_refs = self.refs()
        if current_refs not in (desired, state["refs"]):
            raise RuntimeError("Release refs changed; use the saved backup for recovery")
        self.upload(backup)
        for asset in state["release"]["assets"]:
            if asset.get("label"):
                restored = next(item for item in self.release()["assets"] if item["name"] == asset["name"])
                self.api(f"releases/assets/{restored['id']}", {"label": asset["label"]})
        self.verify_assets(self.release(), backup)
        if current_refs == desired:
            self.push_refs(desired, state["refs"])
        if self.refs() != state["refs"]:
            raise RuntimeError("Preview refs were not restored")
        print("Restored the preview assets and refs")

    def publish(self):
        state = json.loads((self.directory / "state.json").read_text())
        self.require_unchanged(state)
        artifacts = Path(os.environ["RELEASE_ARTIFACTS"])
        for name in self.names:
            if not (artifacts / name).is_file():
                raise RuntimeError(f"Missing replacement artifact: {name}")
        body = Path(os.environ["RELEASE_BODY"]).read_text()
        backup = self.directory / "assets"
        backup.mkdir(exist_ok=True)
        run("gh", "release", "download", self.version, "--repo", self.repository,
            "--dir", str(backup), "--skip-existing")
        self.verify_assets(state["release"], backup)
        run("git", "bundle", "create", str(self.directory / "preview.bundle"), self.tag,
            f"refs/remotes/origin/release/{self.version}")
        run("git", "merge-base", "--is-ancestor", state["refs"][self.branch], self.sha)
        run("git", "merge-base", "--is-ancestor", state["refs"][self.tag], self.sha)
        run("git", "tag", "--force", "--annotate", self.version, self.sha, "--message", f"Release {self.version}")
        desired = {**state["refs"], self.tag: run("git", "rev-parse", self.tag), self.branch: self.sha}
        (self.directory / "replacement-refs.json").write_text(json.dumps(desired, indent=2))
        self.require_unchanged(state)
        promotion_started = False
        try:
            self.push_refs(state["refs"], desired)
            self.upload(artifacts)
            current = self.release()
            self.verify_assets(current, artifacts)
            if metadata(current) != metadata(state["release"]) or self.refs() != desired:
                raise RuntimeError("Release metadata or refs changed before promotion")
            promotion_started = True
            self.api(f"releases/{current['id']}", {
                "name": f"Stash Native {self.version}", "body": body,
                "draft": False, "prerelease": False, "make_latest": "true",
            })
            if not self.published(self.release(), desired, artifacts, body):
                raise RuntimeError("The release was not published as stable and Latest")
        except Exception:
            # A failed request may already have succeeded remotely. Read before recovery.
            current = self.release()
            if promotion_started and self.published(current, desired, artifacts, body):
                print("Verified stable publication after an uncertain response")
                return
            if self.refs() == state["refs"] and fingerprint(current) == fingerprint(state["release"]):
                raise
            self.restore(state, desired, backup)
            raise
        print(f"Published Stash Native {self.version} as stable and Latest at {self.sha}")


if __name__ == "__main__":
    release = Recut()
    if sys.argv[1:] == ["check"]:
        release.check()
    elif sys.argv[1:] == ["publish"]:
        release.publish()
    else:
        raise SystemExit("Usage: recut_preview.py check|publish")
