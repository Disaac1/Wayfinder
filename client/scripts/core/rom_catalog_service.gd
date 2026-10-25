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
