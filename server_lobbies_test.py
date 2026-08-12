import asyncio
import json
import websockets
import urllib.request

async def run_test():
    print("==================================================")
    print("  Starting Server Lobbies List & Deletion API Test")
    print("==================================================")
    
    uri = "ws://localhost:8080"
    async with websockets.connect(uri) as ws:
        # 1. Create Room
        await ws.send(json.dumps({"type": "create_room", "playerName": "LobbyTester"}))
        res = json.loads(await ws.recv())
        assert res["type"] == "room_created", f"Unexpected response: {res}"
        room_code = res["roomCode"]
        user_id = res["userId"]
        print(f"[Test] Created test room: {room_code}")

        # 2. Query GET /api/rooms
        rooms_url = "http://localhost:8080/api/rooms"
        with urllib.request.urlopen(rooms_url) as resp:
            data = json.loads(resp.read().decode())
            rooms = data.get("rooms", [])
            print(f"[Test] GET /api/rooms returned {len(rooms)} room(s).")
            found = False
            for r in rooms:
                if r["code"] == room_code:
                    found = True
                    assert r["hostName"] == "LobbyTester"
                    assert r["playerCount"] == 1
                    assert r["seedStatus"] == "idle"
                    break
            assert found, f"Room {room_code} was not found in GET /api/rooms output: {rooms}"
            print(f"[Test] Room {room_code} verified in GET /api/rooms list!")

        # 3. Explicitly delete room via POST /api/rooms/:code/delete
        delete_url = f"http://localhost:8080/api/rooms/{room_code}/delete"
        req = urllib.request.Request(delete_url, data=b"", headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            assert data.get("success") == True, f"Delete failed: {data}"
            print(f"[Test] Room {room_code} deleted via API.")

        # 4. Verify room no longer exists in GET /api/rooms
        with urllib.request.urlopen(rooms_url) as resp:
            data = json.loads(resp.read().decode())
            rooms = data.get("rooms", [])
            found = False
            for r in rooms:
                if r["code"] == room_code:
                    found = True
                    break
            assert not found, f"Room {room_code} was still found after deletion!"
            print(f"[Test] Verified room {room_code} is purged from GET /api/rooms!")

    print("\n==================================================")
    print("  SERVER LOBBIES LIST & DELETION TEST PASSED!")
    print("==================================================")

if __name__ == "__main__":
    asyncio.run(run_test())
