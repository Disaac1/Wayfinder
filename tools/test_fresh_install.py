#!/usr/bin/env python3
"""
Automated Fresh Install Sandbox Test Runner for Wayfinder
==========================================================
Spawns an isolated sandbox directory for APPDATA, runs the Godot engine
in headless mode against a completely pristine environment, verifies
directory bootstrapping, config generation, catalog discovery,
and clean shutdown, then tears down the sandbox cleanly.
"""

import os
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


def run_fresh_install_test():
    print("=" * 66)
    print("  WAYFINDER FRESH INSTALL SANDBOX AUTOMATION TEST")
    print("=" * 66)

    if not GODOT_EXE.exists():
        print(f"[Error] Godot executable not found at {GODOT_EXE}")
        sys.exit(1)

    sandbox_dir = WORKSPACE_ROOT / "temp_fresh_install_sandbox"
    if sandbox_dir.exists():
        shutil.rmtree(sandbox_dir, ignore_errors=True)
    sandbox_dir.mkdir(parents=True, exist_ok=True)

    print(f"[Sandbox] Created isolated sandbox at: {sandbox_dir}")
    
    # Configure child environment with redirected APPDATA
    env = os.environ.copy()
    env["APPDATA"] = str(sandbox_dir)

    test_script_res = "res://scripts/tests/test_fresh_install.gd"
    cmd = [
        str(GODOT_EXE),
        "--headless",
        "--path",
        str(CLIENT_DIR),
        "-s",
        test_script_res
    ]

    print(f"[Execution] Running Godot headless in sandbox environment...")
    try:
        proc = subprocess.run(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45
        )
        print(proc.stdout)
        
        if proc.returncode != 0:
            print(f"[Failure] Godot test exited with non-zero exit code: {proc.returncode}")
            return False
            
    except subprocess.TimeoutExpired:
        print("[Failure] Test timed out after 45 seconds.")
        return False
    except Exception as e:
        print(f"[Failure] Error running sandbox test: {e}")
        return False

    # Verify that Godot created the isolated user data directory in sandbox
    expected_app_dir = sandbox_dir / "Godot" / "app_userdata" / "Wayfinder"
    if not expected_app_dir.exists():
        print(f"[Failure] Expected user data directory was not created: {expected_app_dir}")
        return False
        
    print(f"[Verification] Sandbox user data created successfully at:")
    print(f"  -> {expected_app_dir}")
    
    # List generated assets in sandbox
    created_items = [p.name for p in expected_app_dir.iterdir()]
    print(f"[Verification] Generated top-level sandbox items: {created_items}")
    
    # Clean up sandbox
    try:
        shutil.rmtree(sandbox_dir, ignore_errors=True)
        print("[Cleanup] Sandbox removed cleanly.")
    except Exception as e:
        print(f"[Cleanup Warning] Failed to delete sandbox: {e}")

    print("\n" + "=" * 66)
    print("  FRESH INSTALL SANDBOX TEST PASSED 100% SUCCESSFULLY!")
    print("=" * 66)
    return True


if __name__ == "__main__":
    success = run_fresh_install_test()
    sys.exit(0 if success else 1)
