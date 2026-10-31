
#!/usr/bin/env python3
"""Update one Hyprstream plugin from the latest GitHub Release."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote
from urllib.request import Request, urlopen

PLUGIN_IDS = {
    "hyprstream": "com.danmaxis.hyprstream.sdPlugin",
    "hyprstream-media": "com.danmaxis.hyprstream.media.sdPlugin",
    "hyprstream-monitors": "com.danmaxis.hyprstream.monitors.sdPlugin",
}

REPO = "danmaxis/hyprstream"
API = f"https://api.github.com/repos/{REPO}"


def fetch_json(url):
    headers = {
        "User-Agent": "nix-opendeck-updater",
        "Accept": "application/vnd.github+json",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"

    with urlopen(Request(url, headers=headers), timeout=30) as response:
        return json.load(response)


def manifest_version(value):
    # Elgato manifests use four components, often ending in .0.
    parts = value.split(".")
    if len(parts) == 4 and parts[-1] == "0":
        parts.pop()
    version = ".".join(parts)

    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2,3}", version):
        raise ValueError(f"Unexpected manifest version: {value}")

    return version


def version_parts(value):
    return tuple(map(int, value.split(".")))


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in PLUGIN_IDS:
        raise SystemExit(f"Usage: {sys.argv[0]} <{'|'.join(PLUGIN_IDS)}>")

    name = sys.argv[1]
    attr = os.environ["UPDATE_NIX_ATTR_PATH"]

    if not attr.endswith(f".opendeck-plugins.danmaxis.{name}"):
        raise ValueError(f"Unexpected update target: {attr}")

    package_file = Path(f"src/packages/plugins/danmaxis/{name}/default.nix")
    contents = package_file.read_text()

    version_pattern = r'(?m)^([ \t]*version = ")([0-9.]+)(";)$'
    revision_pattern = r'(?m)^([ \t]*rev = ")([0-9a-f]{40})(";)$'

    versions = re.findall(version_pattern, contents)
    revisions = re.findall(revision_pattern, contents)

    if len(versions) != 1 or len(revisions) != 1:
        raise ValueError(f"Unexpected derivation format: {package_file}")

    old_version = versions[0][1]

    release = fetch_json(f"{API}/releases/latest")
    tag = release["tag_name"]
    commit = fetch_json(f"{API}/commits/{quote(tag, safe='')}")["sha"]

    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError(f"Unexpected commit SHA: {commit}")

    plugin_id = PLUGIN_IDS[name]
    manifest_path = f"packages/{name}/{plugin_id}/manifest.json"
    manifest = fetch_json(
        f"https://raw.githubusercontent.com/{REPO}/{commit}/{manifest_path}"
    )
    new_version = manifest_version(manifest["Version"])

    if version_parts(new_version) <= version_parts(old_version):
        print(f"{name}: already at {old_version} or newer")
        return

    contents, count = re.subn(
        version_pattern,
        lambda m: f'{m[1]}{new_version}{m[3]}',
        contents,
    )
    if count != 1:
        raise ValueError("Could not update version")

    contents, count = re.subn(
        revision_pattern,
        lambda m: f'{m[1]}{commit}{m[3]}',
        contents,
    )
    if count != 1:
        raise ValueError("Could not update revision")

    package_file.write_text(contents)

    print(f"{name}: {old_version} -> {new_version} ({tag})", flush=True)

    # Refresh the pinned source hash and npmDepsHash without changing
    # the version or revision we selected from upstream's manifest.
    subprocess.run(
        ["nix-update", attr, "--flake", "--version=skip"],
        check=True,
    )


if __name__ == "__main__":
    main()
