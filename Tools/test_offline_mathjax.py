import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import prepare_offline_mathjax as assets


class ArchiveSafetyTests(unittest.TestCase):
    def archive(self, name, kind=tarfile.REGTYPE, content=b"x"):
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode="w:gz") as archive:
            entry = tarfile.TarInfo(name)
            entry.type = kind
            entry.size = len(content) if kind == tarfile.REGTYPE else 0
            entry.linkname = "../../outside"
            archive.addfile(entry, io.BytesIO(content))
        return output.getvalue()

    def test_rejects_traversal_absolute_paths_and_links(self):
        cases = [("package/../../outside", tarfile.REGTYPE),
                 ("/absolute", tarfile.REGTYPE),
                 ("package/config/link", tarfile.SYMTYPE),
                 ("package/config/link", tarfile.LNKTYPE)]
        for name, kind in cases:
            with self.subTest(name=name, kind=kind):
                with tempfile.TemporaryDirectory() as directory:
                    with self.assertRaises(ValueError):
                        assets.extract_assets(self.archive(name, kind),
                                              Path(directory))
                    self.assertEqual(list(Path(directory).iterdir()), [])

    def test_rejects_incomplete_distribution(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                assets.extract_assets(self.archive("package/MathJax.js"),
                                      Path(directory))

    def test_checksum_failure_preserves_previous_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "Offline"
            output.mkdir()
            (output / "verified").write_text("previous")
            archive = root / "bad.tgz"
            archive.write_bytes(b"tampered")
            with patch.object(assets, "OUTPUT", output):
                with self.assertRaises(ValueError):
                    assets.prepare(archive)
            self.assertEqual((output / "verified").read_text(), "previous")


if __name__ == "__main__":
    unittest.main()
