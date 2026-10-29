import warnings
warnings.filterwarnings("ignore")
import sys
import os
os.environ["SKIP_REQUIREMENTS_UPDATE"] = "1"
import json
import importlib

def sanitize_json(val):
    if isinstance(val, (set, frozenset)):
        return list(val)
    elif isinstance(val, dict):
        return {str(k): sanitize_json(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [sanitize_json(v) for v in val]
    return val

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: parse_options.py <archipelago_path> <game_name> [custom_worlds_dir]"}))
        sys.exit(1)

    archipelago_path = os.path.abspath(sys.argv[1])
    game_name = sys.argv[2]
    custom_worlds_dir = os.path.abspath(sys.argv[3]) if len(sys.argv) > 3 else None

    # Inject Archipelago core repository in system path
    sys.path.insert(0, archipelago_path)

    # Disable interactive ModuleUpdate prompt in non-interactive CLI runner
    try:
        import ModuleUpdate
        ModuleUpdate.update_ran = True
    except Exception:
        pass

    # Note: Archipelago core's worlds package already automatically scans both worlds/
    # and custom_worlds/ (or user_folder) as apworld containers under worlds.<pkg_name>.
    # If custom_worlds_dir is provided and distinct from user_folder, we ensure sys.path includes it.
    if custom_worlds_dir and os.path.exists(custom_worlds_dir):
        sys.path.insert(0, custom_worlds_dir)

    try:
        # Import core World Registration mechanism
        from worlds.AutoWorld import AutoWorldRegister
        
        # If requested game is "__list", return all registered games
        if game_name == "__list":
            games_list = sorted(list(AutoWorldRegister.world_types.keys()))
            print(json.dumps({"games": games_list}))
            return

        world_class = AutoWorldRegister.world_types.get(game_name)
        if not world_class:
            print(json.dumps({"error": f"Game '{game_name}' not found in registered worlds"}))
            sys.exit(1)

        # Extract Options Dict
        option_dict = {}
        if hasattr(world_class, "options_dataclass") and world_class.options_dataclass:
            import dataclasses
            import typing
            type_hints = typing.get_type_hints(world_class.options_dataclass)
            for field in dataclasses.fields(world_class.options_dataclass):
                field_type = type_hints.get(field.name, field.type)
                if isinstance(field_type, type):
                    option_dict[field.name] = field_type
        elif hasattr(world_class, "options"):
            option_dict = world_class.options
        elif hasattr(world_class, "option_definitions"):
            option_dict = world_class.option_definitions

        parsed_options = []
        for name, opt_class in option_dict.items():
            # Extract docstring description
            description = opt_class.__doc__ or ""
            # Clean up docstring whitespaces
            description = "\n".join([line.strip() for line in description.strip().split("\n")])

            # Determine Display Name
            display_name = getattr(opt_class, "display_name", None) or name.replace("_", " ").title()

            # Determine default value
            default_val = getattr(opt_class, "default", 0)

            # Determine type (Toggle, Range, Choice)
            opt_type = "choice" # fallback
            choices = []
            min_val = 0
            max_val = 0

            # Check for MRO (Method Resolution Order) class names
            class_mro_names = [base.__name__ for base in opt_class.__mro__]

            if "Toggle" in class_mro_names or "DefaultOnToggle" in class_mro_names:
                opt_type = "toggle"
                default_val = bool(default_val)
            elif "Range" in class_mro_names or "SpecialRange" in class_mro_names:
                opt_type = "range"
                min_val = getattr(opt_class, "range_start", 0)
                max_val = getattr(opt_class, "range_end", 100)
                try:
                    default_val = int(default_val)
                except (ValueError, TypeError):
                    default_val = str(default_val)
            elif isinstance(default_val, dict) or any(x in class_mro_names for x in ["OptionDict", "ItemDict", "StartInventoryPool"]):
                opt_type = "dict"
                if not isinstance(default_val, dict):
                    default_val = {}
            elif isinstance(default_val, (list, set, frozenset)) or any(x in class_mro_names for x in ["OptionList", "OptionSet", "ItemSet", "LocationSet", "VerifyKeys"]):
                opt_type = "list"
                if isinstance(default_val, (list, set, frozenset)):
                    default_val = list(default_val)
                else:
                    default_val = []
            elif hasattr(opt_class, "options") and opt_class.options:
                opt_type = "choice"
                try:
                    if hasattr(opt_class, "name_lookup") and opt_class.name_lookup:
                        try:
                            sorted_keys = sorted(opt_class.name_lookup.keys())
                        except TypeError:
                            sorted_keys = sorted(opt_class.name_lookup.keys(), key=lambda x: (type(x).__name__, str(x)))
                        choices = [opt_class.name_lookup[v] for v in sorted_keys]
                    else:
                        choices = sorted(list(opt_class.options.keys()), key=lambda k: opt_class.options[k])
                except TypeError:
                    choices = sorted(list(opt_class.options.keys()))
                # Convert numeric default to string choice name if possible
                if hasattr(opt_class, "name_lookup") and default_val in opt_class.name_lookup:
                    default_val = opt_class.name_lookup[default_val]
                else:
                    # Look up by value matching in options
                    for key, val in opt_class.options.items():
                        if val == default_val:
                            default_val = key
                            break

            parsed_options.append({
                "name": name,
                "display_name": display_name,
                "type": opt_type,
                "description": description,
                "default": sanitize_json(default_val),
                "choices": sanitize_json(choices),
                "min": min_val,
                "max": max_val
            })

        # Extract Item Names
        item_names = []
        if hasattr(world_class, "item_names") and world_class.item_names:
            item_names = sorted(list(world_class.item_names))
        elif hasattr(world_class, "item_name_to_id") and world_class.item_name_to_id:
            item_names = sorted(list(world_class.item_name_to_id.keys()))

        # Extract Location Names
        location_names = []
        if hasattr(world_class, "location_names") and world_class.location_names:
            location_names = sorted(list(world_class.location_names))
        elif hasattr(world_class, "location_name_to_id") and world_class.location_name_to_id:
            location_names = sorted(list(world_class.location_name_to_id.keys()))

        print(json.dumps({
            "game": game_name,
            "item_names": sanitize_json(item_names),
            "location_names": sanitize_json(location_names),
            "options": parsed_options
        }))

    except Exception as e:
        import traceback
        traceback.print_exc()
        print(json.dumps({"error": f"Internal python exception: {str(e)}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
