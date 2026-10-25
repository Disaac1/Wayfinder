import sys
import os
import glob
import json
import zlib

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: parse_checks.py <archipelago_path> <outputs_dir>"}))
        sys.exit(1)

    archipelago_path = sys.argv[1]
    outputs_dir = sys.argv[2]

    sys.path.insert(0, archipelago_path)
    try:
        from Utils import restricted_loads
    except Exception as e:
        print(json.dumps({"error": f"Failed to import archipelago core: {e}"}))
        sys.exit(1)

    arch_files = glob.glob(os.path.join(outputs_dir, "*.archipelago")) + glob.glob(os.path.join(outputs_dir, "*.multidata"))
    if not arch_files:
        print(json.dumps({"totalChecked": 0, "totalLocations": 0, "games": {}, "players": {}}))
        sys.exit(0)

    try:
        with open(arch_files[0], "rb") as f:
            raw = f.read()
        data = restricted_loads(zlib.decompress(raw[1:]))
    except Exception as e:
        print(json.dumps({"error": f"Failed to decode multidata file: {e}"}))
        sys.exit(1)

    # Check for existing .apsave file
    checked_by_slot = {}
    save_files = glob.glob(os.path.join(outputs_dir, "*.apsave"))
    if save_files:
        try:
            with open(save_files[0], "rb") as f:
                savedata = restricted_loads(zlib.decompress(f.read()))
                loc_checks = savedata.get("location_checks", {})
                for (team, slot), locs in loc_checks.items():
                    checked_by_slot[slot] = len(locs)
        except Exception:
            pass

    slot_info = data.get("slot_info", {})
    locations = data.get("locations", {})

    games = {}
    players = {}
    total_checked = 0
    total_locations = 0

    for slot, s in slot_info.items():
        name = s.name
        game = s.game
        tot = len(locations.get(slot, []))
        chk = checked_by_slot.get(slot, 0)
        total_locations += tot
        total_checked += chk

        players[name] = {"checked": chk, "total": tot, "game": game}
        if game not in games:
            games[game] = {"game": game, "checked": 0, "total": 0}
        games[game]["checked"] += chk
        games[game]["total"] += tot

    print(json.dumps({
        "totalChecked": total_checked,
        "totalLocations": total_locations,
        "games": games,
        "players": players
    }))

if __name__ == "__main__":
    main()
