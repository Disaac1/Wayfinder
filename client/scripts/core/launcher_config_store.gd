class_name LauncherConfigStore
extends RefCounted

const CACHE_PATH: String = "user://cache/launcher_config.json"

var tools: Dictionary = {}
var games: Dictionary = {}

func load_local() -> void:
	tools.clear()
	games.clear()
	if not FileAccess.file_exists(CACHE_PATH):
		return

	var file_access := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not file_access:
		return
	var parsed: Variant = JSON.parse_string(file_access.get_as_text())
	file_access.close()
	if not parsed is Dictionary:
		return

	var cached_tools: Variant = parsed.get("tools", {})
	var cached_games: Variant = parsed.get("games", {})
	if cached_tools is Dictionary:
		tools.merge(cached_tools)
	if cached_games is Dictionary:
		games.merge(cached_games)

func load_remote() -> bool:
	var response: Dictionary = await NetworkManager.fetch_http("/api/launcher/config")
	var data: Variant = response.get("data")
	if response.has("error") or not data is Dictionary:
		return false

	var remote_tools: Variant = data.get("tools", {})
	var remote_games: Variant = data.get("games", {})
	if not remote_tools is Dictionary or not remote_games is Dictionary:
		return false

	tools.clear()
	games.clear()
	tools.merge(remote_tools)
	games.merge(remote_games)
	_save_cache()
	return true

func load() -> bool:
	load_local()
	if await load_remote():
		return true
	print("[LauncherConfigStore] Using cached launcher configuration because the backend was unavailable.")
	return not tools.is_empty() or not games.is_empty()

func _save_cache() -> void:
	DirAccess.make_dir_recursive_absolute("user://cache")
	var file_access := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file_access:
		file_access.store_string(JSON.stringify({"tools": tools, "games": games}, "  "))
		file_access.close()
