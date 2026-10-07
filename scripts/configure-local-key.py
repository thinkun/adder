#!/usr/bin/env python3
"""Collect the development SDK key in a private Mac dialog, never stdout."""
import os
import plistlib
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
dialog = 'text returned of (display dialog "Paste your Melange development Personal Access Token. It will be embedded only in your local Adder build and excluded from Git." default answer "" with hidden answer buttons {"Cancel", "Save locally"} default button "Save locally" with title "Adder build setup")'
result = subprocess.run(["osascript", "-e", dialog], capture_output=True, text=True)
if result.returncode:
    raise SystemExit("Key setup cancelled. No credential was changed.")
key = result.stdout.strip()
if not key.startswith("ztp_") or any(c.isspace() for c in key):
    raise SystemExit("Expected a Melange Personal Access Token. No credential was saved.")
directory = root / ".secrets"
directory.mkdir(exist_ok=True, mode=0o700)
path = directory / "MelangeConfig.plist"
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "wb") as stream:
    plistlib.dump({"PersonalKey": key}, stream)
path.chmod(0o600)
print("Development key saved to ignored local build configuration. Its value was not printed.")
