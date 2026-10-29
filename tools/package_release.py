#!/usr/bin/env python3
"""
Lodestone Release & Deployment Pipeline
========================================
Automates the full deploy workflow:
1. Exports Godot client (Build.exe + Build.pck).
2. Signs and publishes auto-update package (Lodestone.pck + version.json).
3. Packages portable client ZIP (Lodestone_Windows.zip) for website download.
4. If Inno Setup (iscc.exe) is installed, compiles Windows installer (Lodestone_Setup.exe).
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
PUBLISH_SCRIPT = TOOLS_DIR / "publish_update.py"
INSTALLER_ISS = WORKSPACE_ROOT / "installer" / "lodestone.iss"


def get_godot_executable() -> Path:
    if os.environ.get("GODOT_BIN") and Path(os.environ["GODOT_BIN"]).exists():
        return Path(os.environ["GODOT_BIN"])
    if (CLIENT_DIR / "godot.exe").exists():
        return CLIENT_DIR / "godot.exe"
    if (CLIENT_DIR / "godot_console.exe").exists():
        return CLIENT_DIR / "godot_console.exe"
    which_godot = shutil.which("godot") or shutil.which("godot_console")
    if which_godot:
        return Path(which_godot)
    return CLIENT_DIR / "godot.exe"


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


def update_export_metadata(version: str):
    presets_file = CLIENT_DIR / "export_presets.cfg"
    if presets_file.exists():
        content = presets_file.read_text(encoding="utf-8")
        parts = version.split(".")
        while len(parts) < 4:
            parts.append("0")
        four_part = ".".join(parts[:4])
        content = re.sub(r'application/file_version="[^"]*"', f'application/file_version="{four_part}"', content)
        content = re.sub(r'application/product_version="[^"]*"', f'application/product_version="{version}"', content)
        content = re.sub(r'application/company_name="[^"]*"', 'application/company_name="Lodestone"', content)
        content = re.sub(r'application/product_name="[^"]*"', 'application/product_name="Lodestone"', content)
        content = re.sub(r'application/file_description="[^"]*"', 'application/file_description="Lodestone Archipelago Multiworld Client"', content)
        content = re.sub(r'application/copyright="[^"]*"', 'application/copyright="Copyright 2026 Lodestone"', content)
        presets_file.write_text(content, encoding="utf-8")
        print(f"  -> Embedded PE version info ({four_part}) into client/export_presets.cfg")


def export_godot():
    print("\n[1/4] Exporting Godot Windows Desktop Release...")
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    
    godot_exe = get_godot_executable()
    print(f"  -> Using Godot executable: {godot_exe}")
    cmd = [
        str(godot_exe),
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


def publish_auto_update(version: str, notes: str, bridge: bool = False, target_version: str = ""):
    print(f"\n[2/4] Signing and Publishing Auto-Update (v{version})...")
    cmd = [
        sys.executable,
        str(PUBLISH_SCRIPT),
        "--pck", str(BUILD_PCK),
        "--version", version,
        "--notes", notes
    ]
    if bridge:
        cmd.extend(["--bridge", "--target-version", target_version])
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print("[Error] Failed to sign and publish update package")
        sys.exit(1)


def package_portable_zip(version: str):
    print(f"\n[3/4] Creating Portable Client Archive for Website...")
    DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = DOWNLOADS_DIR / "Lodestone_Windows.zip"
    versioned_zip = DOWNLOADS_DIR / f"Lodestone_v{version}_Windows.zip"
    
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(BUILD_EXE, arcname="Lodestone.exe")
        zf.write(BUILD_PCK, arcname="Lodestone.pck")
        
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
        setup_exe = dist_dir / f"Lodestone_Setup_v{version}.exe"
        if setup_exe.exists():
            dest_setup = DOWNLOADS_DIR / "Lodestone_Setup.exe"
            shutil.copy2(setup_exe, dest_setup)
            print(f"  -> Successfully built and deployed: {dest_setup.name} ({setup_exe.stat().st_size:,} bytes)")
    else:
        print("[Warning] Inno Setup compilation returned non-zero code.")


def get_version_info():
    version_file = UPDATES_DIR / "version.json"
    curr = "1.2.0"
    if version_file.exists():
        try:
            with open(version_file, "r", encoding="utf-8") as vf:
                data = json.load(vf)
                curr = data.get("version", "1.2.0")
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
    parser = argparse.ArgumentParser(description="Lodestone Full Build & Deploy Tool")
    parser.add_argument("--version", type=str, required=False, help="Release version (e.g., 1.2.0)")
    parser.add_argument("--notes", type=str, default="Latest release updates", help="Update release notes")
    parser.add_argument("--skip-export", action="store_true", help="Skip Godot export step if already built")
    parser.add_argument("--bridge-version", type=str, help="Build and publish a legacy bridge before the final version")
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
    print(f"       Lodestone Build & Deploy Pipeline (v{args.version})")
    print("=======================================================")
    
    if not args.skip_export:
        if args.bridge_version:
            update_updater_base_version(args.bridge_version)
            export_godot()
            publish_auto_update(args.bridge_version, args.notes, bridge=True, target_version=args.version)

        update_updater_base_version(args.version)
        update_export_metadata(args.version)
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
