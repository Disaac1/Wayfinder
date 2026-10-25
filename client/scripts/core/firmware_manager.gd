class_name FirmwareManager
extends RefCounted

var game_slug_callback: Callable
var inject_config_callback: Callable
var user_games_dir: String

func _init(p_game_slug_callback: Callable, p_inject_config_callback: Callable, p_user_games_dir: String) -> void:
	game_slug_callback = p_game_slug_callback
	inject_config_callback = p_inject_config_callback
	user_games_dir = p_user_games_dir

func ensure(node: Node, preset_config: Dictionary, emulator_exe_path: String, rom_path: String, callback: Callable) -> void:
	var emulator_dir: String = ProjectSettings.globalize_path(emulator_exe_path).get_base_dir() if emulator_exe_path != "" else ProjectSettings.globalize_path("user://tools/BizHawk")
	var firmware_list: Array = []
	var raw_firmware = preset_config.get("required_firmware")
	if raw_firmware is Array:
		firmware_list = raw_firmware
	elif raw_firmware is Dictionary and not raw_firmware.is_empty():
		firmware_list = [raw_firmware]
	if firmware_list.is_empty():
		callback.call(true, "")
		return
	var game_name: String = str(preset_config.get("game_name", ""))
	var game_slug: String = str(game_slug_callback.call(game_name)) if game_name != "" else ""
	_process_queue(node, firmware_list, 0, emulator_dir, game_slug, rom_path, callback)

func _process_queue(node: Node, firmware_list: Array, index: int, emulator_dir: String, game_slug: String, rom_path: String, callback: Callable) -> void:
	if index >= firmware_list.size():
		callback.call(true, emulator_dir)
		return
	var firmware = firmware_list[index]
	if not firmware is Dictionary:
		_process_queue(node, firmware_list, index + 1, emulator_dir, game_slug, rom_path, callback)
		return
	var file_name: String = str(firmware.get("file_name", firmware.get("filename", "")))
	if file_name == "":
		_process_queue(node, firmware_list, index + 1, emulator_dir, game_slug, rom_path, callback)
		return
	var destination: String = str(firmware.get("dest_subpath", "Firmware/" + file_name))
	var aliases: Array = firmware.get("dest_aliases", firmware.get("aliases", []))
	var display_name: String = str(firmware.get("name", firmware.get("display_name", file_name)))
	var download_url: String = str(firmware.get("download_url", ""))
	var emulator_config: Dictionary = firmware.get("emulator_config", {})
	var target_path: String = emulator_dir.path_join(destination)
	DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())

	var existing_source: String = _find_existing(emulator_dir, target_path, aliases)
	if existing_source != "":
		_copy_firmware(existing_source, target_path, aliases, emulator_dir)
		inject_config_callback.call(emulator_dir, emulator_config)
		_process_queue(node, firmware_list, index + 1, emulator_dir, game_slug, rom_path, callback)
		return

	var candidate: String = _find_candidate(file_name, aliases, game_slug, rom_path)
	if candidate != "":
		_copy_firmware(candidate, target_path, aliases, emulator_dir)
		if game_slug != "":
			var game_destination: String = ProjectSettings.globalize_path(user_games_dir.path_join(game_slug).path_join(file_name))
			if not FileAccess.file_exists(game_destination):
				DirAccess.make_dir_recursive_absolute(game_destination.get_base_dir())
				DirAccess.copy_absolute(candidate, game_destination)
		inject_config_callback.call(emulator_dir, emulator_config)
		_process_queue(node, firmware_list, index + 1, emulator_dir, game_slug, rom_path, callback)
		return

	if download_url != "" and not download_url.begins_with("http"):
		download_url = NetworkManager.get_http_url() + (download_url if download_url.begins_with("/") else "/" + download_url)
	if download_url == "":
		callback.call(false, "No download URL configured for required firmware: " + file_name)
		return
	if is_instance_valid(node) and "launch_instructions" in node and is_instance_valid(node.launch_instructions):
		node.launch_instructions.text = "Installing required firmware (" + file_name + ")...\n\nDownloading " + display_name + " from server..."
	var http: HTTPRequest = HTTPRequest.new()
	http.use_threads = true
	var temp_path: String = ProjectSettings.globalize_path("user://temp_fw_" + file_name)
	http.download_file = temp_path
	if not is_instance_valid(node):
		callback.call(false, "Invalid node context for firmware download")
		return
	node.add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 0):
			_copy_firmware(temp_path, target_path, aliases, emulator_dir)
			if game_slug != "":
				var game_destination: String = ProjectSettings.globalize_path(user_games_dir.path_join(game_slug).path_join(file_name))
				DirAccess.make_dir_recursive_absolute(game_destination.get_base_dir())
				DirAccess.copy_absolute(temp_path, game_destination)
			if FileAccess.file_exists(temp_path):
				DirAccess.remove_absolute(temp_path)
			inject_config_callback.call(emulator_dir, emulator_config)
			_process_queue(node, firmware_list, index + 1, emulator_dir, game_slug, rom_path, callback)
		else:
			if FileAccess.file_exists(temp_path):
				DirAccess.remove_absolute(temp_path)
			callback.call(false, "Could not obtain required firmware: " + file_name)
	)
	var request_error: Error = http.request(download_url)
	if request_error != OK:
		http.queue_free()
		callback.call(false, "Failed to start firmware download request for " + file_name)

func _find_existing(emulator_dir: String, target_path: String, aliases: Array) -> String:
	if FileAccess.file_exists(target_path):
		return target_path
	for alias in aliases:
		var alias_path: String = emulator_dir.path_join(str(alias))
		if FileAccess.file_exists(alias_path):
			return alias_path
	return ""

func _find_candidate(file_name: String, aliases: Array, game_slug: String, rom_path: String) -> String:
	var candidates: Array[String] = []
	if game_slug != "":
		candidates.append(ProjectSettings.globalize_path(user_games_dir.path_join(game_slug).path_join(file_name)))
		for alias in aliases:
			candidates.append(ProjectSettings.globalize_path(user_games_dir.path_join(game_slug).path_join(str(alias).get_file())))
	if rom_path != "":
		var rom_dir: String = rom_path.get_base_dir()
		candidates.append(rom_dir.path_join(file_name))
		for alias in aliases:
			candidates.append(rom_dir.path_join(str(alias).get_file()))
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""

func _copy_firmware(source: String, target_path: String, aliases: Array, emulator_dir: String) -> void:
	if source != target_path and not FileAccess.file_exists(target_path):
		DirAccess.copy_absolute(source, target_path)
	for alias in aliases:
		var alias_path: String = emulator_dir.path_join(str(alias))
		if not FileAccess.file_exists(alias_path):
			DirAccess.make_dir_recursive_absolute(alias_path.get_base_dir())
			DirAccess.copy_absolute(source, alias_path)
