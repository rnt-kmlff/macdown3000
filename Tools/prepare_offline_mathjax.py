#!/usr/bin/env python3
"""Prepare hash-pinned MathJax assets; never run package install scripts."""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile
import tempfile
import urllib.request

URL = "https://registry.npmjs.org/mathjax/-/mathjax-2.7.9.tgz"
SHA256 = "7131e739848edc14aa661a5516995866b81a477fab8b039d7cc324930e71f786"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "MacDown/Resources/MathJax/Offline"
ASSETS = {"MathJax.js", "config", "extensions", "fonts", "jax",
          "localization", "LICENSE"}


def extract_assets(data, destination):
    """Reject unsafe archives before writing outside a fresh staging folder."""
    total = 0
    count = 0
    hashes = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            count += 1
            path = PurePosixPath(member.name)
            if (count > 5000 or path.is_absolute() or ".." in path.parts
                    or not path.parts or path.parts[0] != "package"
                    or not (member.isdir() or member.isfile())):
                raise ValueError("Unsafe MathJax archive entry")
            total += member.size
            if total > 80 * 1024 * 1024:
                raise ValueError("MathJax archive exceeds its size budget")
            relative = PurePosixPath(*path.parts[1:])
            if (not member.isfile() or not relative.parts
                    or relative.parts[0] not in ASSETS):
                continue
            content = archive.extractfile(member).read()
            target = destination.joinpath(*relative.parts)
            if str(relative) in hashes:
                raise ValueError("Duplicate MathJax archive entry")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            hashes[str(relative)] = hashlib.sha256(content).hexdigest()
    required = {"MathJax.js", "config/TeX-AMS-MML_HTMLorMML.js",
                "jax/input/TeX/jax.js", "jax/output/HTML-CSS/jax.js"}
    if not required.issubset(hashes):
        raise ValueError("Incomplete MathJax distribution")
    return hashes


def prepare(archive_path=None):
    if archive_path:
        with open(archive_path, "rb") as source:
            data = source.read(24 * 1024 * 1024 + 1)
    else:
        with urllib.request.urlopen(URL, timeout=60) as source:
            data = source.read(24 * 1024 * 1024 + 1)
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError("MathJax archive checksum mismatch")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".Offline-", dir=OUTPUT.parent) as tmp:
        staging = Path(tmp) / "new"
        staging.mkdir()
        hashes = extract_assets(data, staging)
        receipt = {"version": "2.7.9", "source": URL,
                   "archive_sha256": SHA256, "files": hashes}
        (staging / "manifest.json").write_text(
            json.dumps(receipt, sort_keys=True, indent=2) + "\n")
        backup = Path(tmp) / "previous"
        if OUTPUT.exists():
            OUTPUT.rename(backup)
        try:
            staging.rename(OUTPUT)
        except Exception:
            if backup.exists():
                backup.rename(OUTPUT)
            raise
    print(f"Verified offline MathJax 2.7.9: {len(hashes)} assets")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    prepare(parser.parse_args().archive)
