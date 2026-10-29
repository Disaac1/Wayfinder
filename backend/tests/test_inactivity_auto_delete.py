import sqlite3
import os
import urllib.request
import json
import shutil

DB_PATH = os.path.join(os.path.dirname(__file__), "backend", "database.db")
SEEDS_DIR = os.path.join(os.path.dirname(__file__), "backend", "temp_seeds")
ADMIN_HOUSEKEEPING_URL = "http://localhost:8080/api/admin/housekeeping"

def main():
    print("=== Testing 3-Month Inactivity Auto-Purge Housekeeping ===")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    old_code = "OLD999"
    new_code = "NEW111"

    # Clean any previous artifacts
    cursor.execute("DELETE FROM Rooms WHERE code IN (?, ?)", (old_code, new_code))
    conn.commit()

    # 1. Insert inactive room (> 90 days / 3 months ago)
    cursor.execute("""
        INSERT INTO Rooms (code, host_id, status, created_at, updated_at)
        VALUES (?, 'test_host_old', 'active', datetime('now', '-95 days'), datetime('now', '-95 days'))
    """, (old_code,))

    # 2. Insert active room (recent, 10 days ago)
    cursor.execute("""
        INSERT INTO Rooms (code, host_id, status, created_at, updated_at)
        VALUES (?, 'test_host_new', 'active', datetime('now', '-10 days'), datetime('now', '-10 days'))
    """, (new_code,))
    conn.commit()
    conn.close()

    # Create dummy folders on disk in temp_seeds
    old_dir = os.path.join(SEEDS_DIR, old_code)
    new_dir = os.path.join(SEEDS_DIR, new_code)
    os.makedirs(old_dir, exist_ok=True)
    os.makedirs(new_dir, exist_ok=True)
    with open(os.path.join(old_dir, "seed.txt"), "w") as f:
        f.write("old seed data")
    with open(os.path.join(new_dir, "seed.txt"), "w") as f:
        f.write("active seed data")

    print(f"[Setup] Inserted {old_code} (95 days inactive) and {new_code} (10 days old).")
    assert os.path.exists(old_dir), "Old dir should exist before purge"
    assert os.path.exists(new_dir), "New dir should exist before purge"

    # 3. Trigger Housekeeping endpoint
    print("[Action] Triggering POST /api/admin/housekeeping...")
    req = urllib.request.Request(
        ADMIN_HOUSEKEEPING_URL,
        data=b"{}",
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        print("[Response]", res)
        assert res.get("success") is True

    # 4. Check database state
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT code FROM Rooms WHERE code = ?", (old_code,))
    old_row = cursor.fetchone()
    cursor.execute("SELECT code FROM Rooms WHERE code = ?", (new_code,))
    new_row = cursor.fetchone()

    # Cleanup new_code
    cursor.execute("DELETE FROM Rooms WHERE code = ?", (new_code,))
    conn.commit()
    conn.close()

    if os.path.exists(new_dir):
        shutil.rmtree(new_dir, ignore_errors=True)

    # 5. Assertions
    assert old_row is None, f"Expected {old_code} to be purged from database, but it was found!"
    assert not os.path.exists(old_dir), f"Expected disk directory {old_dir} to be deleted, but it still exists!"
    print(f"[OK] Inactive room {old_code} (> 3 months) was successfully purged from DB and disk!")

    assert new_row is not None, f"Expected active room {new_code} to be retained, but it was deleted!"
    print(f"[OK] Active room {new_code} was safely preserved!")

    print("\n[SUCCESS] 3-Month Inactivity Auto-Purge verified successfully!")

if __name__ == "__main__":
    main()
