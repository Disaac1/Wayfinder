#!/usr/bin/env python3
"""
Wayfinder Release & Deployment Pipeline
========================================
Automates the full deploy workflow:
1. Exports Godot client (Build.exe + Build.pck).
2. Signs and publishes auto-update package (Wayfinder.pck + version.json).
3. Packages portable client ZIP (Wayfinder_Windows.zip) for website download.
4. If Inno Setup (iscc.exe) is installed, compiles Windows installer (Wayfinder_Setup.exe).
5. Deploys downloads to backend/public/downloads/.
"""

import sys
import os
import re
import json
import shutil
import zipfile
import subprocess
import argparse
import urllib.request
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
CLIENT_DIR = WORKSPACE_ROOT / "client"
EXPORT_DIR = CLIENT_DIR / ".export"
BUILD_EXE = EXPORT_DIR / "Build.exe"
BUILD_PCK = EXPORT_DIR / "Build.pck"
BACKEND_DIR = WORKSPACE_ROOT / "backend"
UPDATES_DIR = BACKEND_DIR / "public" / "updates"
DOWNLOADS_DIR = BACKEND_DIR / "public" / "downloads"
TOOLS_DIR = WORKSPACE_ROOT / "tools"
GODOT_EXE = CLIENT_DIR / "godot_console.exe"
PUBLISH_SCRIPT = TOOLS_DIR / "publish_update.py"
INSTALLER_ISS = WORKSPACE_ROOT / "installer" / "wayfinder.iss"


def update_updater_base_version(version: str):
    updater_file = CLIENT_DIR / "scripts" / "core" / "updater.gd"
    if updater_file.exists():
        content = updater_file.read_text(encoding="utf-8")
        updated = re.sub(
            r'const BASE_VERSION: String = "[^"]*"',
            f'const BASE_VERSION: String = "{version}"',
            content
        )
        updater_file.write_text(updated, encoding="utf-8")
        print(f"  -> Updated BASE_VERSION to {version} in client/scripts/core/updater.gd")


def export_godot():
    print("\n[1/4] Exporting Godot Windows Desktop Release...")
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    
    cmd = [
        str(GODOT_EXE),
        "--headless",
        "--path", str(CLIENT_DIR),
        "--export-release", "Windows Desktop",
        str(BUILD_EXE.relative_to(CLIENT_DIR))
    ]
    
    res = subprocess.run(cmd, cwd=CLIENT_DIR)
    if res.returncode != 0 or not BUILD_EXE.exists() or not BUILD_PCK.exists():
        print(f"[Error] Godot export failed with return code {res.returncode}")
        sys.exit(1)
        
    print(f"  -> Exported Build.exe ({BUILD_EXE.stat().st_size:,} bytes)")
    print(f"  -> Exported Build.pck ({BUILD_PCK.stat().st_size:,} bytes)")


def publish_auto_update(version: str, notes: str):
    print(f"\n[2/4] Signing and Publishing Auto-Update (v{version})...")
    cmd = [
        sys.executable,
        str(PUBLISH_SCRIPT),
        "--pck", str(BUILD_PCK),
        "--version", version,
        "--notes", notes
    ]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print("[Error] Failed to sign and publish update package")
        sys.exit(1)


def package_portable_zip(version: str):
    print(f"\n[3/4] Creating Portable Client Archive for Website...")
    DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = DOWNLOADS_DIR / "Wayfinder_Windows.zip"
    versioned_zip = DOWNLOADS_DIR / f"Wayfinder_v{version}_Windows.zip"
    
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(BUILD_EXE, arcname="Wayfinder.exe")
        zf.write(BUILD_PCK, arcname="Wayfinder.pck")
        
    shutil.copy2(zip_path, versioned_zip)
    print(f"  -> Generated: {zip_path.name} ({zip_path.stat().st_size:,} bytes)")


