#!/usr/bin/env python3
"""Copy an ignored development config into the app before code signing."""
import os
import plistlib
import shutil
from pathlib import Path

root = Path(os.environ["SRCROOT"])
source = root / ".secrets" / "MelangeConfig.plist"
target = Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["UNLOCALIZED_RESOURCES_FOLDER_PATH"] / "MelangeConfig.plist"
if source.is_file():
    with source.open("rb") as stream:
        config = plistlib.load(stream)
    key = config.get("PersonalKey", "")
    if not isinstance(key, str) or not key.startswith("ztp_"):
        raise SystemExit("Invalid private SDK configuration. Configure the development key on your Mac.")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    print("Embedded private development SDK configuration.")
else:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(plistlib.dumps({}))
    print("No private SDK key configured; the app will show Mac setup instructions.")
