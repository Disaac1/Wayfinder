import sys
import os
import glob
import json
import re
import zlib

def is_transition_or_event(loc_name: str, item_name: str) -> bool:
    """Detects and filters out Hollow Knight room transitions, entrance rando links, and logic events."""
    # 1. Self-pointing logic connection or transition (e.g. Abyss_01 -> Abyss_01)
    if loc_name == item_name:
        return True

    # 2. Door/entrance transition syntax like White_Palace_15[right1] or RoomA -> RoomB
    if ("[" in loc_name and "]" in loc_name) or ("[" in item_name and "]" in item_name):
        return True
    if "->" in loc_name or "->" in item_name:
        return True

    # 3. Logic events and internal tags
    lower_loc = loc_name.strip().lower()
    for prefix in ("can_", "defeated_", "combat[", "opened_", "broke_", "hit_", "warp-", "bench-", "aerialminiboss", "boss"):
        if lower_loc.startswith(prefix) or lower_loc == prefix:
            return True

    return False

def parse_spoiler_log(spoiler_path):
    players = []
    locations = {}
    items_by_player = {}
    all_items = set()

    with open(spoiler_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Find players from Player N: <Name>
    player_matches = re.findall(r'^Player\s+\d+:\s*(.+)$', content, re.MULTILINE)
    for p in player_matches:
        p_name = p.strip()
        if p_name and p_name not in players:
            players.append(p_name)
            locations[p_name] = []
            items_by_player[p_name] = set()

    # If single-player seed without Player N: headers
    if not players:
        # Check for single player game
        p_match = re.search(r'^Game:\s*(.+)$', content, re.MULTILINE)
        if p_match:
            default_player = "Player 1"
            players.append(default_player)
            locations[default_player] = []
            items_by_player[default_player] = set()

    # Find Locations block
    loc_start = content.find("\nLocations:\n")
    if loc_start != -1:
        loc_text = content[loc_start + len("\nLocations:\n"):]
        # Find next major header like \nPlaythrough:\n or \nPaths:\n
        next_section = re.search(r'\n(Playthrough|Paths):\n', loc_text)
        if next_section:
            loc_text = loc_text[:next_section.start()]

        # Pattern 1: Multi-world format: <Location> (<Player>): <Item> (<TargetPlayer>)
        loc_pattern_mw = re.compile(r'^\s*(.+?)\s+\(([^)]+)\):\s*(.+?)\s+\(([^)]+)\)\s*(?:costing.+)?$', re.MULTILINE)
        for match in loc_pattern_mw.finditer(loc_text):
            loc_name, loc_player, item_name, target_player = match.groups()
            loc_name = loc_name.strip()
            loc_player = loc_player.strip()
            item_name = item_name.strip()
            target_player = target_player.strip()

            # Filter out transitions and logic events
            if is_transition_or_event(loc_name, item_name):
                continue

            if loc_player not in locations:
                locations[loc_player] = []
            if loc_name not in locations[loc_player]:
                locations[loc_player].append(loc_name)

            if target_player not in items_by_player:
                items_by_player[target_player] = set()
            items_by_player[target_player].add(item_name)
            all_items.add(item_name)

            if loc_player not in players:
                players.append(loc_player)
            if target_player not in players:
                players.append(target_player)

        # Pattern 2: Single-player format: <Location>: <Item>
        if not any(locations.values()):
            default_p = players[0] if players else "Player 1"
            loc_pattern_sp = re.compile(r'^\s*(.+?):\s*(.+?)\s*(?:costing.+)?$', re.MULTILINE)
            for match in loc_pattern_sp.finditer(loc_text):
                loc_name, item_name = match.groups()
                loc_name = loc_name.strip()
                item_name = item_name.strip()

                if is_transition_or_event(loc_name, item_name):
                    continue

                if default_p not in locations:
                    locations[default_p] = []
                if loc_name not in locations[default_p]:
                    locations[default_p].append(loc_name)

                if default_p not in items_by_player:
                    items_by_player[default_p] = set()
                items_by_player[default_p].add(item_name)
                all_items.add(item_name)

    # Convert sets to sorted lists
    sorted_items = {}
    for p in items_by_player:
        sorted_items[p] = sorted(list(items_by_player[p]))

    for p in locations:
        locations[p] = sorted(locations[p])

    return {
        "players": players,
        "locations": locations,
        "items": sorted_items,
        "allItems": sorted(list(all_items))
    }

def parse_multidata(archipelago_path, outputs_dir):
    sys.path.insert(0, archipelago_path)
    try:
        from Utils import restricted_loads
    except Exception as e:
        return {"error": f"Failed to import archipelago core: {e}"}

    arch_files = glob.glob(os.path.join(outputs_dir, "*.archipelago")) + glob.glob(os.path.join(outputs_dir, "*.multidata"))
    if not arch_files:
        return {"players": [], "locations": {}, "items": {}, "allItems": []}

    try:
        with open(arch_files[0], "rb") as f:
            raw = f.read()
        data = restricted_loads(zlib.decompress(raw[1:]))
    except Exception as e:
        return {"error": f"Failed to decode multidata file: {e}"}

    slot_info = data.get("slot_info", {})
    players = []
    locations = {}
    items_by_player = {}
    all_items = set()

    slot_to_name = {}
    for slot, s in slot_info.items():
        name = getattr(s, "name", str(slot))
        slot_to_name[slot] = name
        players.append(name)
        locations[name] = []
        items_by_player[name] = set()

    datapackage = data.get("datapackage", {})
    # Map item ID -> item Name, location ID -> location Name per game
    loc_id_to_name = {}
    item_id_to_name = {}
    for game, gdata in datapackage.items():
        for l_name, l_id in gdata.get("location_name_to_id", {}).items():
            loc_id_to_name[(game, l_id)] = l_name
        for i_name, i_id in gdata.get("item_name_to_id", {}).items():
            item_id_to_name[(game, i_id)] = i_name
            all_items.add(i_name)

    for slot, loc_dict in data.get("locations", {}).items():
        p_name = slot_to_name.get(slot, str(slot))
        s_info = slot_info.get(slot)
        game = getattr(s_info, "game", "") if s_info else ""
        for loc_id, item_tuple in loc_dict.items():
            item_id = item_tuple[0]
            target_slot = item_tuple[1]
            target_name = slot_to_name.get(target_slot, str(target_slot))
            target_info = slot_info.get(target_slot)
            target_game = getattr(target_info, "game", "") if target_info else ""

            loc_name = loc_id_to_name.get((game, loc_id), f"Location #{loc_id}")
            item_name = item_id_to_name.get((target_game, item_id), f"Item #{item_id}")

            if p_name in locations and loc_name not in locations[p_name]:
                locations[p_name].append(loc_name)
            if target_name in items_by_player:
                items_by_player[target_name].add(item_name)
            all_items.add(item_name)

    sorted_items = {}
    for p in items_by_player:
        sorted_items[p] = sorted(list(items_by_player[p]))
    for p in locations:
        locations[p] = sorted(locations[p])

    return {
        "players": players,
        "locations": locations,
        "items": sorted_items,
        "allItems": sorted(list(all_items))
    }

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: parse_seed_data.py <archipelago_path> <outputs_dir>"}))
        sys.exit(1)

    archipelago_path = sys.argv[1]
    outputs_dir = sys.argv[2]

    # 1. Primary: Use multidata binary extraction (authoritative, exact IDs, zero transition/event spam)
    try:
        result = parse_multidata(archipelago_path, outputs_dir)
        if result.get("players") and (result.get("locations") or result.get("items")):
            print(json.dumps(result))
            sys.exit(0)
    except Exception:
        pass

    # 2. Fallback: Parse spoiler log with strict transition filtering
    spoiler_files = glob.glob(os.path.join(outputs_dir, "*_Spoiler.txt"))
    if spoiler_files:
        try:
            result = parse_spoiler_log(spoiler_files[0])
            if result.get("players") and (result.get("locations") or result.get("items")):
                print(json.dumps(result))
                sys.exit(0)
        except Exception:
            pass

    print(json.dumps({"players": [], "locations": {}, "items": {}, "allItems": []}))

if __name__ == "__main__":
    main()
