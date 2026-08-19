import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from scripts.publish import parse_version, verify_release_directory


class PublishTests(unittest.TestCase):
    def test_version_is_strict(self):
        self.assertEqual(parse_version("1.2.3"), "1.2.3")
        with self.assertRaises(ValueError):
            parse_version("v1.2.3")

    def test_release_directory_rejects_modified_asset(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = {
                "FieldViz_1.2.3_x64_Setup.exe": b"installer",
                "latest.json": json.dumps(
                    {
                        "version": "1.2.3",
                        "platforms": {
                            "windows-x86_64": {
                                "url": "https://github.com/AnatoForge/fieldviz_desktop/releases/download/v1.2.3/FieldViz_1.2.3_x64_Setup.exe"
                            }
                        },
                    }
                ).encode(),
                "latest.json.sig": b"signature",
            }
            assets = {}
            for name, contents in files.items():
                (root / name).write_bytes(contents)
                assets[name] = {
                    "size": len(contents),
                    "sha256": hashlib.sha256(contents).hexdigest(),
                }
            (root / "release-state.json").write_text(
                json.dumps({"version": "1.2.3", "sourceTag": "v1.2.3", "assets": assets}),
                encoding="utf-8",
            )
            self.assertEqual(len(verify_release_directory("1.2.3", root)), 3)
            (root / "latest.json.sig").write_bytes(b"modified")
            with self.assertRaises(RuntimeError):
                verify_release_directory("1.2.3", root)


if __name__ == "__main__":
    unittest.main()
