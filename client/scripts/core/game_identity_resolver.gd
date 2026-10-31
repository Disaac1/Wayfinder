class_name GameIdentityResolver
extends RefCounted

var presets: Dictionary

func _init(p_presets: Dictionary = {}) -> void:
	presets = p_presets

static func normalize(value: String) -> String:
	var result := value.to_lower()
	for character in [":", "-", "_", " ", "'", ".", "(", ")", "[", "]", "é"]:
		result = result.replace(character, "e" if character == "é" else "")
	return result

static func slugify(value: String) -> String:
	var result := value.to_lower()
	result = result.replace(":", "")
	result = result.replace("-", "_")
	result = result.replace(" ", "_")
	result = result.replace("é", "e")
	result = result.replace("'", "")
	result = result.replace(".", "")
	while result.contains("__"):
		result = result.replace("__", "_")
	return result.strip_edges().trim_prefix("_").trim_suffix("_")

static func resolve_slug(game_name: String, preset: Dictionary = {}) -> String:
	if not preset.is_empty():
		var configured_slug := str(preset.get("slug", ""))
		var canonical_name := str(preset.get("game_name", ""))
		var target := normalize(game_name)
		if canonical_name != "" and normalize(canonical_name) == target:
			return configured_slug if configured_slug != "" else slugify(canonical_name)
		for alias in _string_array(preset.get("aliases", [])):
			if normalize(alias) == target:
				return configured_slug if configured_slug != "" else (slugify(canonical_name) if canonical_name != "" else slugify(game_name))
		if configured_slug != "":
			return configured_slug
		if canonical_name != "":
			return slugify(canonical_name)
	return slugify(game_name)

func get_slug(game_name: String) -> String:
	var target := normalize(game_name)
	for key in presets.keys():
		var preset: Dictionary = presets[key]
		var canonical_name := str(preset.get("game_name", key))
		var configured_slug := str(preset.get("slug", ""))
		if normalize(str(key)) == target or normalize(canonical_name) == target:
			return configured_slug if configured_slug != "" else slugify(canonical_name)
		for alias in _string_array(preset.get("aliases", [])):
			if normalize(alias) == target:
				return configured_slug if configured_slug != "" else slugify(canonical_name)
	return slugify(game_name)

func get_preset(game_name: String) -> Dictionary:
	if presets.has(game_name) and presets[game_name] is Dictionary:
		return presets[game_name]

	var target := normalize(game_name)
	for key in presets.keys():
		var preset: Dictionary = presets[key]
		if normalize(str(key)) == target:
			return preset
		if normalize(str(preset.get("game_name", ""))) == target:
			return preset
		for alias in _string_array(preset.get("aliases", [])):
			if normalize(alias) == target:
				return preset

	return {
		"game_name": game_name,
		"support_tier": 3,
		"launch_mode": "ap_client",
		"client_tool": "archipelago_client",
		"client_component": "Archipelago Launcher",
		"auto_connect": true,
		"install_instructions": "Community APWorld: Select your clean base ROM or executable if required. Lodestone will open Archipelago Launcher and connect automatically."
	}

func has_preset(game_name: String) -> bool:
	var target := normalize(game_name)
	for key in presets.keys():
		var preset: Dictionary = presets[key]
		if normalize(str(key)) == target or normalize(str(preset.get("game_name", ""))) == target:
			return true
		for alias in _string_array(preset.get("aliases", [])):
			if normalize(alias) == target:
				return true
	return false

func game_slug_for_rom(rom_name: String) -> String:
	for key in presets.keys():
		var preset: Dictionary = presets[key]
		if str(preset.get("required_rom", "")) == rom_name or str(preset.get("required_audio_rom", "")) == rom_name:
			return get_slug(str(preset.get("game_name", key)))
		for alias in _string_array(preset.get("rom_aliases", [])):
			if alias == rom_name:
				return get_slug(str(preset.get("game_name", key)))

	var normalized_rom := normalize(rom_name)
	for key in presets.keys():
		var preset: Dictionary = presets[key]
		var title := str(preset.get("game_name", key))
		if normalized_rom.contains(normalize(title)):
			return get_slug(title)
	return get_slug(rom_name.get_basename())

static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
