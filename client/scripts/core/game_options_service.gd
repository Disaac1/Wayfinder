class_name GameOptionsService
extends RefCounted

# --- DEPENDENCIES ---
const GuidedSetupRegistry = preload("res://scripts/guided_setup/guided_setup_registry.gd")

# --- CONSTANTS ---
const GAMES_CACHE_PATH: String = "user://cache/games_list.json"
const GAMES_CACHE_DIR: String = "user://cache"
const GUIDED_SETUP_CACHE_DIR_PREFIX: String = "user://cache/games/"

# --- SIGNALS ---
signal games_list_updated(games: Array)
signal options_schema_loaded(game_name: String, schema: Dictionary)
signal guided_setup_cached(game_name: String)
signal config_changed(game_name: String, config: Dictionary)

# --- STATE VARIABLES ---
var all_games: Array = []
var options_cache: Dictionary = {}
var config_states: Dictionary = {}
var use_guided_setup_mode: Dictionary = {}
var active_config_game: String = ""

# =====================================================================
#                      /api/games CACHING & FETCHING
# =====================================================================

func load_cached_games_list() -> Array:
	if FileAccess.file_exists(GAMES_CACHE_PATH):
		var file: FileAccess = FileAccess.open(GAMES_CACHE_PATH, FileAccess.READ)
		if file:
			var json_string: String = file.get_as_text()
			file.close()
			var json: JSON = JSON.new()
			if json.parse(json_string) == OK:
				if json.data is Array:
					all_games = json.data
				elif json.data is Dictionary and json.data.has("games") and json.data["games"] is Array:
					all_games = json.data["games"]
				elif json.data is Dictionary and json.data.has("list") and json.data["list"] is Array:
					all_games = json.data["list"]
	return all_games

func fetch_games_list() -> Array:
	var response: Dictionary = await NetworkManager.fetch_http("/api/games")
	if not response.has("error"):
		var raw_data = response.get("data")
		var extracted: Array = []
		if raw_data is Array:
			extracted = raw_data
		elif raw_data is Dictionary:
			if raw_data.has("games") and raw_data["games"] is Array:
				extracted = raw_data["games"]
			elif raw_data.has("list") and raw_data["list"] is Array:
				extracted = raw_data["list"]
		
		if not extracted.is_empty():
			all_games = extracted
			DirAccess.make_dir_recursive_absolute(GAMES_CACHE_DIR)
			var file: FileAccess = FileAccess.open(GAMES_CACHE_PATH, FileAccess.WRITE)
			if file:
				file.store_string(JSON.stringify(all_games))
				file.close()
			print("[GameOptionsService] Successfully loaded %d games from backend /api/games" % all_games.size())
			games_list_updated.emit(all_games)
	return all_games

func clear_games_cache() -> void:
	if FileAccess.file_exists(GAMES_CACHE_PATH):
		DirAccess.remove_absolute(GAMES_CACHE_PATH)
	all_games.clear()

# =====================================================================
#                 /api/options/<game> SCHEMA FETCHING
# =====================================================================

func get_options_schema(game_name: String) -> Dictionary:
	if options_cache.has(game_name):
		return options_cache[game_name]
		
	var endpoint: String = "/api/options/" + game_name.uri_encode()
	var response: Dictionary = await NetworkManager.fetch_http(endpoint)
	if response.has("error"):
		print("[GameOptionsService] Failed to load options schema for '%s': %s" % [game_name, str(response.get("error"))])
		return {}
	if response.has("data") and response.data is Dictionary:
		options_cache[game_name] = response.data
		options_schema_loaded.emit(game_name, response.data)
		return response.data
		
	print("[GameOptionsService] Failed to load options schema for '%s': response did not contain a valid schema object." % game_name)
	return {}

func clear_options_cache() -> void:
	options_cache.clear()

# =====================================================================
#                     GUIDED SETUP CACHING
# =====================================================================

