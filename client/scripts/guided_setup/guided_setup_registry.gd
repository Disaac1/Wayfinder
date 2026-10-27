class_name GuidedSetupRegistry
extends RefCounted

const DeclarativeGuidedSetupScript = preload("res://scripts/guided_setup/declarative_guided_setup.gd")

# Runtime registry mapping game names to custom Guided Setup GDScript resource paths
static var REGISTRY: Dictionary = {}

static var _slug_map_cache: Dictionary = {}
static var _slug_map_initialized: bool = false

# Normalizes string for alias lookup
static func _normalize_key(s: String) -> String:
	var result = s.to_lower()
	for ch in [":", "-", "_", " ", "'", ".", "(", ")", "[", "]", "é"]:
		if ch == "é":
			result = result.replace(ch, "e")
		else:
			result = result.replace(ch, "")
	return result

# Scans available game directories to build dynamic canonical slug and alias mapping
static func refresh_slug_cache() -> void:
	_slug_map_initialized = false
	_slug_map_cache.clear()
	_ensure_slug_cache()

static func _ensure_slug_cache() -> void:
	if _slug_map_initialized:
		return
	_slug_map_initialized = true
	
	# 1. Populate canonical slugs and aliases from backend launcher cache
	if FileAccess.file_exists("user://cache/launcher_config.json"):
		var fa = FileAccess.open("user://cache/launcher_config.json", FileAccess.READ)
		if fa:
			var parsed = JSON.parse_string(fa.get_as_text())
			if parsed is Dictionary and parsed.has("games"):
				for g_name in parsed["games"].keys():
					var g_data: Dictionary = parsed["games"][g_name]
					var canonical_slug = g_data.get("slug", g_name.to_lower().replace(":", "").replace("-", "_").replace(" ", "_").replace("'", "").replace(".", ""))
					_slug_map_cache[_normalize_key(g_name)] = canonical_slug
					_slug_map_cache[g_name.to_lower().replace("-", "_").replace(" ", "_")] = canonical_slug
					for alias in g_data.get("aliases", []):
						_slug_map_cache[_normalize_key(str(alias))] = canonical_slug
						_slug_map_cache[str(alias).to_lower().replace("-", "_").replace(" ", "_")] = canonical_slug
			fa.close()
			
	# 2. Check cached games directories
	var scan_dirs = ["user://cache/games"]
	for base_dir in scan_dirs:
		if not DirAccess.dir_exists_absolute(base_dir):
			continue
		var dir = DirAccess.open(base_dir)
		if not dir:
			continue
		dir.list_dir_begin()
		var folder = dir.get_next()
		while folder != "":
			if dir.current_is_dir() and folder != "." and folder != "..":
				var canonical_slug: String = folder
				_slug_map_cache[_normalize_key(folder)] = canonical_slug
				_slug_map_cache[folder.to_lower().replace("-", "_").replace(" ", "_")] = canonical_slug
				
				var setup_path = base_dir.path_join(folder).path_join("guided_setup.json")
				if FileAccess.file_exists(setup_path):
					var fa = FileAccess.open(setup_path, FileAccess.READ)
					if fa:
						var parsed = JSON.parse_string(fa.get_as_text())
						if parsed is Dictionary:
							var g_title = parsed.get("game_title", "")
							if g_title != "":
								_slug_map_cache[_normalize_key(g_title)] = canonical_slug
						fa.close()
			folder = dir.get_next()

# Helper to normalize game slug dynamically based on loaded game data & aliases
static func get_game_slug(game_name: String) -> String:
	_ensure_slug_cache()
	var key = _normalize_key(game_name)
	if _slug_map_cache.has(key):
		return _slug_map_cache[key]
	var fallback = game_name.to_lower().replace(":", "").replace("-", "_").replace(" ", "_").replace("é", "e").replace("'", "").replace(".", "")
	if _slug_map_cache.has(fallback):
		return _slug_map_cache[fallback]
	return fallback

# Helper to find a declarative guided_setup.json path for a game
static func _get_declarative_json_path(game_name: String) -> String:
	var slug = get_game_slug(game_name)
	var cache_path = "user://cache/games/" + slug + "/guided_setup.json"
	if FileAccess.file_exists(cache_path):
		return cache_path
	return ""

# Checks if a guided setup wizard is registered for the specified game
static func has_guided_setup(game_name: String) -> bool:
	if REGISTRY.has(game_name):
		return true
	return _get_declarative_json_path(game_name) != ""

static func get_default_config(game_name: String) -> Dictionary:
	var json_path = _get_declarative_json_path(game_name)
	if json_path == "":
		return {}
	var fa = FileAccess.open(json_path, FileAccess.READ)
	if not fa:
		return {}
	var parsed = JSON.parse_string(fa.get_as_text())
	fa.close()
	if parsed is Dictionary and parsed.get("default_config", {}) is Dictionary:
		return parsed["default_config"].duplicate(true)
	return {}

# Validates backend schema and instantiates the wizard if valid
static func validate_and_create(game_name: String, schema: Dictionary) -> Dictionary:
	if not has_guided_setup(game_name):
		return {"valid": false, "reason": "No guided setup registered for " + game_name, "wizard": null}
		
	if REGISTRY.has(game_name):
		var script_path = REGISTRY[game_name]
		var wizard_script = load(script_path)
		if wizard_script:
			if wizard_script.has_method("validate_schema"):
				var val_res = wizard_script.validate_schema(schema)
				if not val_res.get("valid", false):
					return {"valid": false, "reason": val_res.get("reason", "Incompatible schema"), "wizard": null}
			var wizard_instance = wizard_script.new()
			return {"valid": true, "reason": "", "wizard": wizard_instance}

	# Load Declarative JSON definition
	var json_path = _get_declarative_json_path(game_name)
	if json_path != "":
		var wizard = DeclarativeGuidedSetupScript.new()
		if wizard.load_from_file(json_path):
			var req_keys = wizard._get_required_schema_keys()
			if not schema.is_empty():
				var val_res = DeclarativeGuidedSetupScript.validate_schema_json(schema, req_keys)
				if not val_res.get("valid", false):
					return {"valid": false, "reason": val_res.get("reason", "Incompatible schema"), "wizard": null}
			return {"valid": true, "reason": "", "wizard": wizard}

	return {"valid": false, "reason": "Failed to create guided setup for " + game_name, "wizard": null}

# Register a new game wizard dynamically at runtime
static func register_game_wizard(game_name: String, script_path: String) -> void:
	REGISTRY[game_name] = script_path
