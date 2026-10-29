import asyncio
import json
import urllib.request
import websockets
import sys

BACKEND_WS = "ws://localhost:8080"
BACKEND_HTTP = "http://localhost:8080"

async def run_multiplayer_test():
    print("==================================================================")
    print("  STARTING MULTI-PLAYER GENERATION, SYNC & AP SOCKET TEST")
    print("==================================================================")
    
    # -------------------------------------------------------------
    # Step 1: Connect Alice and Create Room
    # -------------------------------------------------------------
    print("\n[Step 1] Connecting Alice and creating room...")
    alice_ws = await websockets.connect(BACKEND_WS)
    await alice_ws.send(json.dumps({"type": "create_room", "playerName": "Alice"}))
    
    res = json.loads(await alice_ws.recv())
    assert res.get("type") == "room_created", f"Unexpected create_room response: {res}"
    room_code = res["roomCode"]
    alice_id = res["userId"]
    print(f"  -> Room created: {room_code} | Host Alice ID: {alice_id}")
    
    # Consume initial room_state for Alice
    initial_state_alice = json.loads(await alice_ws.recv())
    assert initial_state_alice.get("type") == "room_state"
    assert len(initial_state_alice["players"]) == 1

    # -------------------------------------------------------------
    # Step 2: Connect Bob and Join Room
    # -------------------------------------------------------------
    print("\n[Step 2] Connecting Bob and joining room...")
    bob_ws = await websockets.connect(BACKEND_WS)
    await bob_ws.send(json.dumps({"type": "join_room", "roomCode": room_code, "playerName": "Bob"}))
    
    res_bob = json.loads(await bob_ws.recv())
    assert res_bob.get("type") == "room_joined", f"Unexpected join_room response: {res_bob}"
    bob_id = res_bob["userId"]
    print(f"  -> Bob joined: User ID {bob_id}")
    
    # Alice should receive broadcast room_state with 2 players
    state_alice_after_join = json.loads(await alice_ws.recv())
    assert len(state_alice_after_join["players"]) == 2, f"Expected 2 players, got {state_alice_after_join['players']}"
    
    # Bob should also receive room_state with 2 players
    state_bob_after_join = json.loads(await bob_ws.recv())
    assert len(state_bob_after_join["players"]) == 2
    print("  -> Both Alice and Bob synchronized 2 connected players.")

    # -------------------------------------------------------------
    # Step 3: Configure Games & Ready States (2 Players, Same Game to test slot isolation)
    # -------------------------------------------------------------
    print("\n[Step 3] Setting games and ready states for both players (Pokemon Emerald multiworld)...")
    alice_yaml = (
        "description: Alice Emerald Multiworld\n"
        "name: Alice\n"
        "game: Pokemon Emerald\n"
        "Pokemon Emerald:\n"
        "  extra_boulders: 0\n"
    )
    await alice_ws.send(json.dumps({
        "type": "update_state",
        "games": ["Pokemon Emerald"],
        "isReady": True,
        "yaml": alice_yaml
    }))
    
    # Both players receive Alice's updated state
    await alice_ws.recv()
    await bob_ws.recv()
    
    bob_yaml = (
        "description: Bob Emerald Multiworld\n"
        "name: Bob\n"
        "game: Pokemon Emerald\n"
        "Pokemon Emerald:\n"
        "  extra_boulders: 0\n"
    )
    await bob_ws.send(json.dumps({
        "type": "update_state",
        "games": ["Pokemon Emerald"],
        "isReady": True,
        "yaml": bob_yaml
    }))
    
    # Both players receive Bob's updated state
    final_state_alice = json.loads(await alice_ws.recv())
    final_state_bob = json.loads(await bob_ws.recv())
    
    ready_count = sum(1 for p in final_state_alice["players"] if p.get("isReady"))
    assert ready_count == 2, f"Expected both players ready, got: {final_state_alice['players']}"
    print("  -> Both Alice and Bob configured their games and set ready=True.")

    # -------------------------------------------------------------
    # Step 4: Multi-Player Seed Generation
    # -------------------------------------------------------------
    print("\n[Step 4] Alice triggering multiworld seed generation...")
    await alice_ws.send(json.dumps({"type": "generate_seed"}))
    
    seed_done = False
    tunnel_url = None
    
    # Read messages until generation completes
    async def listen_for_done(ws, name):
        nonlocal seed_done, tunnel_url
        while not seed_done:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=60.0)
                msg = json.loads(raw)
                mtype = msg.get("type")
                if mtype == "generation_log":
                    line = msg.get("line", "")
                    if "Generating" in line or "Created" in line or "Archipelago" in line or "Player" in line:
                        print(f"    [{name} Log] {line[:95]}")
                elif mtype == "room_state" and msg.get("seedStatus") == "done":
                    seed_done = True
                    tunnel_url = msg.get("tunnelUrl")
                    print(f"  -> [{name}] Seed generation completed! Tunnel: {tunnel_url}")
                    return msg
                elif mtype == "error":
                    raise RuntimeError(f"Error from server during generation: {msg.get('message')}")
            except asyncio.TimeoutError:
                raise TimeoutError(f"Timed out waiting for generation on {name}")

    # Listen on both sockets concurrently
    await asyncio.gather(
        listen_for_done(alice_ws, "Alice"),
        listen_for_done(bob_ws, "Bob")
    )
    
    assert tunnel_url is not None, "tunnel_url was not returned in room_state"
    ap_port = int(tunnel_url.split(":")[-1])
    print(f"  -> Central Archipelago MultiServer running on port: {ap_port}")

    # -------------------------------------------------------------
    # Step 5: Test Targeted Player Patch Distribution & Slot Isolation
    # -------------------------------------------------------------
    print("\n[Step 5] Testing targeted player patch retrieval endpoints...")
    
    # 5a. Alice Patch
    alice_patch_url = f"{BACKEND_HTTP}/api/seeds/{room_code}/player-patch?playerName=Alice&gameName=Pokemon%20Emerald&userId={alice_id}"
    req_alice = urllib.request.Request(alice_patch_url)
    with urllib.request.urlopen(req_alice) as resp:
        assert resp.status == 200, f"Alice patch request failed: {resp.status}"
        disposition_a = resp.headers.get("Content-Disposition", "")
        data_a = resp.read()
        print(f"  -> Alice received patch: {disposition_a} ({len(data_a)} bytes)")
        assert "p1_alice" in disposition_a.lower() or "alice" in disposition_a.lower(), f"Expected Alice patch, got {disposition_a}"
        assert "bob" not in disposition_a.lower(), f"Alice should not receive Bob's patch! Got {disposition_a}"
        assert len(data_a) > 100, "Alice patch data is unexpectedly small"
        
    # 5b. Bob Patch
    bob_patch_url = f"{BACKEND_HTTP}/api/seeds/{room_code}/player-patch?playerName=Bob&gameName=Pokemon%20Emerald&userId={bob_id}"
    req_bob = urllib.request.Request(bob_patch_url)
    with urllib.request.urlopen(req_bob) as resp:
        assert resp.status == 200, f"Bob patch request failed: {resp.status}"
        disposition_b = resp.headers.get("Content-Disposition", "")
        data_b = resp.read()
        print(f"  -> Bob received patch: {disposition_b} ({len(data_b)} bytes)")
        assert "p2_bob" in disposition_b.lower() or "bob" in disposition_b.lower(), f"Expected Bob patch, got {disposition_b}"
        assert "alice" not in disposition_b.lower(), f"Bob should not receive Alice's patch! Got {disposition_b}"
        assert len(data_b) > 100, "Bob patch data is unexpectedly small"

    print("  -> Verified accurate, isolated player patch distribution between Alice & Bob!")

    # -------------------------------------------------------------
    # Step 6: Connect to Archipelago MultiServer via WebSocket
    # -------------------------------------------------------------
    print(f"\n[Step 6] Connecting Alice and Bob AP clients directly to Archipelago MultiServer on port {ap_port}...")
    ap_ws_uri = f"ws://localhost:{ap_port}"
    
    # Wait for AP server port to finish initializing
    alice_ap_ws = None
    for attempt in range(25):
        try:
            alice_ap_ws = await websockets.connect(ap_ws_uri)
            break
        except (ConnectionRefusedError, OSError):
            await asyncio.sleep(0.5)
    assert alice_ap_ws is not None, f"Could not connect to Archipelago MultiServer on port {ap_port} after 12s"
    
    bob_ap_ws = await websockets.connect(ap_ws_uri)
    
    # 6a. Receive RoomInfo on both sockets
    room_info_raw_a = await alice_ap_ws.recv()
    room_info_a = json.loads(room_info_raw_a)[0]
    assert room_info_a.get("cmd") == "RoomInfo", f"Expected RoomInfo, got: {room_info_a}"
    print("  -> Received Archipelago RoomInfo packet on Alice AP socket.")
    
    room_info_raw_b = await bob_ap_ws.recv()
    room_info_b = json.loads(room_info_raw_b)[0]
    assert room_info_b.get("cmd") == "RoomInfo"
    print("  -> Received Archipelago RoomInfo packet on Bob AP socket.")
    
    # 6b. Send Connect packet for Alice (Slot: Alice, Game: Pokemon Emerald)
    connect_alice = [{
        "cmd": "Connect",
        "password": "",
        "game": "Pokemon Emerald",
        "name": "Alice",
        "version": {"major": 0, "minor": 5, "build": 0, "class": "Version"},
        "items_handling": 7,
        "tags": ["AP"],
        "uuid": "alice-test-uuid-12345"
    }]
    await alice_ap_ws.send(json.dumps(connect_alice))
    
    # Expect Connected packet on Alice
    connected_resp_a = json.loads(await alice_ap_ws.recv())
    connected_cmd_a = next((p for p in connected_resp_a if p.get("cmd") == "Connected"), None)
    assert connected_cmd_a is not None, f"Expected Connected packet for Alice, got: {connected_resp_a}"
    alice_slot = connected_cmd_a.get("slot")
    print(f"  -> Alice connected to Archipelago MultiServer! Assigned Slot: {alice_slot}")
    
    # 6c. Send Connect packet for Bob (Slot: Bob, Game: Pokemon Emerald)
    connect_bob = [{
        "cmd": "Connect",
        "password": "",
        "game": "Pokemon Emerald",
        "name": "Bob",
        "version": {"major": 0, "minor": 5, "build": 0, "class": "Version"},
        "items_handling": 7,
        "tags": ["AP"],
        "uuid": "bob-test-uuid-67890"
    }]
    await bob_ap_ws.send(json.dumps(connect_bob))
    
    # Expect Connected packet on Bob
    connected_resp_b = json.loads(await bob_ap_ws.recv())
    connected_cmd_b = next((p for p in connected_resp_b if p.get("cmd") == "Connected"), None)
    assert connected_cmd_b is not None, f"Expected Connected packet for Bob, got: {connected_resp_b}"
    bob_slot = connected_cmd_b.get("slot")
    print(f"  -> Bob connected to Archipelago MultiServer! Assigned Slot: {bob_slot}")
    
    assert alice_slot != bob_slot, f"Alice and Bob should have different slots, got Alice={alice_slot}, Bob={bob_slot}"
    print(f"  -> Both players confirmed active in same multiworld (Alice Slot {alice_slot}, Bob Slot {bob_slot})!")

    # -------------------------------------------------------------
    # Step 7: Test Auto-Update and Session Checks API Endpoints
    # -------------------------------------------------------------
    print("\n[Step 7] Testing dynamic .pck Auto-Updater endpoints...")
    version_url = f"{BACKEND_HTTP}/api/client/version"
    with urllib.request.urlopen(version_url) as resp:
        assert resp.status == 200
        ver_data = json.loads(resp.read().decode())
        print(f"  -> GET /api/client/version returned: version={ver_data.get('version')}, min_version={ver_data.get('min_version')}")
        assert "version" in ver_data
        assert "download_url" in ver_data

    print("\n[Step 7b] Testing Session Checks Progress API...")
    checks_url = f"{BACKEND_HTTP}/api/session/{room_code}/checks"
    with urllib.request.urlopen(checks_url) as resp:
        assert resp.status == 200
        checks_data = json.loads(resp.read().decode())
        print(f"  -> GET /api/session/{room_code}/checks: Total={checks_data.get('totalChecked')}/{checks_data.get('totalLocations')}")
        print(f"  -> Per-game breakdown: {checks_data.get('games')}")
        assert checks_data.get("totalLocations", 0) > 0, "Expected totalLocations to be greater than 0"
        assert "Pokemon Emerald" in checks_data.get("games", {})
        assert checks_data["games"]["Pokemon Emerald"]["total"] > 0

    # -------------------------------------------------------------
    # Step 8: Cleanup
    # -------------------------------------------------------------
    print("\n[Step 8] Cleaning up test sockets and server...")
    await alice_ap_ws.close()
    await bob_ap_ws.close()
    await alice_ws.close()
    await bob_ws.close()
    
    cleanup_req = urllib.request.Request(
        f"{BACKEND_HTTP}/api/test/cleanup",
        data=json.dumps({"roomCode": room_code}).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(cleanup_req) as resp:
        assert resp.status == 200
        print("  -> Room and Archipelago server cleanly shut down.")

    print("\n==================================================================")
    print("  ALL MULTI-PLAYER GENERATION & SYNC TESTS PASSED SUCCESSFULLY! ")
    print("==================================================================")

if __name__ == "__main__":
    asyncio.run(run_multiplayer_test())