func ensure_remote_guided_setup(game_name: String) -> void:
	var slug: String = GuidedSetupRegistry.get_game_slug(game_name)
	var cache_dir: String = GUIDED_SETUP_CACHE_DIR_PREFIX + slug
	var cache_path: String = cache_dir + "/guided_setup.json"
	var had_cached_setup: bool = GuidedSetupRegistry.has_guided_setup(game_name)
	
	var res: Dictionary = await NetworkManager.fetch_http("/api/games/" + slug + "/guided-setup")
	if res.has("error"):
		print("[GuidedSetup] Failed to refresh setup for '%s' (slug '%s'): %s%s" % [
			game_name,
			slug,
			str(res.get("error")),
			". Using cached setup." if had_cached_setup else ""
		])
		return
	if not res.has("data") or not (res.get("data") is Dictionary):
		print("[GuidedSetup] Failed to refresh setup for '%s' (slug '%s'): response did not contain a valid setup object.%s" % [
			game_name,
			slug,
			" Using cached setup." if had_cached_setup else ""
		])
		return

	if res.get("data").is_empty():
		print("[GuidedSetup] Failed to refresh setup for '%s' (slug '%s'): server returned an empty setup object.%s" % [
			game_name,
			slug,
			" Using cached setup." if had_cached_setup else ""
		])
		return

	if not res.get("data").has("steps"):
		print("[GuidedSetup] Failed to refresh setup for '%s' (slug '%s'): setup is missing its steps.%s" % [
			game_name,
			slug,
			" Using cached setup." if had_cached_setup else ""
		])
		return

	DirAccess.make_dir_recursive_absolute(cache_dir)
	var fa: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(res.data, "  "))
		fa.close()
		print("[GuidedSetup] Refreshed cached setup for: ", game_name)
		guided_setup_cached.emit(game_name)
	else:
		print("[GuidedSetup] Failed to cache setup for '%s' at '%s': could not open the cache file." % [game_name, cache_path])

func has_cached_guided_setup(game_name: String) -> bool:
	if GuidedSetupRegistry.has_guided_setup(game_name):
		return true
	var slug: String = GuidedSetupRegistry.get_game_slug(game_name)
	return FileAccess.file_exists(GUIDED_SETUP_CACHE_DIR_PREFIX + slug + "/guided_setup.json")

# =====================================================================
#                 CONFIG STATES DICTIONARY MANAGEMENT
# =====================================================================

func get_config(game_name: String) -> Dictionary:
	return config_states.get(game_name, {})

func set_config(game_name: String, config: Dictionary) -> void:
	config_states[game_name] = config
	config_changed.emit(game_name, config)

func remove_config(game_name: String) -> void:
	config_states.erase(game_name)

func has_config(game_name: String) -> bool:
	return config_states.has(game_name)

func is_guided_setup_mode(game_name: String) -> bool:
	return use_guided_setup_mode.get(game_name, true)

func set_guided_setup_mode(game_name: String, enabled: bool) -> void:
	use_guided_setup_mode[game_name] = enabled

func prepopulate_default_options(game_name: String) -> void:
	if not config_states.has(game_name):
		config_states[game_name] = {}
	var schema_dict: Dictionary = await get_options_schema(game_name)
	var options_list: Array = schema_dict.get("options", [])
	for option_def in options_list:
		var opt_name: String = option_def.get("name", "")
		if not config_states[game_name].has(opt_name):
			config_states[game_name][opt_name] = option_def.get("default")
	if options_list.is_empty() and GuidedSetupRegistry.has_guided_setup(game_name):
		var guided_defaults: Dictionary = GuidedSetupRegistry.get_default_config(game_name)
		for opt_name in guided_defaults:
			if not config_states[game_name].has(opt_name):
				config_states[game_name][opt_name] = guided_defaults[opt_name]

func clear() -> void:
	config_states.clear()
	use_guided_setup_mode.clear()
	active_config_game = ""

