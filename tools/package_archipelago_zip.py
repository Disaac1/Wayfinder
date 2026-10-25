"""
Packages a portable, standalone Archipelago installation into a clean zip archive
and saves it to backend/public/tools/archipelago.zip for direct client download.
This avoids requiring admin privileges or running the Inno Setup .exe on client machines.
"""

import os
import sys
import zipfile
import shutil

WORKSPACE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_ZIP_DIR = os.path.join(WORKSPACE_ROOT, "backend", "public", "tools")
OUTPUT_ZIP_PATH = os.path.join(OUTPUT_ZIP_DIR, "archipelago.zip")

CANDIDATE_SOURCE_DIRS = [
    os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Wayfinder\tools\Archipelago"),
    r"C:\ProgramData\Archipelago",
    os.path.expandvars(r"%LOCALAPPDATA%\Programs\Archipelago"),
    r"C:\Archipelago"
]

def find_source_dir():
    for candidate in CANDIDATE_SOURCE_DIRS:
        exe_path = os.path.join(candidate, "ArchipelagoLauncher.exe")
        if os.path.exists(exe_path):
            return candidate
    return None

def package_archipelago():
    source_dir = find_source_dir()
    if not source_dir:
        print("[ERROR] Could not find a valid Archipelago installation in candidate locations:", file=sys.stderr)
        for c in CANDIDATE_SOURCE_DIRS:
            print(f"  - {c}", file=sys.stderr)
        return False

    print(f"[INFO] Found source Archipelago at: {source_dir}")
    os.makedirs(OUTPUT_ZIP_DIR, exist_ok=True)

    # Exclude temporary or unnecessary files to keep zip lightweight
    EXCLUDED_NAMES = {
        "__pycache__", ".git", ".github", "logs", "temp", "temp_seeds"
    }

    print(f"[INFO] Packaging into {OUTPUT_ZIP_PATH}...")
    temp_zip = OUTPUT_ZIP_PATH + ".tmp"
    total_files = 0
    total_bytes = 0

    with zipfile.ZipFile(temp_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for root, dirs, files in os.walk(source_dir):
            dirs[:] = [d for d in dirs if d not in EXCLUDED_NAMES]
            for file in files:
                if file.endswith(".tmp") or file.endswith(".log") or file.endswith(".pyc"):
                    continue
                file_path = os.path.join(root, file)
                rel_path = os.path.relpath(file_path, source_dir)
                zf.write(file_path, arcname=rel_path)
                total_files += 1
                total_bytes += os.path.getsize(file_path)
                if total_files % 100 == 0:
                    print(f"  Packed {total_files} files...")

    if os.path.exists(OUTPUT_ZIP_PATH):
        os.remove(OUTPUT_ZIP_PATH)
    os.rename(temp_zip, OUTPUT_ZIP_PATH)

    zip_size_mb = os.path.getsize(OUTPUT_ZIP_PATH) / (1024 * 1024)
    print(f"[SUCCESS] Packaged {total_files} files ({total_bytes / (1024*1024):.1f} MB uncompressed)")
    print(f"[SUCCESS] Destination: {OUTPUT_ZIP_PATH} ({zip_size_mb:.1f} MB)")
    return True

if __name__ == "__main__":
    success = package_archipelago()
    sys.exit(0 if success else 1)
