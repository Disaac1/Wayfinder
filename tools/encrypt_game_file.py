#!/usr/bin/env python3
"""
Wayfinder Game File Encryption & Decryption Utility
Compatible with Godot 4 AESContext (AES-256-CBC, PKCS#7 padding)

Format:
  [16-byte random IV] + [AES-256-CBC Ciphertext]

Key Derivation:
  SHA-256 of the user-provided passphrase -> 32-byte AES-256 key
"""

import sys
import os
import hashlib
import argparse
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding

def derive_key(passphrase: str) -> bytes:
    return hashlib.sha256(passphrase.encode('utf-8')).digest()

def encrypt_file(input_path: str, output_path: str, passphrase: str) -> None:
    key = derive_key(passphrase)
    iv = os.urandom(16)
    
    padder = padding.PKCS7(128).padder()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    encryptor = cipher.encryptor()
    
    CHUNK_SIZE = 64 * 1024  # 64 KB
    
    with open(input_path, 'rb') as f_in, open(output_path, 'wb') as f_out:
        f_out.write(iv)
        while True:
            chunk = f_in.read(CHUNK_SIZE)
            if not chunk:
                break
            padded_chunk = padder.update(chunk)
            if padded_chunk:
                f_out.write(encryptor.update(padded_chunk))
        
        final_padded = padder.finalize()
        if final_padded:
            f_out.write(encryptor.update(final_padded))
        f_out.write(encryptor.finalize())
        
    print(f"[OK] Encrypted {input_path} -> {output_path} ({os.path.getsize(output_path)} bytes)")

def decrypt_file(input_path: str, output_path: str, passphrase: str) -> None:
    key = derive_key(passphrase)
    
    CHUNK_SIZE = 64 * 1024  # 64 KB
    
    with open(input_path, 'rb') as f_in:
        iv = f_in.read(16)
        if len(iv) < 16:
            raise ValueError("File is too small to contain a valid IV.")
            
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
        decryptor = cipher.decryptor()
        unpadder = padding.PKCS7(128).unpadder()
        
        with open(output_path, 'wb') as f_out:
            while True:
                chunk = f_in.read(CHUNK_SIZE)
                if not chunk:
                    break
                decrypted_chunk = decryptor.update(chunk)
                if decrypted_chunk:
                    unpadded_chunk = unpadder.update(decrypted_chunk)
                    if unpadded_chunk:
                        f_out.write(unpadded_chunk)
                        
            final_decrypted = decryptor.finalize()
            if final_decrypted:
                final_unpadded = unpadder.update(final_decrypted)
                if final_unpadded:
                    f_out.write(final_unpadded)
            f_out.write(unpadder.finalize())
        
    print(f"[OK] Decrypted {input_path} -> {output_path} ({os.path.getsize(output_path)} bytes)")

def main():
    parser = argparse.ArgumentParser(description="Wayfinder AES-256 Game File Encryptor/Decryptor")
    parser.add_argument("--input", "-i", required=True, help="Input file path")
    parser.add_argument("--output", "-o", required=True, help="Output file path")
    parser.add_argument("--key", "-k", required=True, help="Passphrase/key to use")
    parser.add_argument("--decrypt", "-d", action="store_true", help="Decrypt instead of encrypt")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input):
        print(f"[Error] Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)
        
    if args.decrypt:
        decrypt_file(args.input, args.output, args.key)
    else:
        encrypt_file(args.input, args.output, args.key)

if __name__ == "__main__":
    main()
