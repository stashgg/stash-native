import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from recut_preview import Recut, run


def asset(name, contents):
    return {"id": name, "name": name, "label": "", "size": len(contents), "state": "uploaded",
            "digest": "sha256:" + hashlib.sha256(contents).hexdigest(), "updated_at": "before"}


class FakeRecut(Recut):
    def __init__(self):
        super().__init__()
        self.remote_refs = {self.tag: "b" * 40, self.branch: "a" * 40, "refs/heads/main": self.sha}
        self.contents = {name: b"preview" for name in self.names}
        self.remote_release = {
            "id": 123, "tag_name": self.version, "name": "Stash Native 3.0.0 (Preview)",
            "body": "Preview notes", "target_commitish": "main", "draft": False,
            "prerelease": True, "immutable": False, "updated_at": "before",
            "assets": [asset(name, data) for name, data in self.contents.items()],
        }
        self.uploads = 0
        self.promotions = 0
        self.fail_upload = False
        self.corrupt_upload = False
        self.lose_promotion_response = False

    def api(self, path, payload=None):
        if payload:
            self.promotions += 1
            self.remote_release.update({key: value for key, value in payload.items() if key != "make_latest"})
            if self.lose_promotion_response:
                raise RuntimeError("Lost promotion response")
        return copy.deepcopy(self.remote_release)

    def refs(self):
        return self.remote_refs.copy()

    def push_refs(self, expected, desired):
        if self.remote_refs != expected:
            raise RuntimeError("Lease failed")
        self.remote_refs = desired.copy()

    def upload(self, directory):
        self.uploads += 1
        if self.fail_upload and self.uploads == 1:
            del self.contents[self.names[0]]
            self.remote_release["assets"] = [asset(name, data) for name, data in self.contents.items()]
            raise RuntimeError("Upload interrupted after deleting an old asset")
        self.contents = {name: (directory / name).read_bytes() for name in self.names}
        if self.corrupt_upload and self.uploads == 1:
            self.contents[self.names[0]] = b"corrupt"
        self.remote_release["assets"] = [asset(name, data) for name, data in self.contents.items()]

    def command(self, *args, **kwargs):
        if args[:3] == ("gh", "release", "download"):
            directory = Path(args[args.index("--dir") + 1])
            for name, data in self.contents.items():
                (directory / name).write_bytes(data)
        elif args[:2] == ("git", "rev-parse"):
            return "d" * 40
        return ""


