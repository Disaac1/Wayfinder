import sys
import os
import dataclasses
import json

sys.path.insert(0, os.path.abspath("backend/archipelago_core"))

# Prevent ModuleUpdate interactive prompts
os.environ["SKIP_MODULE_UPDATE"] = "1"

try:
    from worlds.pokemon_emerald.options import PokemonEmeraldOptions
    from Options import PerGameCommonOptions
    
    # Extract all option field names defined on PokemonEmeraldOptions
    emerald_fields = {f.name: f.type for f in dataclasses.fields(PokemonEmeraldOptions)}
    
    print(f"Total options in backend PokemonEmeraldOptions: {len(emerald_fields)}")
    
    # Keys configured in our GDScript Guided Setup (DEFAULT_CONFIG and wizard setters)
    guided_keys = [
        "goal", "norman_count", "norman_requirement", "elite_four_count", "elite_four_requirement",
        "legendary_hunt_count", "legendary_hunt_catch", "badges", "hms", "key_items", "bikes",
        "event_tickets", "rods", "overworld_items", "hidden_items", "npc_gifts", "berry_trees",
        "dexsanity", "trainersanity", "require_flash", "remove_roadblocks", "wild_pokemon",
        "starters", "trainer_parties", "legendary_encounters", "misc_pokemon", "types",
        "abilities", "exp_modifier", "min_catch_rate", "guaranteed_catch", "reusable_tms_tutors",
        "level_up_moves", "move_match_type_bias", "match_trainer_levels", "turbo_a",
        "better_shops", "music", "fanfares", "death_link", "enable_wonder_trading"
    ]
    
    missing_keys = [k for k in guided_keys if k not in emerald_fields]
    if missing_keys:
        print("ERROR: Guided setup contains keys NOT in backend schema:", missing_keys)
    else:
        print("SUCCESS: All guided setup keys match backend PokemonEmeraldOptions exactly!")
        
    print("\nBackend options breakdown:")
    for k in sorted(emerald_fields.keys()):
        is_guided = "✓ (Guided)" if k in guided_keys else "  (Advanced/Default)"
        opt_class = emerald_fields[k]
        display_name = getattr(opt_class, "display_name", k)
        print(f"  [{is_guided}] {k} -> {display_name}")

except Exception as e:
    import traceback
    traceback.print_exc()
    sys.exit(1)
