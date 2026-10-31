class_name RomCatalogService
extends RefCounted

const RomCatalogManager = preload("res://scripts/core/rom_catalog_manager.gd")

const CATALOG_PATH: String = "user://rom.json"
const FALLBACK_CATALOG_PATH: String = "user://roms.json"

var presets: Dictionary
var resolver
var catalog: Dictionary = {}

func _init(p_presets: Dictionary, p_resolver) -> void:
	presets = p_presets
	resolver = p_resolver

func load_catalog() -> void:
	_ensure_catalog_file()
	catalog = RomCatalogManager.load_catalog()

func _ensure_catalog_file() -> void:
	if FileAccess.file_exists(CATALOG_PATH) or FileAccess.file_exists(FALLBACK_CATALOG_PATH):
		return

	var default_catalog: Dictionary = {}
	for game_name in presets.keys():
		var preset: Dictionary = presets[game_name]
		var required_rom := str(preset.get("required_rom", ""))
		if required_rom != "":
			default_catalog[required_rom] = ""
	RomCatalogManager.save_catalog(default_catalog)

func get_download_entry(identifier: String) -> Dictionary:
	var raw_value: Variant = _find_raw_value(identifier)
	var default_key: String = str(catalog.get("default_key", catalog.get("key", ""))).strip_edges()

	if raw_value is String:
		var url: String = str(raw_value).strip_edges()
		if url != "":
			return {
				"url": url,
				"key": default_key,
				"encrypted": url.to_lower().contains(".enc") or default_key != ""
			}
	elif raw_value is Dictionary:
		var dictionary_url: String = str(raw_value.get("url", "")).strip_edges()
		var key: String = str(raw_value.get("key", default_key)).strip_edges()
		return {
			"url": dictionary_url,
			"key": key,
			"encrypted": raw_value.get("encrypted", false) or key != "" or dictionary_url.to_lower().contains(".enc")
		}
	return {}

func _find_raw_value(identifier: String) -> Variant:
	if catalog.has(identifier):
		return catalog[identifier]
	for key in catalog.keys():
		if str(key).nocasecmp_to(identifier) == 0:
			return catalog[key]

	var candidate_keys: Array[String] = [resolver.get_slug(identifier)]
	var target_norm: String = resolver.normalize(identifier)
	for game_key in presets.keys():
		var preset: Dictionary = presets[game_key]
		var game_name: String = str(preset.get("game_name", game_key))
		var required_rom: String = str(preset.get("required_rom", ""))
		var executable: String = str(preset.get("client_executable", preset.get("executable_name", "")))
		var game_slug: String = resolver.get_slug(game_name)
		var aliases: Array[String] = _combined_aliases(preset)
		var matched := identifier == required_rom or identifier == game_name or identifier == str(game_key) or identifier == executable
		matched = matched or resolver.normalize(game_name) == target_norm or game_slug == resolver.get_slug(identifier)
		if not matched:
			for alias in aliases:
				if identifier == alias or resolver.normalize(alias) == target_norm:
					matched = true
					break
		if not matched:
			continue

		candidate_keys.append(game_name)
		candidate_keys.append(str(game_key))
		candidate_keys.append(game_slug)
		if required_rom != "":
			candidate_keys.append(required_rom)
		if executable != "":
			candidate_keys.append(executable)
		candidate_keys.append_array(aliases)
		break

	for candidate in candidate_keys:
		if catalog.has(candidate):
			return catalog[candidate]
		var normalized_candidate: String = resolver.normalize(candidate)
		for key in catalog.keys():
			if str(key).nocasecmp_to(candidate) == 0 or resolver.normalize(str(key)) == normalized_candidate:
				return catalog[key]
	return null

func _combined_aliases(preset: Dictionary) -> Array[String]:
	var aliases: Array[String] = []
	for field in ["rom_aliases", "executable_aliases", "aliases"]:
		var values: Variant = preset.get(field, [])
		if values is Array:
			for value in values:
				var alias := str(value)
				if alias != "" and not aliases.has(alias):
					aliases.append(alias)
	return aliases

const USER_BASE_ROMS_DIR: String = "user://base_roms"
const USER_GAMES_DIR: String = "user://games"

var paths_config_ref: Dictionary = {}
var get_supported_extensions_cb: Callable

func set_context_references(p_paths_config: Dictionary, p_get_supported_extensions_cb: Callable) -> void:
	paths_config_ref = p_paths_config
	get_supported_extensions_cb = p_get_supported_extensions_cb

