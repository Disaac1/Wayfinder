import os
import sys
import zipfile
import hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from encrypt_game_file import encrypt_file, decrypt_file

SOTN_DIR = r"C:\Users\disaa\Desktop\SotN"
FILES_TO_PACK = [
    "Castlevania - Symphony of the Night (USA) (Track 1).bin",
    "Castlevania - Symphony of the Night (USA) (Track 2).bin",
    "Castlevania - Symphony of the Night (USA).cue"
]
ZIP_NAME = "Castlevania - Symphony of the Night (USA).zip"
ENC_NAME = "Castlevania - Symphony of the Night (USA).zip.enc"
KEY = "WayfinderSotN2026!"

def main():
    zip_path = os.path.join(SOTN_DIR, ZIP_NAME)
    enc_path = os.path.join(SOTN_DIR, ENC_NAME)
    
    print(f"Creating zip archive at {zip_path}...")
    with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for fname in FILES_TO_PACK:
            src_file = os.path.join(SOTN_DIR, fname)
            if not os.path.exists(src_file):
                print(f"Error: Missing {src_file}", file=sys.stderr)
                sys.exit(1)
            print(f"  Adding {fname} ({os.path.getsize(src_file):,} bytes)...")
            zf.write(src_file, arcname=fname)
            
    zip_size = os.path.getsize(zip_path)
    print(f"Zip created successfully: {zip_size:,} bytes")
    
    # Calculate sha256 of the plain zip
    with open(zip_path, 'rb') as f:
        orig_hash = hashlib.sha256(f.read()).hexdigest()
    print(f"Plain zip SHA-256: {orig_hash}")
    
    print(f"\nEncrypting {zip_path} -> {enc_path} with AES-256...")
    encrypt_file(zip_path, enc_path, KEY)
    enc_size = os.path.getsize(enc_path)
    print(f"Encrypted file size: {enc_size:,} bytes")
    
    # Verify decryption
    test_dec_path = os.path.join(SOTN_DIR, "test_decrypted.zip")
    print(f"\nVerifying decryption with test output to {test_dec_path}...")
    decrypt_file(enc_path, test_dec_path, KEY)
    with open(test_dec_path, 'rb') as f:
        dec_hash = hashlib.sha256(f.read()).hexdigest()
    assert orig_hash == dec_hash, f"Hash mismatch! {orig_hash} != {dec_hash}"
    print("[PASS] Decrypted zip SHA-256 matches original byte-for-byte!")
    
    # Clean up test decrypted file
    if os.path.exists(test_dec_path):
        os.remove(test_dec_path)
        print("Cleaned up temporary verification file.")

    print("\n=======================================================")
    print(f"  SOTN ENCRYPTION COMPLETED SUCCESSFULLY!")
    print(f"  Encrypted File: {enc_path}")
    print(f"  Passphrase/Key: {KEY}")
    print("=======================================================")

if __name__ == "__main__":
    main()
