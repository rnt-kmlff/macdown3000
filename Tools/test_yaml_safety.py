#!/usr/bin/env python3
"""Run the actual bounded YAML guard with the pinned C parser and sanitizers."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main(archive_path):
    spec = json.loads((ROOT / "Dependency/LibYAML/LibYAML.podspec.json").read_text())
    with tempfile.TemporaryDirectory(prefix="macdown-yaml-test-") as tmp:
        tmp = Path(tmp)
        archive = tmp / "source.tar.gz"
        if archive_path:
            data = archive_path.read_bytes()
        else:
            with urllib.request.urlopen(spec["source"]["http"], timeout=60) as source:
                data = source.read(2 * 1024 * 1024)
        if hashlib.sha256(data).hexdigest() != spec["source"]["sha256"]:
            raise ValueError("LibYAML source checksum mismatch")
        archive.write_bytes(data)
        with tarfile.open(archive) as tar:
            for member in tar:
                path = PurePosixPath(member.name)
                if (path.is_absolute() or ".." in path.parts
                        or not (member.isdir() or member.isfile())):
                    raise ValueError("Unsafe LibYAML archive")
                target = tmp.joinpath(*path.parts)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(tar.extractfile(member).read())
        source = tmp / "yaml-0.2.5"
        binary = tmp / "yaml-safety-tests"
        args = ["clang", "-std=c99", "-g", "-O1",
                "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                '-DYAML_VERSION_STRING="0.2.5"', "-DYAML_VERSION_MAJOR=0",
                "-DYAML_VERSION_MINOR=2", "-DYAML_VERSION_PATCH=5",
                "-I" + str(source / "include"), "-I" + str(source / "src"),
                *map(str, sorted((source / "src").glob("*.c"))),
                str(ROOT / "Tools/yaml_safety_tests.c"), "-o", str(binary)]
        subprocess.run(args, check=True, timeout=120)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    main(parser.parse_args().archive)
