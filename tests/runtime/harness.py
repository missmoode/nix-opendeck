"""Process and filesystem mechanics for the nix-opendeck runtime scenario.

All test state stays under a temporary directory. Behavioural assertions live in
run.py; this module does not decide which application features need testing.
"""

from __future__ import annotations

import http.client
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote


PLUGIN_ID = "com.amansprojects.starterpack.sdPlugin"
BUS_NAME = "me.amankhanna.opendeck.SingleInstance"
PORTS_RE = re.compile(r"Using ports (\d+) and (\d+)")


class OpenDeckHarness:
    def __init__(self, package: Path, artifacts: Path | None = None):
        self.package = package.resolve()
        self.artifacts = artifacts
        self.temporary = tempfile.TemporaryDirectory(prefix="opendeck-runtime-")
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.config_base = self.root / "config"
        self.config = (
            self.home / "Library/Application Support/opendeck"
            if sys.platform == "darwin"
            else self.config_base / "opendeck"
        )
        self.process: subprocess.Popen | None = None
        self._stopped = False
        self.log_path = self.root / "opendeck.log"
        self.asset_port: int | None = None
        self.plugin_dir: Path | None = None
        self.environ = os.environ.copy()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        try:
            self.stop()
            if self.artifacts and self.log_path.exists():
                self.artifacts.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(self.log_path, self.artifacts / self.log_path.name)
        finally:
            self.temporary.cleanup()

    def prepare(self):
        if sys.platform not in ("linux", "darwin"):
            raise RuntimeError(f"Unsupported runtime platform: {sys.platform}")
        binary = self.package / "bin/opendeck"
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise RuntimeError(f"Packaged OpenDeck executable missing: {binary}")

        # Tauri's macOS single-instance mechanism is not isolated by a private
        # D-Bus session. Local macOS execution is intentionally fail-closed until
        # independently validated; hosted macOS CI machines are ephemeral.
        if sys.platform == "darwin" and not os.environ.get("GITHUB_ACTIONS"):
            raise RuntimeError("macOS runtime tests currently require an ephemeral GitHub Actions runner")

        for path in (
            self.home,
            self.config,
            self.root / "data",
            self.root / "cache",
            self.root / "runtime",
        ):
            path.mkdir(parents=True, exist_ok=True)
        (self.root / "runtime").chmod(0o700)

        self.environ.update({
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.config_base),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
            "TMPDIR": str(self.root),
        })
        if sys.platform == "darwin":
            self.environ["CFFIXED_USER_HOME"] = str(self.home)
        else:
            # The Nix runner supplies Xvfb and a private session bus.
            if not self.environ.get("DISPLAY") or not self.environ.get("DBUS_SESSION_BUS_ADDRESS"):
                raise RuntimeError("Linux runtime checks require the packaged Xvfb/D-Bus runner")
            self.environ.pop("WAYLAND_DISPLAY", None)
            self.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        # Nix names OpenDeck outputs <pname>-<version>. Keep the existing
        # settings version current to avoid the upstream upgrade dialog.
        version = self.package.name.rsplit("-", 1)[-1]
        settings = {
            "version": version,
            "disableelgato": True,
            "statistics": False,
            "updatecheck": False,
            "autolaunch": False,
            "developer": False,
            "background": False,
        }
        (self.config / "settings.json").write_text(json.dumps(settings) + "\n")

        # A managed-style symlink for asset authorization. There is deliberately
        # no manifest: no test plugin is executed, or even eligible for loading.
        outside = self.root / "external-plugin"
        (outside / "icons").mkdir(parents=True)
        (outside / "icons/test.svg").write_text("<svg xmlns='http://www.w3.org/2000/svg'></svg>\n")
        (self.config / "plugins").mkdir()
        (self.config / "plugins/runtime.assets.sdPlugin").symlink_to(outside, target_is_directory=True)
        (self.config / "local.svg").write_text("<svg xmlns='http://www.w3.org/2000/svg'/>\n")
        (self.root / "forbidden.svg").write_text("<svg>not authorized</svg>\n")
        self.plugin_dir = self._bundled_directory()

    def _bundled_directory(self) -> Path:
        if sys.platform == "darwin":
            return self.package / "Applications/OpenDeck.app/Contents/Resources/plugins"
        # Linux makeWrapper installs this exact variable in the launcher.
        wrapper = (self.package / "bin/opendeck").read_text()
        for line in wrapper.splitlines():
            if "OPENDECK_BUNDLED_PLUGINS_DIR=" not in line:
                continue
            for token in shlex.split(line):
                if token.startswith("OPENDECK_BUNDLED_PLUGINS_DIR="):
                    return Path(token.partition("=")[2])
        raise RuntimeError("Cannot locate OPENDECK_BUNDLED_PLUGINS_DIR in Linux launcher")

    def start(self):
        if self.process is not None:
            raise RuntimeError("OpenDeck is already started by this harness")
        # Run the actual .app executable on macOS to preserve its resource paths.
        executable = (
            self.package / "Applications/OpenDeck.app/Contents/MacOS/opendeck"
            if sys.platform == "darwin" else self.package / "bin/opendeck"
        )
        # File output needs no reader thread, shared buffer or output draining.
        with self.log_path.open("w") as log:
            self.process = subprocess.Popen(
                [str(executable), "--hide"],
                env=self.environ,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )

    def log_count(self, needle: str) -> int:
        return sum(needle in line for line in self.log_path.read_text(errors="replace").splitlines())

    def wait_until(self, predicate, label: str, *, timeout: float = 30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.process is not None and self.process.poll() is not None:
                raise AssertionError(f"OpenDeck exited {self.process.returncode} while awaiting {label}")
            result = predicate()
            if result:
                return result
            time.sleep(0.1)
        raise AssertionError(f"Timed out waiting for {label}")

    def wait_ready(self):
        def ports():
            match = PORTS_RE.search(self.log_path.read_text(errors="replace"))
            return int(match.group(2)) if match else None

        self.asset_port = self.wait_until(ports, "OpenDeck port selection")
        self.wait_until(lambda: self._tcp_available(self.asset_port), "asset server listening")
        return True

    def wait_bus_name(self):
        return self.wait_until(self._owns_bus_name, "private D-Bus single-instance name")

    def is_running(self):
        return self.process is not None and self.process.poll() is None

    @staticmethod
    def _tcp_available(port):
        import socket
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                return True
        except OSError:
            return False

    def _owns_bus_name(self):
        result = subprocess.run(
            ["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus",
             "--object-path", "/org/freedesktop/DBus", "--method",
             "org.freedesktop.DBus.NameHasOwner", BUS_NAME],
            capture_output=True, text=True, timeout=3, env=self.environ,
        )
        return result.returncode == 0 and "(true,)" in result.stdout

    def request(self, path: Path):
        if self.asset_port is None:
            raise RuntimeError("Asset server is not ready")
        connection = http.client.HTTPConnection("127.0.0.1", self.asset_port, timeout=5)
        try:
            connection.request("GET", quote(str(path), safe="/"))
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def wait_registered(self, plugin_id: str, count: int = 1):
        return self.wait_until(
            lambda: self.log_count(f"Registered plugin {plugin_id}") >= count,
            f"registration of {plugin_id} (count {count})",
        )

    def command(self, *args: str, timeout: int = 20):
        return subprocess.run(
            [str(self.package / "bin/opendeck"), *args],
            env=self.environ, capture_output=True, text=True, timeout=timeout,
        )

    def stop(self):
        if self.process is None or self._stopped:
            return
        # Only signal this process group once: it may survive its leader, but
        # its ID can eventually be reused after the group disappears.
        self._stopped = True
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.process.wait(timeout=5)
        # Keep the original handle for post-stop assertions.

    def assert_no_instance(self):
        if self.is_running():
            return False
        if sys.platform == "linux" and self._owns_bus_name():
            return False
        # Detect a lingering listener without inspecting unrelated processes.
        # The inactive CLI command is also run synchronously with a timeout.
        return self.asset_port is None or not self._tcp_available(self.asset_port)
