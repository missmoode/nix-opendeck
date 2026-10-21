#!/usr/bin/env python3
"""Update one native system's Deno FOD hash, using the package's own metadata.

Called by a package's passthru.updatePlatformDeps; CI does not need to know
which packages use Deno or where their hashes are stored.
"""

import argparse
import base64
from collections import deque
import json
from pathlib import Path
import re
import subprocess
import sys

HASH = r"sha256-[A-Za-z0-9+/]{43}="
MISMATCH = re.compile(
    r"hash mismatch in fixed-output derivation '(?P<drv>[^']+)':\s*"
    r"specified:\s*(?P<expected>" + HASH + r")\s*"
    r"got:\s*(?P<actual>" + HASH + r")"
)
HASH_MAP = re.compile(
    r"outputHash\s*=\s*\{(?P<body>[^{}]+)\}\s*"
    r"\.\$\{stdenv\.hostPlatform\.system\}\s*;",
    re.S,
)


def check_hash(value):
    if not re.fullmatch(HASH, value):
        raise ValueError("unexpected hash format")
    if len(base64.b64decode(value.removeprefix("sha256-"), validate=True)) != 32:
        raise ValueError("expected SHA-256 hash")


def build_deps(attr):
    cmd = ["nix", "build", "--no-link", "-L", f".#{attr}.denoDeps"]
    print("+", " ".join(cmd), flush=True)
    tail = deque(maxlen=300)
    with subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, errors="replace",
    ) as proc:
        for line in proc.stdout:
            print(line, end="", flush=True)
            tail.append(line)
        return_code = proc.wait()
    return return_code, "".join(tail)


def repair(source_file, system, derivation_name, output):
    candidates = [
        m for m in MISMATCH.finditer(output)
        if re.fullmatch(
            r"[0-9a-z]{32}-" + re.escape(derivation_name) + r"-.+\.drv",
            Path(m.group("drv")).name,
        )
    ]
    if len(candidates) != 1:
        raise ValueError("failure was not a single, recognised Deno dependency hash mismatch")

    expected, actual = candidates[0].group("expected", "actual")
    check_hash(expected)
    check_hash(actual)
    source = Path(source_file)
    original = source.read_text()
    matches = list(HASH_MAP.finditer(original))
    if len(matches) != 1:
        raise ValueError(f"expected exactly one platform outputHash map in {source}")
    match = matches[0]
    entry = re.compile(
        r"(?m)^[ \t]*" + re.escape(system) + r"\s*=\s*\"" + HASH + r"\"\s*;"
    )
    items = list(entry.finditer(match.group("body")))
    if len(items) != 1:
        raise ValueError(f"expected exactly one {system} hash in {source}")
    item = items[0]
    old_line = item.group()
    if old_line.count(expected) != 1:
        raise ValueError("reported expected hash does not match selected platform entry")
    new_line = old_line.replace(expected, actual)
    if original.count(old_line) != 1:
        raise ValueError("source edit is not unique")
    source.write_text(original.replace(old_line, new_line, 1))
    return {"path": source.as_posix(), "before": old_line, "after": new_line}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attr", required=True, help="flake attribute of the package")
    parser.add_argument("--package", required=True, help="pname of the denoDeps derivation")
    parser.add_argument("--file", required=True, help="relative source file in the checkout")
    parser.add_argument("--system", required=True)
    parser.add_argument("--output", required=True, help="JSON record of source edits")
    args = parser.parse_args()
    output = Path(args.output)
    rc, log = build_deps(args.attr)
    if rc == 0:
        output.write_text("[]\n")
        return 0
    try:
        edit = repair(args.file, args.system, args.package, log)
    except (ValueError, OSError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 1
    rc, _ = build_deps(args.attr)
    if rc:
        print("::error::Deno dependency build still failed after hash correction", file=sys.stderr)
        return 1
    output.write_text(json.dumps([edit], indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
