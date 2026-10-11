"""Download-channel regression; uses existing public facts and no network or GUI."""
from importlib import import_module
from pathlib import Path
import json
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
release_tools = import_module("package-release")
site = import_module("build-site")


class ReleaseSiteTests(unittest.TestCase):
    def setUp(self):
        self.release = {"product": "Folio", "version": "1.2.1", "build": "128",
                        "filename": "Folio-1.2.1-128-arm64.zip", "sha256": "a" * 64,
                        "bytes": 3643010, "source_commit": "b" * 40, "signature": "adhoc",
                        "notarized": False, "download_url": "downloads/Folio-1.2.1-128-arm64.zip"}

    def test_public_metadata_preserves_facts_and_omits_internal_records(self):
        self.release.update(receipt={"log": "/Users/private/test.log"}, internal_token="secret")
        public = release_tools.public_metadata(self.release)
        self.assertNotIn("receipt", public)
        self.assertNotIn("internal_token", public)
        for key in ("bytes", "sha256", "source_commit", "signature", "notarized"):
            self.assertEqual(public[key], self.release[key])
        self.assertEqual(public["download_url"],
                         "https://github.com/zengtianli/tl-markdown/releases/download/v1.2.1-128/Folio-1.2.1-128-arm64.zip")
        self.assertTrue(public["checksum_url"].endswith("/v1.2.1-128/SHA256SUMS.txt"))
        self.assertEqual(self.release["download_url"], "downloads/Folio-1.2.1-128-arm64.zip")

    def test_site_rejects_installer_even_when_allowlisted_but_keeps_tutorial_samples(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "site-manifest.json").write_text("{}")
            sample = root / "tutorial-example.zip"
            sample.write_bytes(b"sample")
            manifest = {"files": [{"path": sample.name}]}
            site.validate_file_set(root, manifest)
            installer = root / self.release["filename"]
            installer.write_bytes(b"installer")
            manifest["files"].append({"path": installer.name})
            with self.assertRaisesRegex(AssertionError, "GitHub Releases"):
                site.validate_file_set(root, manifest)


if __name__ == "__main__":
    unittest.main()
