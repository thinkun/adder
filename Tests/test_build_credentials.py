"""Test the real build phase with synthetic credentials only."""
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "embed-local-key.py"


class PrivateBuildConfiguration(unittest.TestCase):
    def test_embed_then_remove_without_echoing_key(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            secret = root / ".secrets" / "MelangeConfig.plist"
            secret.parent.mkdir()
            synthetic = "ztp_TEST_ONLY_NOT_A_REAL_CREDENTIAL"
            secret.write_bytes(plistlib.dumps({"PersonalKey": synthetic}))
            env = {**os.environ, "SRCROOT": str(root), "TARGET_BUILD_DIR": str(root / "products"), "UNLOCALIZED_RESOURCES_FOLDER_PATH": "Adder.app"}
            first = subprocess.run(["python3", str(SCRIPT)], env=env, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0)
            self.assertNotIn(synthetic, first.stdout + first.stderr)
            target = root / "products" / "Adder.app" / "MelangeConfig.plist"
            self.assertEqual(plistlib.loads(target.read_bytes())["PersonalKey"], synthetic)
            secret.unlink()
            second = subprocess.run(["python3", str(SCRIPT)], env=env, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0)
            self.assertNotIn("PersonalKey", plistlib.loads(target.read_bytes()), "A later build without local config must not retain the previous key")

    def test_invalid_configuration_fails_without_echoing_value(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            secret = root / ".secrets" / "MelangeConfig.plist"
            secret.parent.mkdir()
            synthetic = "invalid_SYNTHETIC_SECRET"
            secret.write_bytes(plistlib.dumps({"PersonalKey": synthetic}))
            env = {**os.environ, "SRCROOT": str(root), "TARGET_BUILD_DIR": str(root / "products"), "UNLOCALIZED_RESOURCES_FOLDER_PATH": "Adder.app"}
            result = subprocess.run(["python3", str(SCRIPT)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(synthetic, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
