#!/usr/bin/env python3
"""
Lodestone Update Publisher & Pack Signer
=========================================
Signs an exported Godot .pck file with our private RSA key and deploys
it along with version.json to the backend public updates directory.
"""

import sys
import os
import json
import base64
import hashlib
import argparse
import shutil
from datetime import datetime, timezone
from pathlib import Path
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import serialization

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PCK = WORKSPACE_ROOT / "client" / ".export" / "Build.pck"
BACKEND_DIR = WORKSPACE_ROOT / "backend"
UPDATES_DIR = BACKEND_DIR / "public" / "updates"
VERSION_FILE = UPDATES_DIR / "version.json"
TARGET_PCK = UPDATES_DIR / "Lodestone.pck"
LEGACY_TARGET_PCK = UPDATES_DIR / "Wayfinder.pck"
BRIDGE_VERSION_FILE = UPDATES_DIR / "bridge-version.json"
BRIDGE_TARGET_PCK = UPDATES_DIR / "Lodestone-bridge.pck"
PRIV_KEY_FILE = BACKEND_DIR / "certs" / "updater_private_key.pem"


def sign_file(file_path: Path, priv_key_path: Path):
    with open(priv_key_path, "rb") as kf:
        private_key = serialization.load_pem_private_key(kf.read(), password=None)

    sha256 = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            sha256.update(chunk)
    digest_hex = sha256.hexdigest()

    with open(file_path, "rb") as f:
        file_bytes = f.read()

    signature = private_key.sign(
        file_bytes,
        padding.PKCS1v15(),
        hashes.SHA256()
    )
    sig_b64 = base64.b64encode(signature).decode("ascii")
    return digest_hex, sig_b64, len(file_bytes)


def main():
    parser = argparse.ArgumentParser(description="Sign and publish a Godot .pck release update")
    parser.add_argument("--pck", type=str, default=str(DEFAULT_PCK), help="Path to exported Build.pck")
    parser.add_argument("--version", type=str, required=True, help="Semantic version string (e.g., 1.2.0)")
    parser.add_argument("--notes", type=str, default="Maintenance and balance updates", help="Changelog release notes")
    parser.add_argument("--min-version", type=str, default="1.0.0", help="Minimum required base client version")
    parser.add_argument("--key", type=str, default=str(PRIV_KEY_FILE), help="Path to updater_private_key.pem")
    parser.add_argument("--bridge", action="store_true", help="Publish as an intermediate bridge update")
    parser.add_argument("--target-version", type=str, default="", help="Target final version when bridge=True")

    args = parser.parse_args()

    pck_path = Path(args.pck).resolve()
    key_path = Path(args.key).resolve()

    if not pck_path.exists():
        print(f"[Error] Target pack file not found: {pck_path}")
        sys.exit(1)

    if not key_path.exists():
        print(f"[Error] Private key not found: {key_path}")
        sys.exit(1)

    print(f"[Signer] Reading and hashing: {pck_path.name}...")
    digest_hex, sig_b64, file_size = sign_file(pck_path, key_path)

    print(f"  -> SHA-256: {digest_hex}")
    print(f"  -> Size:    {file_size:,} bytes")
    print(f"  -> RSA Signature generated ({len(sig_b64)} chars base64)")

    # Ensure updates destination directory
    UPDATES_DIR.mkdir(parents=True, exist_ok=True)

    # Copy .pck
    target_pck = BRIDGE_TARGET_PCK if args.bridge else TARGET_PCK
    target_version_file = BRIDGE_VERSION_FILE if args.bridge else VERSION_FILE
    shutil.copy2(pck_path, target_pck)
    # Also maintain legacy filename so older clients receive it seamlessly
    if not args.bridge:
        shutil.copy2(pck_path, LEGACY_TARGET_PCK)
    print(f"[Deploy] Copied .pck to: {target_pck}")

    # Write version.json
    version_data = {
        "version": args.version,
        "min_version": args.min_version,
        "release_date": datetime.now(timezone.utc).isoformat(),
        "notes": args.notes,
        "pck_filename": target_pck.name,
        "pck_size": file_size,
        "sha256": digest_hex,
        "signature": sig_b64
    }
    if args.bridge:
        version_data["target_version"] = args.target_version or args.version
        version_data["download_url"] = "/api/client/download-pck?channel=bridge"

    with open(target_version_file, "w", encoding="utf-8") as vf:
        json.dump(version_data, vf, indent=2)

    print(f"[Deploy] Wrote version manifest to: {target_version_file}")
    print(f"\n[SUCCESS] Update v{args.version} successfully published and digitally signed!")


if __name__ == "__main__":
    main()
