import asyncio
import json
import websockets
import urllib.request

async def run_test():
    print("==================================================")
    print("  Starting Backend Lockdown & REST API Test")
    print("==================================================")
    
    uri = "ws://localhost:8080"
    async with websockets.connect(uri) as ws:
        # 1. Create Room
        await ws.send(json.dumps({"type": "create_room", "playerName": "HostPlayer"}))
        res = json.loads(await ws.recv())
        assert res["type"] == "room_created", f"Unexpected response: {res}"
        room_code = res["roomCode"]
        user_id = res["userId"]
        print(f"[Test] Room created: {room_code} (User ID: {user_id})")
        
        # Recv room state
        await ws.recv()
        
        # 2. Set Games & Ready
        await ws.send(json.dumps({
            "type": "update_state",
            "games": ["Pokemon Emerald"],
            "isReady": True,
            "yaml": "description: Test\nname: HostPlayer\ngame: Pokemon Emerald\nPokemon Emerald:\n  extra_boulders: 0\n"
        }))
        await ws.recv() # room_state
        
        # 3. Generate Seed
        print("[Test] Generating seed...")
        await ws.send(json.dumps({"type": "generate_seed"}))
        
        # Recv till seed is done
        seed_done = False
        while not seed_done:
            msg = json.loads(await ws.recv())
            if msg.get("type") == "room_state" and msg.get("seedStatus") == "done":
                seed_done = True
                print("[Test] Seed generation completed successfully.")
                
        # 4. Attempt to modify room state (Lockdown Check)
        print("[Test] Verifying backend lockdown on state updates...")
        await ws.send(json.dumps({
            "type": "update_state",
            "games": ["Hollow Knight"],
            "isReady": False,
            "yaml": None
        }))
        
        err_msg = json.loads(await ws.recv())
        assert err_msg["type"] == "error", f"Expected error message, got: {err_msg}"
        assert "locked" in err_msg["message"].lower(), f"Expected lockdown error, got: {err_msg}"
        print(f"[Test] Lockdown check passed. Error returned: '{err_msg['message']}'")
        
        # 5. Direct HTTP REST API Validation
        print("[Test] Validating direct REST HTTP API endpoints...")
        
        # GET /api/session/:id
        session_url = f"http://localhost:8080/api/session/{room_code}"
        with urllib.request.urlopen(session_url) as resp:
            data = json.loads(resp.read().decode())
            assert data["roomCode"] == room_code
            assert data["seedStatus"] == "done"
            assert len(data["players"]) == 1
            print(f"[Test] GET /api/session/{room_code} passed: {data['seedStatus']}, {len(data['players'])} player(s)")
            
        # GET /api/session/:id/games
        games_url = f"http://localhost:8080/api/session/{room_code}/games"
        with urllib.request.urlopen(games_url) as resp:
            data = json.loads(resp.read().decode())
            assert data["roomCode"] == room_code
            assert data["players"][0]["games"] == ["Pokemon Emerald"]
            print(f"[Test] GET /api/session/{room_code}/games passed: {data['players'][0]['games']}")

        # GET /api/session/:id/server
        server_url = f"http://localhost:8080/api/session/{room_code}/server"
        with urllib.request.urlopen(server_url) as resp:
            data = json.loads(resp.read().decode())
            assert data["roomCode"] == room_code
            assert data["serverActive"] == True
            print(f"[Test] GET /api/session/{room_code}/server passed: Port {data['port']}, active={data['serverActive']}")

        # Cleanup
        req = urllib.request.Request(
            "http://localhost:8080/api/test/cleanup",
            data=json.dumps({"roomCode": room_code}).encode(),
            headers={"Content-Type": "application/json"}
        )
        urllib.request.urlopen(req)
        print("[Test] Cleanup complete.")

    print("\n==================================================")
    print("  BACKEND LOCKDOWN & REST API TEST PASSED!")
    print("==================================================")

if __name__ == "__main__":
    asyncio.run(run_test())