func find_existing_base_rom(rom_name: String) -> String:
	var game_slug: String = resolver.game_slug_for_rom(rom_name)
	var game_folder: String = USER_GAMES_DIR.path_join(game_slug)
	var target_unified: String = game_folder.path_join(rom_name)

	# Check if user already configured a path for this game/rom in paths_config
	for g_name in paths_config_ref.keys():
		var p_path: String = str(paths_config_ref[g_name])
		if p_path != "" and FileAccess.file_exists(p_path) and not p_path.to_lower().ends_with(".exe"):
			var p_base: String = p_path.get_file()
			var matches: bool = (p_base == rom_name or p_path == rom_name)
			if matches:
				if (p_path.contains("base_roms") or p_path.contains("base_rom")) and game_folder != "":
					if not FileAccess.file_exists(target_unified):
						DirAccess.make_dir_recursive_absolute(game_folder)
						var m_err: Error = DirAccess.copy_absolute(p_path, target_unified)
						if m_err == OK:
							print("[RomCatalogService] Auto-migrated paths_config legacy ROM to unified path: ", target_unified)
							DirAccess.remove_absolute(p_path)
							cleanup_legacy_base_roms_dir()
							paths_config_ref[g_name] = target_unified
							return target_unified
					else:
						DirAccess.remove_absolute(p_path)
						cleanup_legacy_base_roms_dir()
						paths_config_ref[g_name] = target_unified
						return target_unified
				return p_path

	var candidate_directories: Array[String] = [
		game_folder,
		ProjectSettings.globalize_path(game_folder),
		USER_BASE_ROMS_DIR,
		"user://base_rom",
		"user://roms",
		"user://",
		"res://base_roms",
		"res://base_rom",
		"res://",
		ProjectSettings.globalize_path(USER_BASE_ROMS_DIR),
		ProjectSettings.globalize_path("user://base_rom")
	]
	
	var games_da: DirAccess = DirAccess.open(USER_GAMES_DIR)
	if games_da:
		games_da.list_dir_begin()
		var g_sub: String = games_da.get_next()
		while g_sub != "":
			if games_da.current_is_dir() and not g_sub.begins_with("."):
				var sub_dir: String = USER_GAMES_DIR.path_join(g_sub)
				if not candidate_directories.has(sub_dir):
					candidate_directories.append(sub_dir)
			g_sub = games_da.get_next()
	
	var target_extension: String = rom_name.get_extension().to_lower()
	if target_extension == "":
		for game_name in presets.keys():
			var preset: Dictionary = presets[game_name]
			if game_name == rom_name or preset.get("game_name", "") == rom_name:
				target_extension = preset.get("required_rom", "").get_extension().to_lower()
				break
		
	for dir_path in candidate_directories:
		if dir_path == "" or not DirAccess.dir_exists_absolute(dir_path):
			continue
		var full_file_path: String = dir_path.path_join(rom_name)
		if FileAccess.file_exists(full_file_path):
			var chk_fa: FileAccess = FileAccess.open(full_file_path, FileAccess.READ)
			if chk_fa:
				var sz: int = chk_fa.get_length()
				chk_fa.close()
				if sz >= 32 or sz == 0:
					print("[RomCatalogService] Found exact ROM file at: ", full_file_path)
					if (dir_path.contains("base_roms") or dir_path.contains("base_rom")) and game_folder != "":
						if not FileAccess.file_exists(target_unified):
							DirAccess.make_dir_recursive_absolute(game_folder)
							var mig_err: Error = DirAccess.copy_absolute(full_file_path, target_unified)
							if mig_err == OK:
								print("[RomCatalogService] Auto-migrated legacy ROM to unified game path: ", target_unified)
								DirAccess.remove_absolute(full_file_path)
								cleanup_legacy_base_roms_dir()
								return target_unified
						else:
							DirAccess.remove_absolute(full_file_path)
							cleanup_legacy_base_roms_dir()
							return target_unified
					return full_file_path
			
	return _fuzzy_search_matching_rom(candidate_directories, rom_name, target_extension)

func migrate_all_legacy_base_roms() -> void:
	var legacy_dirs: Array[String] = [USER_BASE_ROMS_DIR, "user://base_rom", "user://roms"]
	for l_dir in legacy_dirs:
		if not DirAccess.dir_exists_absolute(l_dir):
			continue
		var da: DirAccess = DirAccess.open(l_dir)
		if not da:
			continue
		da.list_dir_begin()
		var fn: String = da.get_next()
		while fn != "":
			if not da.current_is_dir() and not fn.begins_with("."):
				var old_path: String = l_dir.path_join(fn)
				var slug: String = resolver.game_slug_for_rom(fn)
				if slug != "":
					var game_folder: String = USER_GAMES_DIR.path_join(slug)
					var target_path: String = game_folder.path_join(fn)
					if not FileAccess.file_exists(target_path):
						DirAccess.make_dir_recursive_absolute(game_folder)
						var err: Error = DirAccess.copy_absolute(old_path, target_path)
						if err == OK:
							print("[RomCatalogService] Auto-migrated legacy base ROM to: ", target_path)
							DirAccess.remove_absolute(old_path)
					else:
						DirAccess.remove_absolute(old_path)
						print("[RomCatalogService] Removed redundant legacy ROM (already in games/): ", old_path)
			fn = da.get_next()
	cleanup_legacy_base_roms_dir()

