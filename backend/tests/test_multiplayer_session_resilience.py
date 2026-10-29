
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
import urllib.request
import urllib.error
import websockets
import sys
import io
import zipfile

BACKEND_WS = "ws://localhost:8080"
BACKEND_HTTP = "http://localhost:8080"

async def run_resilience_test():
    print("==================================================================")
    print("  STARTING MULTI-PLAYER SESSION RESILIENCE & CONCURRENCY TEST")
    print("==================================================================")

    # 1. Setup Room with 2 players
    print("\n[Step 1] Creating Room and Joining Players...")
    alice_ws = await websockets.connect(BACKEND_WS)
    await alice_ws.send(json.dumps({"type": "create_room", "playerName": "Alice"}))
    res_a = json.loads(await alice_ws.recv())
    room_code = res_a["roomCode"]
    alice_id = res_a["userId"]
    await alice_ws.recv() # room_state

    bob_ws = await websockets.connect(BACKEND_WS)
    await bob_ws.send(json.dumps({"type": "join_room", "roomCode": room_code, "playerName": "Bob"}))
    res_b = json.loads(await bob_ws.recv())
    bob_id = res_b["userId"]
    await alice_ws.recv() # room_state on Alice
    await bob_ws.recv() # room_state on Bob
    print(f"  -> Room {room_code} initialized with Alice ({alice_id}) and Bob ({bob_id})")

    # 2. Lockout Collision (Checkout by Alice, then Bob)
    print("\n[Step 2] Testing Session Lockout and 409 Conflict Collision...")
    checkout_alice_url = f"{BACKEND_HTTP}/api/session/{room_code}/checkout?userId={alice_id}"
    with urllib.request.urlopen(checkout_alice_url) as resp:
        assert resp.status == 200
        print("  -> Alice successfully acquired session lock.")

    # Sockets should receive room_state with lockedBy == alice_id
    msg_a = json.loads(await alice_ws.recv())
    msg_b = json.loads(await bob_ws.recv())
    assert msg_a.get("lockedBy") == alice_id
    assert msg_b.get("lockedBy") == alice_id
    print("  -> Verified real-time broadcast: session is locked by Alice.")

    # Bob attempts to checkout -> Expect HTTP 409 Conflict
    checkout_bob_url = f"{BACKEND_HTTP}/api/session/{room_code}/checkout?userId={bob_id}"
    try:
        urllib.request.urlopen(checkout_bob_url)
        assert False, "Bob's checkout should have failed with HTTP 409 Conflict"
    except urllib.error.HTTPError as e:
        assert e.code == 409, f"Expected HTTP 409, got {e.code}"
        body = json.loads(e.read().decode())
        print(f"  -> Bob checkout rejected as expected: {body.get('error')}")

    # 3. Checkin by Alice
    print("\n[Step 3] Alice checking in session save archive...")
    # Create mock zip archive containing {roomCode}.apsave
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"{room_code}.apsave", b"Mock Archipelago Save Game State Data")
    zip_bytes = zip_buffer.getvalue()

    checkin_url = f"{BACKEND_HTTP}/api/session/{room_code}/checkin?userId={alice_id}"
    checkin_req = urllib.request.Request(
        checkin_url,
        data=zip_bytes,
        headers={"Content-Type": "application/zip"},
        method="POST"
    )
    with urllib.request.urlopen(checkin_req) as resp:
        assert resp.status == 200
        res_data = json.loads(resp.read().decode())
        assert res_data.get("success") == True
        print("  -> Alice successfully checked in save archive.")

    # Sockets receive room_state with lockedBy == null
    msg_a = json.loads(await alice_ws.recv())
    msg_b = json.loads(await bob_ws.recv())
    assert msg_a.get("lockedBy") is None or msg_a.get("lockedBy") == ""
    assert msg_b.get("lockedBy") is None or msg_b.get("lockedBy") == ""
    print("  -> Verified session lock released after checkin.")

    # 4. Bob checks out save file (now available)
    print("\n[Step 4] Bob acquiring session lock now that it is free...")
    with urllib.request.urlopen(checkout_bob_url) as resp:
        assert resp.status == 200
        print(f"  -> Bob successfully acquired session lock (Content-Type: {resp.headers.get('Content-Type')}).")

    await alice_ws.recv()
    await bob_ws.recv()

    # 5. Force Unlock Override
    print("\n[Step 5] Testing Force Unlock override (Alice overrides Bob's lock)...")
    force_unlock_url = f"{BACKEND_HTTP}/api/session/{room_code}/force-unlock"
    force_req = urllib.request.Request(
        force_unlock_url,
        data=b"",
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(force_req) as resp:
        assert resp.status == 200
        print("  -> Force unlock API succeeded.")

    msg_a = json.loads(await alice_ws.recv())
    msg_b = json.loads(await bob_ws.recv())
    assert msg_a.get("lockedBy") is None or msg_a.get("lockedBy") == ""
    print("  -> Verified session lock forcefully cleared across all player sockets.")

    # 6. Player Disconnect and Reconnect Handshake
    print("\n[Step 6] Testing WebSocket Disconnect and Reconnect Handshake...")
    # Bob disconnects
    await bob_ws.close()
    await asyncio.sleep(0.3)

    # Alice should see Bob marked as isConnected = False
    state_after_drop = json.loads(await alice_ws.recv())
    bob_in_state = next((p for p in state_after_drop["players"] if p.get("userId") == bob_id), None)
    assert bob_in_state is not None
    assert bob_in_state.get("isConnected") == False
    print("  -> Alice notified Bob is disconnected (isConnected = False).")

    # Bob reconnects with same userId
    bob_reconnected_ws = await websockets.connect(BACKEND_WS)
    await bob_reconnected_ws.send(json.dumps({
        "type": "reconnect",
        "userId": bob_id,
        "roomCode": room_code
    }))
    recon_msg = json.loads(await bob_reconnected_ws.recv())
    assert recon_msg.get("type") == "room_joined"
    print("  -> Bob reconnected with existing session ID successfully.")

    # Alice sees Bob restored as isConnected = True
    state_after_recon = json.loads(await alice_ws.recv())
    bob_restored = next((p for p in state_after_recon["players"] if p.get("userId") == bob_id), None)
    assert bob_restored is not None
    assert bob_restored.get("isConnected") == True
    print("  -> Alice notified Bob is restored (isConnected = True).")

    # Cleanup
    await bob_reconnected_ws.close()
    await alice_ws.close()
    cleanup_req = urllib.request.Request(
        f"{BACKEND_HTTP}/api/test/cleanup",
        data=json.dumps({"roomCode": room_code}).encode(),
        headers={"Content-Type": "application/json"}
    )
    urllib.request.urlopen(cleanup_req)
    print("\n==================================================================")
    print("  MULTI-PLAYER SESSION RESILIENCE & CONCURRENCY TEST PASSED!     ")
    print("==================================================================")



class TestMultiplayerSessionResilience(unittest.IsolatedAsyncioTestCase):
    async def test_multiplayer_session_resilience(self):
        if not is_backend_online():
            raise unittest.SkipTest("Backend service is offline at http://localhost:8080")
        await run_resilience_test()

if __name__ == "__main__":
    asyncio.run(run_resilience_test())
