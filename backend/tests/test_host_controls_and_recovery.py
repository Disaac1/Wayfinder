
import unittest

def is_backend_online(base_url="http://localhost:8080"):
    try:
        req = urllib.request.Request(f"{base_url}/api/games", headers={"User-Agent": "CI-Test"})
        with urllib.request.urlopen(req, timeout=1) as resp:
            return resp.status == 200
    except Exception:
        return False

import asyncio
import json
import websockets
import urllib.request
import urllib.parse
import sys

BASE_HTTP = "http://localhost:8080"
BASE_WS = "ws://localhost:8080"

def http_post(endpoint, data=None):
    url = f"{BASE_HTTP}{endpoint}"
    payload = json.dumps(data).encode('utf-8') if data else b""
    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'} if data else {})
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode('utf-8')
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode('utf-8')
        try:
            return e.code, json.loads(raw) if raw else {}
        except Exception:
            return e.code, {"error": raw}

async def main():
    print("=== Testing Host Controls (Kick Player), Soft Delete & Recovery ===")
    
    # 1. Connect Host (Alice)
    host_ws = await websockets.connect(BASE_WS)
    await host_ws.send(json.dumps({
        "type": "create_room",
        "playerName": "Alice_Host"
    }))
    
    created_msg = json.loads(await host_ws.recv())
    assert created_msg["type"] == "room_created", f"Expected room_created, got {created_msg}"
    room_code = created_msg["roomCode"]
    host_user_id = created_msg["userId"]
    print(f"[OK] Host created room {room_code} (User ID: {host_user_id})")
    
    # Read initial room_state
    state_msg = json.loads(await host_ws.recv())
    assert state_msg["type"] == "room_state"
    
    # 2. Connect Bob
    bob_ws = await websockets.connect(BASE_WS)
    await bob_ws.send(json.dumps({
        "type": "join_room",
        "roomCode": room_code,
        "playerName": "Bob_Guest"
    }))
    
    bob_joined = json.loads(await bob_ws.recv())
    assert bob_joined["type"] == "room_joined"
    bob_user_id = bob_joined["userId"]
    
    # Drain initial room_state broadcast for Bob
    bob_state = json.loads(await bob_ws.recv())
    assert bob_state["type"] == "room_state"
    print(f"[OK] Bob joined room {room_code} (User ID: {bob_user_id})")
    
    # Host gets updated room state
    host_state2 = json.loads(await host_ws.recv())
    assert len(host_state2["players"]) == 2
    print(f"[OK] Room now has 2 players: {[p['name'] for p in host_state2['players']]}")
    
    # 3. Non-host (Bob) attempts to kick host (Alice)
    print("\n--- Test: Non-host attempts kick ---")
    await bob_ws.send(json.dumps({
        "type": "kick_player",
        "targetUserId": host_user_id
    }))
    bob_err = json.loads(await bob_ws.recv())
    assert bob_err["type"] == "error", f"Expected error, got {bob_err}"
    print(f"[OK] Unauthorized kick rejected: {bob_err['message']}")
    
    # 4. Host kicks Bob
    print("\n--- Test: Host kicks Bob ---")
    await host_ws.send(json.dumps({
        "type": "kick_player",
        "targetUserId": bob_user_id
    }))
    
    # Bob should receive kicked message
    bob_kicked = json.loads(await bob_ws.recv())
    assert bob_kicked["type"] == "kicked", f"Expected kicked, got {bob_kicked}"
    print(f"[OK] Bob received kick notice: {bob_kicked['message']}")
    
    # Host receives updated room_state showing only Host
    host_state3 = json.loads(await host_ws.recv())
    assert len(host_state3["players"]) == 1
    assert host_state3["players"][0]["userId"] == host_user_id
    print(f"[OK] Bob removed from room state. Remaining players: {[p['name'] for p in host_state3['players']]}")
    
    # 5. Room Soft Deletion & Grace Period Recovery
    print("\n--- Test: Unauthorized room deletion check ---")
    # Attempt delete with wrong userId
    status, res = http_post(f"/api/rooms/{room_code}/delete?userId=fake-user-id")
    assert status == 403, f"Expected 403, got {status}: {res}"
    print(f"[OK] Unauthorized room deletion correctly blocked (403): {res.get('error')}")
    
    print("\n--- Test: Host room soft deletion ---")
    status, res = http_post(f"/api/rooms/{room_code}/delete?userId={host_user_id}")
    assert status == 200, f"Expected 200, got {status}: {res}"
    print(f"[OK] Room soft-deleted by host: {res.get('message')}")
    
    # Host socket should receive room_deleted notice
    host_deleted = json.loads(await host_ws.recv())
    assert host_deleted["type"] == "room_deleted", f"Expected room_deleted, got {host_deleted}"
    print(f"[OK] Host socket received room_deleted notification: {host_deleted['message']}")
    
    # Attempting to join deleted room should fail
    guest_ws = await websockets.connect(BASE_WS)
    await guest_ws.send(json.dumps({
        "type": "join_room",
        "roomCode": room_code,
        "playerName": "Charlie"
    }))
    guest_err = json.loads(await guest_ws.recv())
    assert guest_err["type"] == "error"
    print(f"[OK] Inactive/deleted room cannot be joined: {guest_err['message']}")
    await guest_ws.close()
    
    print("\n--- Test: Room 7-day Grace Period Recovery ---")
    status, res = http_post(f"/api/rooms/{room_code}/recover")
    assert status == 200, f"Expected 200, got {status}: {res}"
    print(f"[OK] Room recovered successfully: {res}")
    
    # Verify room can be joined again
    charlie_ws = await websockets.connect(BASE_WS)
    await charlie_ws.send(json.dumps({
        "type": "join_room",
        "roomCode": room_code,
        "playerName": "Charlie"
    }))
    charlie_joined = json.loads(await charlie_ws.recv())
    assert charlie_joined["type"] == "room_joined"
    print(f"[OK] Charlie joined recovered room {room_code}!")
    await charlie_ws.close()
    
    # Cleanup test room
    http_post("/api/test/cleanup", {"roomCode": room_code})
    print("\n[SUCCESS] All host controls, soft deletion, and recovery tests passed!")



class TestHostControlsAndRecovery(unittest.IsolatedAsyncioTestCase):
    async def test_host_controls_and_recovery(self):
        if not is_backend_online():
            raise unittest.SkipTest("Backend service is offline at http://localhost:8080")
        await main()

if __name__ == "__main__":
    asyncio.run(main())