class RecutTests(unittest.TestCase):
    def setUp(self):
        root = Path(os.environ.get("HS_TEMP", Path.home() / "Temp"))
        root.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=root, prefix="recut-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        environment = patch.dict(os.environ, {
            "HS_TEMP": str(self.root), "VERSION": "3.0.0", "GITHUB_REPOSITORY": "example/sdk",
            "GITHUB_SHA": "c" * 40, "GITHUB_OUTPUT": str(self.root / "outputs"),
            "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main",
            "RECUT_PREVIEW": "true", "RELEASE_UNRELEASED": "", "RELEASE_PREVIEW": "",
            "RELEASE_ARTIFACTS": str(self.root / "artifacts"), "RELEASE_BODY": str(self.root / "body"),
        })
        environment.start()
        self.addCleanup(environment.stop)
        self.release = FakeRecut()

    def prepare(self):
        self.release.check()
        artifacts = self.root / "artifacts"
        artifacts.mkdir()
        for name in self.release.names:
            (artifacts / name).write_bytes(b"stable")
        (self.root / "body").write_text("Stable release notes")
        self.original = copy.deepcopy(self.release.remote_release)
        self.original_refs = self.release.refs()

    def publish(self):
        with patch("recut_preview.run", side_effect=self.release.command):
            self.release.publish()

    def assert_restored(self):
        self.assertTrue(self.release.remote_release["prerelease"])
        self.assertEqual(self.release.remote_release["body"], self.original["body"])
        self.assertEqual(self.release.refs(), self.original_refs)
        self.assertEqual(self.release.contents, {name: b"preview" for name in self.release.names})
        self.assertEqual(self.release.promotions, 0)

    def test_existing_tag_skips_without_explicit_recut(self):
        os.environ["RECUT_PREVIEW"] = "false"
        self.release.remote_release["prerelease"] = False
        self.release.check()
        self.assertEqual((self.root / "outputs").read_text(), "skip=true\nrecut=false\n")
        self.assertFalse(self.release.directory.exists())

    def test_new_version_keeps_normal_release_path(self):
        os.environ["RECUT_PREVIEW"] = "false"
        del self.release.remote_refs[self.release.tag]
        self.release.check()
        self.assertEqual((self.root / "outputs").read_text(), "skip=false\nrecut=false\n")

    def test_mutable_preview_is_eligible(self):
        self.release.check()
        self.assertEqual((self.root / "outputs").read_text(), "skip=false\nrecut=true\n")
        state = json.loads((self.release.directory / "state.json").read_text())
        self.assertEqual(state["refs"], self.release.refs())
        self.assertEqual(state["release"]["id"], 123)

    def test_stable_draft_and_immutable_releases_are_rejected(self):
        for field, value in (("prerelease", False), ("draft", True), ("immutable", True)):
            with self.subTest(field=field):
                original = self.release.remote_release[field]
                self.release.remote_release[field] = value
                with self.assertRaisesRegex(RuntimeError, "mutable prerelease"):
                    self.release.check()
                self.release.remote_release[field] = original

    def test_recut_requires_manual_main_and_stable_changelog(self):
        for field, value in (("GITHUB_EVENT_NAME", "push"), ("GITHUB_REF", "refs/heads/feature"),
                             ("RELEASE_PREVIEW", "true"), ("RELEASE_UNRELEASED", "true")):
            with self.subTest(field=field), patch.dict(os.environ, {field: value}):
                with self.assertRaises(RuntimeError):
                    self.release.check()

    def test_missing_preview_refs_and_moved_main_are_rejected(self):
        original = self.release.refs()
        for ref in (self.release.tag, self.release.branch, "refs/heads/main"):
            with self.subTest(ref=ref):
                self.release.remote_refs = {key: value for key, value in original.items() if key != ref}
                with self.assertRaises(RuntimeError):
                    self.release.check()

    def test_changed_release_is_not_overwritten(self):
        self.prepare()
        self.release.remote_release["body"] = "Edited during validation"
        with self.assertRaisesRegex(RuntimeError, "changed during validation"):
            self.publish()
        self.assertEqual(self.release.uploads, 0)
        self.assertEqual(self.release.refs(), self.original_refs)

    def test_changed_refs_are_not_overwritten(self):
        self.prepare()
        self.release.remote_refs[self.release.branch] = "e" * 40
        with self.assertRaisesRegex(RuntimeError, "changed during validation"):
            self.publish()
        self.assertEqual(self.release.uploads, 0)
        self.assertEqual(self.release.remote_refs[self.release.branch], "e" * 40)

    def test_partial_upload_restores_missing_asset_and_original_refs(self):
        self.prepare()
        self.release.fail_upload = True
        with self.assertRaisesRegex(RuntimeError, "Upload interrupted"):
            self.publish()
        self.assert_restored()

    def test_rejected_ref_push_does_not_reupload_unchanged_assets(self):
        self.prepare()
        with patch.object(self.release, "push_refs", side_effect=RuntimeError("Push denied")):
            with self.assertRaisesRegex(RuntimeError, "Push denied"):
                self.publish()
        self.assertEqual(self.release.uploads, 0)
        self.assert_restored()

    def test_corrupt_upload_is_not_promoted(self):
        self.prepare()
        self.release.corrupt_upload = True
        with self.assertRaisesRegex(RuntimeError, "verification failed"):
            self.publish()
        self.assert_restored()

    def test_success_promotes_all_four_rebuilt_assets(self):
        self.prepare()
        self.publish()
        self.assertFalse(self.release.remote_release["prerelease"])
        self.assertEqual(self.release.contents, {name: b"stable" for name in self.release.names})
        self.assertEqual(self.release.refs()[self.release.branch], self.release.sha)
        self.assertEqual(self.release.promotions, 1)

    def test_uncertain_promotion_is_verified_without_repeating_write(self):
        self.prepare()
        self.release.lose_promotion_response = True
        self.publish()
        self.assertFalse(self.release.remote_release["prerelease"])
        self.assertEqual(self.release.uploads, 1)
        self.assertEqual(self.release.promotions, 1)

    def test_atomic_push_rejects_stale_tag_without_advancing_branch(self):
        remote = self.root / "remote.git"
        source = self.root / "source"
        run("git", "init", "--bare", str(remote))
        run("git", "init", str(source))

        def git(*args):
            return run("git", "-C", str(source), *args)

        git("config", "user.name", "Release test")
        git("config", "user.email", "release@example.invalid")
        git("commit", "--allow-empty", "-m", "Preview")
        original = git("rev-parse", "HEAD")
        git("remote", "add", "origin", str(remote))
        git("push", "origin", f"HEAD:{self.release.branch}", f"HEAD:{self.release.tag}")
        git("commit", "--allow-empty", "-m", "Stable")
        replacement = git("rev-parse", "HEAD")
        expected = {self.release.branch: original, self.release.tag: "f" * 40}
        desired = {self.release.branch: replacement, self.release.tag: replacement}
        real_run = run
        with patch("recut_preview.run", side_effect=lambda *args: real_run("git", "-C", str(source), *args[1:])):
            with self.assertRaises(RuntimeError):
                Recut.push_refs(self.release, expected, desired)
        refs = git("ls-remote", "origin", self.release.tag, self.release.branch)
        self.assertEqual([line.split()[0] for line in refs.splitlines()], [original, original])


if __name__ == "__main__":
    unittest.main()