def build_installer(version: str):
    print("\n[4/4] Checking for Inno Setup (ISCC.exe)...")
    iscc_candidates = [
        shutil.which("iscc.exe"),
        os.path.expandvars(r"%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"),
        r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        r"C:\Program Files\Inno Setup 6\ISCC.exe"
    ]
    iscc_path = next((p for p in iscc_candidates if p and os.path.exists(p)), None)
    
    if not iscc_path:
        print("  -> Inno Setup not found. (Install with: winget install JRSoftware.InnoSetup)")
        print("  -> Skipping .exe installer. Portable ZIP is ready in downloads.")
        return

    print(f"  -> Compiling Inno Setup installer using {iscc_path}...")
    cmd = [iscc_path, f"/DMyAppVersion={version}", str(INSTALLER_ISS)]
    res = subprocess.run(cmd, cwd=WORKSPACE_ROOT)
    if res.returncode == 0:
        dist_dir = WORKSPACE_ROOT / "dist"
        setup_exe = dist_dir / f"Wayfinder_Setup_v{version}.exe"
        if setup_exe.exists():
            dest_setup = DOWNLOADS_DIR / "Wayfinder_Setup.exe"
            shutil.copy2(setup_exe, dest_setup)
            print(f"  -> Successfully built and deployed: {dest_setup.name} ({setup_exe.stat().st_size:,} bytes)")
    else:
        print("[Warning] Inno Setup compilation returned non-zero code.")


def get_version_info():
    version_file = UPDATES_DIR / "version.json"
    curr = "1.0.0"
    if version_file.exists():
        try:
            with open(version_file, "r", encoding="utf-8") as vf:
                data = json.load(vf)
                curr = data.get("version", "1.0.0")
        except Exception:
            pass

    # If local version is still fallback 1.0.0, attempt fetching latest from published server
    if curr == "1.0.0":
        try:
            req = urllib.request.Request(
                "https://wayfinder.disaac1.com/api/client/version",
                headers={"User-Agent": "Wayfinder-Release-Tool/1.0"}
            )
            with urllib.request.urlopen(req, timeout=2.5) as resp:
                remote_data = json.loads(resp.read().decode("utf-8"))
                rem_ver = remote_data.get("version")
                if rem_ver:
                    curr = rem_ver
        except Exception:
            pass

    parts = curr.split(".")
    try:
        parts[-1] = str(int(parts[-1]) + 1)
        next_ver = ".".join(parts)
    except Exception:
        next_ver = f"{curr}.1"
    return curr, next_ver


def main():
    parser = argparse.ArgumentParser(description="Wayfinder Full Build & Deploy Tool")
    parser.add_argument("--version", type=str, required=False, help="Release version (e.g., 1.0.1)")
    parser.add_argument("--notes", type=str, default="Latest release updates", help="Update release notes")
    parser.add_argument("--skip-export", action="store_true", help="Skip Godot export step if already built")
    parser.add_argument("--get-next-version", action="store_true", help="Print current and suggested next version")
    
    args = parser.parse_args()

    if args.get_next_version:
        curr, next_ver = get_version_info()
        print(f"{curr} {next_ver}")
        return

    if not args.version:
        print("[Error] --version argument is required unless using --get-next-version")
        sys.exit(1)
    
    print("=======================================================")
    print(f"       Wayfinder Build & Deploy Pipeline (v{args.version})")
    print("=======================================================")
    
    if not args.skip_export:
        update_updater_base_version(args.version)
        export_godot()
        
    publish_auto_update(args.version, args.notes)
    package_portable_zip(args.version)
    build_installer(args.version)
    
    print("\n=======================================================")
    print("                  DEPLOYMENT COMPLETE                  ")
    print("=======================================================")
    print(f"  • Website Downloads: {DOWNLOADS_DIR}")
    print(f"  • Auto-Updates:      {UPDATES_DIR / 'version.json'}")
    print("=======================================================\n")


if __name__ == "__main__":
    main()
