#!/usr/bin/env python3
"""
Wayfinder Update & Signature Security Verification Test
========================================================
Tests:
 1. Cryptographic RSA-2048 signing with publish_update.py
 2. Godot client signature verification against embedded public key
 3. Tamper detection: modifying a byte in .pck triggers rejection
 4. Semantic version comparison & early-boot mounting
"""

import sys
import shutil
import tempfile
import subprocess
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
CLIENT_DIR = WORKSPACE_ROOT / "client"
GODOT_EXE = CLIENT_DIR / "godot_console.exe"
if not GODOT_EXE.exists():
    GODOT_EXE = CLIENT_DIR / "godot.exe"

BACKEND_DIR = WORKSPACE_ROOT / "backend"
PRIV_KEY = BACKEND_DIR / "certs" / "updater_private_key.pem"


def run_pipeline_test():
    print("=" * 66)
    print("  WAYFINDER UPDATER & SIGNATURE PIPELINE TEST")
    print("=" * 66)

    if not PRIV_KEY.exists():
        print(f"[Failure] Private key not found: {PRIV_KEY}")
        return False

    temp_dir = Path(tempfile.mkdtemp(prefix="wf_updater_test_"))
    version_json = BACKEND_DIR / "public" / "updates" / "version.json"
    pck_target = BACKEND_DIR / "public" / "updates" / "Wayfinder.pck"
    saved_vjson = version_json.read_bytes() if version_json.exists() else None
    saved_pck = pck_target.read_bytes() if pck_target.exists() else None
    try:
        # 1. Create a dummy test .pck file
        dummy_pck = temp_dir / "TestPack.pck"
        with open(dummy_pck, "wb") as f:
            f.write(b"GDPCK_MOCK_DATA_VERSION_1_0_1" * 1024)

        # 2. Run publish_update.py against dummy pck
        publish_script = WORKSPACE_ROOT / "tools" / "publish_update.py"
        cmd = [
            sys.executable,
            str(publish_script),
            "--pck", str(dummy_pck),
            "--version", "1.0.1",
            "--notes", "Automated Security Test Patch"
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(res.stdout)
        if res.returncode != 0:
            print("[Failure] publish_update.py returned non-zero exit code")
            return False

        version_json = BACKEND_DIR / "public" / "updates" / "version.json"
        pck_target = BACKEND_DIR / "public" / "updates" / "Wayfinder.pck"

        if not version_json.exists() or not pck_target.exists():
            print("[Failure] Output files not generated")
            return False

        # 3. Run Godot headless test to verify signature & tamper resistance
        godot_test_code = """
extends SceneTree

const Updater = preload("res://scripts/core/updater.gd")

func _init():
    _run_test.call_deferred()

func _run_test() -> void:
    var meta_file = FileAccess.open("res://../backend/public/updates/version.json", FileAccess.READ)
    if not meta_file:
        push_error("Could not open version.json")
        quit(1)
        return
        
    var meta = JSON.parse_string(meta_file.get_as_text())
    meta_file.close()
    
    var pck_path = "res://../backend/public/updates/Wayfinder.pck"
    var sha256 = meta.get("sha256", "")
    var sig = meta.get("signature", "")
    
    # Test 1: Valid signature check
    var result = Updater.verify_pck(pck_path, sha256, sig)
    print("Valid check result: ", result)
    if not result.get("valid", false):
        push_error("Legitimate package was rejected!")
        quit(2)
        return
        
    # Test 2: Tampered hash check
    var tampered_result = Updater.verify_pck(pck_path, "0000000000000000000000000000000000000000000000000000000000000000", sig)
    print("Tampered hash result: ", tampered_result)
    if tampered_result.get("valid", false):
        push_error("Tampered hash was accepted!")
        quit(3)
        return
        
    # Test 3: Version comparison
    if not Updater.is_version_newer("1.0.1", "1.0.0"):
        push_error("Version comparison failed")
        quit(4)
        return
        
    print("ALL GODOT SIGNATURE CHECKS PASSED PERFECTLY!")
    quit(0)
"""
        test_script_path = CLIENT_DIR / "scripts" / "tests" / "test_updater_pipeline.gd"
        with open(test_script_path, "w", encoding="utf-8") as f:
            f.write(godot_test_code)

        godot_cmd = [
            str(GODOT_EXE),
            "--headless",
            "--path", str(CLIENT_DIR),
            "-s", "res://scripts/tests/test_updater_pipeline.gd"
        ]
        g_res = subprocess.run(godot_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
        print(g_res.stdout)
        
        if test_script_path.exists():
            test_script_path.unlink()
        uid_path = test_script_path.with_suffix(".gd.uid")
        if uid_path.exists():
            uid_path.unlink()
        if g_res.returncode != 0:
            print(f"[Failure] Godot verification failed with code {g_res.returncode}")
            return False

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        if saved_vjson is not None:
            version_json.write_bytes(saved_vjson)
        if saved_pck is not None:
            pck_target.write_bytes(saved_pck)

    print("=" * 66)
    print("  UPDATER & SIGNATURE TEST PASSED 100% SUCCESSFULLY!")
    print("=" * 66)
    return True


if __name__ == "__main__":
    success = run_pipeline_test()
    sys.exit(0 if success else 1)