func cleanup_legacy_base_roms_dir() -> void:
	var legacy_dirs: Array[String] = [USER_BASE_ROMS_DIR, "user://base_rom", "user://roms"]
	for l_dir in legacy_dirs:
		if DirAccess.dir_exists_absolute(l_dir):
			var da: DirAccess = DirAccess.open(l_dir)
			if da:
				da.list_dir_begin()
				var fn: String = da.get_next()
				var is_empty: bool = true
				while fn != "":
					if not fn.begins_with("."):
						is_empty = false
						break
					fn = da.get_next()
				if is_empty:
					DirAccess.remove_absolute(l_dir)
					print("[RomCatalogService] Cleaned up empty legacy directory: ", l_dir)

func _fuzzy_search_matching_rom(candidate_directories: Array[String], rom_name: String, target_extension: String) -> String:
	var search_keywords: Array[String] = []
	var base_clean: String = rom_name.get_basename().to_lower()
	for sep in [" ", "_", "-", "(", ")", "[", "]", "."]:
		base_clean = base_clean.replace(sep, " ")
		
	var generic_tokens: Array[String] = [
		"usa", "eur", "europe", "japan", "jap", "rev", "version", "ver", 
		"the", "and", "edition", "v1", "v2", "beta", "game", "gba", "snes", "n64"
	]
	
	for token in base_clean.split(" ", false):
		var t: String = token.strip_edges()
		if t.length() >= 3 and not generic_tokens.has(t) and not search_keywords.has(t):
			search_keywords.append(t)

	for game_name in presets.keys():
		var preset: Dictionary = presets[game_name]
		var req: String = preset.get("required_rom", "")
		var aliases: Array = preset.get("rom_aliases", [])
		var matches_preset: bool = (req == rom_name)
		if not matches_preset:
			for a in aliases:
				if str(a) == rom_name:
					matches_preset = true
					break
		if matches_preset:
			var g_clean: String = str(game_name).to_lower()
			for sep in [" ", "_", "-", "(", ")", "[", "]", ":"]:
				g_clean = g_clean.replace(sep, " ")
			for token in g_clean.split(" ", false):
				var t: String = token.strip_edges()
				if t.length() >= 3 and not generic_tokens.has(t) and not search_keywords.has(t):
					search_keywords.append(t)

	if search_keywords.is_empty():
		return ""

	var supported_extensions: Array[String] = []
	if get_supported_extensions_cb.is_valid():
		var exts = get_supported_extensions_cb.call()
		if exts is Array:
			for e in exts:
				supported_extensions.append(str(e))
	if not supported_extensions.has("zip"):
		supported_extensions.append("zip")
	if target_extension != "" and not supported_extensions.has(target_extension):
		supported_extensions.append(target_extension)

	for dir_path in candidate_directories:
		if dir_path == "" or not DirAccess.dir_exists_absolute(dir_path):
			continue
		var dir_access: DirAccess = DirAccess.open(dir_path)
		if dir_access:
			dir_access.list_dir_begin()
			var file_item: String = dir_access.get_next()
			while file_item != "":
				if not dir_access.current_is_dir():
					var item_ext: String = file_item.get_extension().to_lower()
					if supported_extensions.has(item_ext):
						var item_lower: String = file_item.to_lower()
						for keyword in search_keywords:
							if item_lower.contains(keyword):
								var found_path: String = dir_path.path_join(file_item)
								print("[RomCatalogService] Discovered matching ROM file (", file_item, ") at: ", found_path)
								if (found_path.contains("base_roms") or found_path.contains("base_rom")):
									var f_slug: String = resolver.game_slug_for_rom(file_item)
									if f_slug == "":
										f_slug = resolver.game_slug_for_rom(rom_name)
									var f_folder: String = USER_GAMES_DIR.path_join(f_slug)
									var target_unified: String = f_folder.path_join(file_item)
									if not FileAccess.file_exists(target_unified):
										DirAccess.make_dir_recursive_absolute(f_folder)
										var mig_err: Error = DirAccess.copy_absolute(found_path, target_unified)
										if mig_err == OK:
											print("[RomCatalogService] Auto-migrated fuzzy legacy ROM to unified path: ", target_unified)
											DirAccess.remove_absolute(found_path)
											cleanup_legacy_base_roms_dir()
											return target_unified
									else:
										DirAccess.remove_absolute(found_path)
										cleanup_legacy_base_roms_dir()
										return target_unified
								return found_path
				file_item = dir_access.get_next()
				
	return ""
