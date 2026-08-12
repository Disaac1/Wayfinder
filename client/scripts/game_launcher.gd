class_name GameLauncher
extends RefCounted

# --- CONSTANTS ---
const DEFAULT_ARCHIPELAGO_DOWNLOAD_URL: String = "https://github.com/ArchipelagoMW/Archipelago/releases/download/0.6.7/Setup.Archipelago.0.6.7.exe"
const DEFAULT_BIZHAWK_PREREQS_URL: String = "https://github.com/TASEmulators/BizHawk-Prereqs/releases/download/2.4.8_1/bizhawk_prereqs_v2.4.8_1.zip"

const ZIP_HEADER_BYTE_1: int = 0x50  # 'P'
const ZIP_HEADER_BYTE_2: int = 0x4B  # 'K'
const BYTES_PER_MB: float = 1024.0 * 1024.0

const USER_TOOLS_DIR: String = "user://tools"
const USER_BASE_ROMS_DIR: String = "user://base_roms"
const USER_SAVES_DIR: String = "user://saves"
const USER_PATHS_CONFIG_PATH: String = "user://paths_config.json"
const USER_ROM_CATALOG_PATH: String = "user://rom.json"
const LOCAL_ROM_TEMPLATE_PATH: String = "res://data/rom_template.json"
const LOCAL_LAUNCHER_CONFIG_PATH: String = "res://data/game_launcher_config.json"

# State attributes
var launcher_tools: Dictionary = {}
var launcher_presets: Dictionary = {}
var paths_config: Dictionary = {}
var roms_catalog: Dictionary = {}
var _active_browse_field: String = ""


# =====================================================================
#                     CONFIG & CATALOG LOADING
# =====================================================================

func load_launcher_config() -> void:
	var response: Dictionary = await NetworkManager.fetch_http("/api/launcher/config")
	if not response.has("error") and response.get("data") is Dictionary:
		var config_data: Dictionary = response.data
		launcher_tools = config_data.get("tools", {})
		launcher_presets = config_data.get("games", {})
		print("[Launcher] Loaded ", launcher_presets.size(), " games and ", launcher_tools.size(), " shared tools from backend REST API.")
		return

	if FileAccess.file_exists(LOCAL_LAUNCHER_CONFIG_PATH):
		var file_access: FileAccess = FileAccess.open(LOCAL_LAUNCHER_CONFIG_PATH, FileAccess.READ)
		if file_access:
			var parsed_json: Variant = JSON.parse_string(file_access.get_as_text())
			if parsed_json is Dictionary:
				if parsed_json.has("games"):
					launcher_presets = parsed_json.get("games", {})
					launcher_tools = parsed_json.get("tools", {})
				else:
					launcher_presets = parsed_json
			file_access.close()
			print("[Launcher] Loaded ", launcher_presets.size(), " launcher presets from local bundle.")

func load_roms_catalog() -> void:
	_ensure_rom_catalog_file_exists()
				
	var file_access: FileAccess = FileAccess.open(USER_ROM_CATALOG_PATH, FileAccess.READ)
	if file_access:
		var parsed_json: Variant = JSON.parse_string(file_access.get_as_text())
		if parsed_json is Dictionary:
			roms_catalog = parsed_json
			print("[Launcher] Loaded user ROMs catalog: ", roms_catalog)
		file_access.close()

func _ensure_rom_catalog_file_exists() -> void:
	if FileAccess.file_exists(USER_ROM_CATALOG_PATH):
		return
		
	if FileAccess.file_exists(LOCAL_ROM_TEMPLATE_PATH):
		var source_file: FileAccess = FileAccess.open(LOCAL_ROM_TEMPLATE_PATH, FileAccess.READ)
		var dest_file: FileAccess = FileAccess.open(USER_ROM_CATALOG_PATH, FileAccess.WRITE)
		if source_file and dest_file:
			dest_file.store_string(source_file.get_as_text())
			dest_file.close()
			source_file.close()
			print("[Launcher] Copied rom_template.json to user://rom.json")
	else:
		var default_file: FileAccess = FileAccess.open(USER_ROM_CATALOG_PATH, FileAccess.WRITE)
		if default_file:
			default_file.store_string(JSON.stringify({"Pokemon - Emerald Version (USA).gba": ""}, "  "))
			default_file.close()

func load_paths_config() -> void:
	if FileAccess.file_exists(USER_PATHS_CONFIG_PATH):
		var file_access: FileAccess = FileAccess.open(USER_PATHS_CONFIG_PATH, FileAccess.READ)
		if file_access:
			var parsed_json: Variant = JSON.parse_string(file_access.get_as_text())
			if parsed_json is Dictionary:
				paths_config = parsed_json
				print("[Launcher] Loaded user paths configuration.")
			file_access.close()

func save_paths_config() -> void:
	var file_access: FileAccess = FileAccess.open(USER_PATHS_CONFIG_PATH, FileAccess.WRITE)
	if file_access:
		file_access.store_string(JSON.stringify(paths_config, "  "))
		file_access.close()
		print("[Launcher] Saved user paths configuration.")


# =====================================================================
#                   ROM UNPACKING & AUTO-DISCOVERY
# =====================================================================

func unpack_rom_zip(zip_file_path: String, rom_name: String, callback: Callable) -> void:
	var zip_reader: ZIPReader = ZIPReader.new()
	var open_err: Error = zip_reader.open(zip_file_path)
	if open_err != OK:
		callback.call(false, "Failed to open ROM zip archive: " + zip_file_path)
		return
		
	var archive_files: PackedStringArray = zip_reader.get_files()
	var rom_data: PackedByteArray = PackedByteArray()
	var target_extension: String = rom_name.get_extension().to_lower()
	var extracted_filename: String = ""
	
	for file_entry in archive_files:
		var file_ext: String = file_entry.get_extension().to_lower()
		if file_ext == target_extension or file_entry.to_lower().contains(".gba") or file_entry.to_lower().contains(".sfc"):
			rom_data = zip_reader.read_file(file_entry)
			extracted_filename = file_entry
			break
			
	if rom_data.is_empty() and not archive_files.is_empty():
		for file_entry in archive_files:
			if not file_entry.ends_with("/"):
				rom_data = zip_reader.read_file(file_entry)
				extracted_filename = file_entry
				break
				
	zip_reader.close()
	
	var target_destination: String = USER_BASE_ROMS_DIR.path_join(rom_name)
	if zip_file_path != target_destination and FileAccess.file_exists(zip_file_path):
		DirAccess.remove_absolute(zip_file_path)
		
	if rom_data.is_empty():
		callback.call(false, "No valid ROM file found inside downloaded ZIP archive.")
		return
		
	var output_file: FileAccess = FileAccess.open(target_destination, FileAccess.WRITE)
	if output_file:
		output_file.store_buffer(rom_data)
		output_file.close()
		print("[Launcher] Extracted base ROM (", rom_data.size(), " bytes) from ", extracted_filename, " to: ", target_destination)
		callback.call(true, target_destination)
	else:
		callback.call(false, "Failed to write extracted ROM to destination: " + target_destination)

func find_existing_base_rom(rom_name: String) -> String:
	var candidate_directories: Array[String] = [
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
	
	var target_extension: String = rom_name.get_extension().to_lower()
	if target_extension == "":
		target_extension = "gba"
		
	for dir_path in candidate_directories:
		if dir_path == "" or not DirAccess.dir_exists_absolute(dir_path):
			continue
		var full_file_path: String = dir_path.path_join(rom_name)
		if FileAccess.file_exists(full_file_path):
			print("[Launcher] Found exact ROM file at: ", full_file_path)
			return full_file_path
			
	return _fuzzy_search_matching_rom(candidate_directories, rom_name, target_extension)

func _fuzzy_search_matching_rom(candidate_directories: Array[String], rom_name: String, target_extension: String) -> String:
	var search_keywords: Array[String] = [rom_name.get_basename().to_lower(), "emerald", "pokemon", "zelda", "mario", "sm64"]
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
					if item_ext == target_extension or item_ext == "gba" or item_ext == "sfc" or item_ext == "z64" or item_ext == "n64" or item_ext == "zip":
						var item_lower: String = file_item.to_lower()
						for keyword in search_keywords:
							if item_lower.contains(keyword):
								var found_path: String = dir_path.path_join(file_item)
								print("[Launcher] Discovered matching ROM file (", file_item, ") at: ", found_path)
								return found_path
				file_item = dir_access.get_next()
				
	return ""

func ensure_rom_exists_or_download(node: Node, rom_name: String, callback: Callable) -> void:
	if rom_name.strip_edges() == "":
		print("[Launcher] Game specifies no required ROM. Skipping ROM download/check.")
		callback.call(true, "")
		return
		
	DirAccess.make_dir_recursive_absolute(USER_BASE_ROMS_DIR)
	var target_rom_path: String = USER_BASE_ROMS_DIR.path_join(rom_name)
	
	var existing_rom: String = find_existing_base_rom(rom_name)
	if existing_rom != "":
		_handle_existing_base_rom(node, existing_rom, target_rom_path, rom_name, callback)
		return
		
	var catalog_url: String = roms_catalog.get(rom_name, "").strip_edges()
	if catalog_url == "":
		callback.call(false, "Base ROM \"" + rom_name + "\" is missing. Please configure a download link in user://rom.json or place the file directly in user://base_roms/")
		return
		
	if catalog_url.begins_with("file://"):
		_handle_local_file_url(node, catalog_url, target_rom_path, rom_name, callback)
		return
		
	_download_base_rom_http(node, catalog_url, USER_BASE_ROMS_DIR, rom_name, target_rom_path, callback)

func _handle_existing_base_rom(node: Node, found_rom: String, target_rom_path: String, rom_name: String, callback: Callable) -> void:
	var verified_path: String = found_rom
	if found_rom != target_rom_path and not FileAccess.file_exists(target_rom_path):
		var copy_err: Error = DirAccess.copy_absolute(found_rom, target_rom_path)
		if copy_err == OK:
			print("[Launcher] Cached ROM copy from ", found_rom, " to ", target_rom_path)
			verified_path = target_rom_path
		else:
			print("[Launcher Warning] Could not copy ROM to user://base_roms, using existing: ", found_rom)
	
	var test_file: FileAccess = FileAccess.open(verified_path, FileAccess.READ)
	if test_file:
		var header_bytes: PackedByteArray = test_file.get_buffer(2)
		test_file.close()
		if header_bytes.size() >= 2 and header_bytes[0] == ZIP_HEADER_BYTE_1 and header_bytes[1] == ZIP_HEADER_BYTE_2:
			print("[Launcher] Found ZIP header in existing ROM file. Unpacking...")
			unpack_rom_zip(verified_path, rom_name, callback)
			return
			
	print("[Launcher] Base ROM verified and ready: ", verified_path)
	callback.call(true, verified_path)

func _handle_local_file_url(node: Node, catalog_url: String, target_rom_path: String, rom_name: String, callback: Callable) -> void:
	var source_path: String = catalog_url.replace("file://", "")
	if OS.get_name() == "Windows" and (source_path.begins_with("/") or source_path.begins_with("\\")):
		source_path = source_path.substr(1)
	var copy_err: Error = DirAccess.copy_absolute(source_path, target_rom_path)
	if copy_err == OK:
		print("[Launcher] Local ROM copy succeeded: ", target_rom_path)
		ensure_rom_exists_or_download(node, rom_name, callback)
	else:
		callback.call(false, "Failed to copy local ROM file from: " + source_path + " (Error: " + str(copy_err) + ")")

func _download_base_rom_http(node: Node, download_url: String, base_roms_dir: String, rom_name: String, target_rom_path: String, callback: Callable) -> void:
	print("[Launcher] Downloading base ROM from: ", download_url)
	_set_overlay_downloading_state(node)
		
	var is_zip_url: bool = download_url.to_lower().contains(".zip")
	var temp_download_path: String = base_roms_dir.path_join("temp_download_" + rom_name.validate_filename() + (".zip" if is_zip_url else ".rom"))
	
	var http_request: HTTPRequest = HTTPRequest.new()
	node.add_child(http_request)
	http_request.download_file = temp_download_path
	
	var is_downloading_flag: Array = [true]
	http_request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		is_downloading_flag[0] = false
		http_request.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 0):
			_process_downloaded_rom_file(node, temp_download_path, target_rom_path, rom_name, is_zip_url, callback)
		else:
			print("[Launcher Error] Failed to download base ROM. HTTP Status: ", response_code)
			if FileAccess.file_exists(temp_download_path):
				DirAccess.remove_absolute(temp_download_path)
			callback.call(false, "Failed to download ROM from configured URL. Response code: " + str(response_code))
	)
	
	track_http_download_progress(node, http_request, "Base ROM (" + rom_name + ")", is_downloading_flag)
	var request_err: Error = http_request.request(download_url)
	if request_err != OK:
		is_downloading_flag[0] = false
		http_request.queue_free()
		callback.call(false, "Failed to start ROM download HTTP request.")

func _set_overlay_downloading_state(node: Node) -> void:
	if is_instance_valid(node):
		if node.has_node("%LaunchOverlay"):
			node.get_node("%LaunchOverlay").visible = true
		if node.has_node("%PathSection"):
			node.get_node("%PathSection").visible = false
		if node.has_node("%EmulatorPathSection"):
			node.get_node("%EmulatorPathSection").visible = false
		if node.has_node("%GameSelectionSection"):
			node.get_node("%GameSelectionSection").visible = false
		if node.has_node("%LaunchConfirmBtn"):
			node.get_node("%LaunchConfirmBtn").visible = false

func _process_downloaded_rom_file(node: Node, temp_download_path: String, target_rom_path: String, rom_name: String, is_zip_url: bool, callback: Callable) -> void:
	print("[Launcher] Base ROM download completed. Checking format...")
	var finish_rom_callback: Callable = func(final_path: String):
		for countdown_idx in range(5, 0, -1):
			if is_instance_valid(node) and "launch_instructions" in node and is_instance_valid(node.launch_instructions):
				node.launch_instructions.text = "Base ROM Ready: " + rom_name + "!\n" + get_progress_bar_str(100) + "\n\nContinuing automatically in " + str(countdown_idx) + " seconds..."
			if is_instance_valid(node) and node.get_tree():
				await node.get_tree().create_timer(1.0).timeout
		callback.call(true, final_path)
		
	if is_zip_url:
		unpack_rom_zip(temp_download_path, rom_name, func(unpack_success: bool, unpack_result: String):
			if unpack_success:
				finish_rom_callback.call(unpack_result)
			else:
				callback.call(false, unpack_result)
		)
	else:
		var check_file: FileAccess = FileAccess.open(temp_download_path, FileAccess.READ)
		var is_zip_bytes: bool = false
		if check_file:
			var header_bytes: PackedByteArray = check_file.get_buffer(2)
			check_file.close()
			if header_bytes.size() >= 2 and header_bytes[0] == ZIP_HEADER_BYTE_1 and header_bytes[1] == ZIP_HEADER_BYTE_2:
				is_zip_bytes = true
				
		if is_zip_bytes:
			unpack_rom_zip(temp_download_path, rom_name, func(unpack_success: bool, unpack_result: String):
				if unpack_success:
					finish_rom_callback.call(unpack_result)
				else:
					callback.call(false, unpack_result)
			)
		else:
			DirAccess.copy_absolute(temp_download_path, target_rom_path)
			DirAccess.remove_absolute(temp_download_path)
			print("[Launcher] Base ROM stored successfully at: ", target_rom_path)
			finish_rom_callback.call(target_rom_path)


# =====================================================================
#                    PROGRESS TRACKING & UI UTILITIES
# =====================================================================

func get_progress_bar_str(pct: int) -> String:
	var filled_count: int = int(clamp(pct, 0, 100) / 5)
	var empty_count: int = 20 - filled_count
	var bar_str: String = ""
	for idx in range(filled_count):
		bar_str += "█"
	for idx in range(empty_count):
		bar_str += "░"
	return "[" + bar_str + "] " + str(pct) + "%"

func update_launch_progress_ui(node: Node, task_title: String, pct: int, downloaded_bytes: int, total_bytes: int) -> void:
	var bar_str: String = get_progress_bar_str(pct)
	var display_text: String = "Installing " + task_title + "...\n\n"
	if total_bytes > 0:
		var dl_mb: float = float(downloaded_bytes) / BYTES_PER_MB
		var total_mb: float = float(total_bytes) / BYTES_PER_MB
		display_text += "Progress: " + bar_str + "\n"
		display_text += "Downloaded: " + String.num(dl_mb, 1) + " MB / " + String.num(total_mb, 1) + " MB"
	else:
		var dl_mb: float = float(downloaded_bytes) / BYTES_PER_MB
		display_text += "Progress: " + bar_str + "\n"
		display_text += "Downloaded: " + String.num(dl_mb, 1) + " MB"
		
	if is_instance_valid(node) and "launch_instructions" in node and is_instance_valid(node.launch_instructions):
		node.launch_instructions.text = display_text

func track_http_download_progress(node: Node, http_request: HTTPRequest, task_title: String, is_active_flag: Array) -> void:
	while is_active_flag[0] and is_instance_valid(http_request):
		var downloaded_bytes: int = http_request.get_downloaded_bytes()
		var total_bytes: int = http_request.get_body_size()
		var percentage: int = int((float(downloaded_bytes) / float(total_bytes)) * 100.0) if total_bytes > 0 else 0
		update_launch_progress_ui(node, task_title, percentage, downloaded_bytes, total_bytes)
		if is_instance_valid(node) and node.get_tree():
			await node.get_tree().create_timer(0.15).timeout
		else:
			break


# =====================================================================
#                ARCHIPELAGO CONFIG SYNC (host.yaml)
# =====================================================================

func sync_archipelago_host_yaml(rom_path: String, bizhawk_path: String = "") -> void:
	var possible_host_yaml_paths: Array[String] = _get_archipelago_host_yaml_paths()
	var absolute_rom_path: String = ProjectSettings.globalize_path(rom_path).replace("\\", "/")
	var absolute_bizhawk_path: String = ProjectSettings.globalize_path(bizhawk_path).replace("\\", "/") if bizhawk_path != "" else ""

	_sync_base_rom_files_to_archipelago_dirs(rom_path)

	for target_yaml_path in possible_host_yaml_paths:
		_write_synced_host_yaml_file(target_yaml_path, absolute_rom_path, absolute_bizhawk_path)

func _get_archipelago_host_yaml_paths() -> Array[String]:
	var possible_paths: Array[String] = [
		USER_TOOLS_DIR.path_join("Archipelago/host.yaml")
	]
	if OS.get_name() == "Windows":
		var appdata_dir: String = OS.get_environment("APPDATA")
		if appdata_dir != "":
			possible_paths.append(appdata_dir.path_join("Archipelago").path_join("host.yaml"))
		var local_appdata_dir: String = OS.get_environment("LOCALAPPDATA")
		if local_appdata_dir != "":
			possible_paths.append(local_appdata_dir.path_join("Archipelago").path_join("host.yaml"))
		possible_paths.append("C:/ProgramData/Archipelago/host.yaml")
	possible_paths.append(OS.get_environment("HOME").path_join("Archipelago").path_join("host.yaml"))
	return possible_paths

func _sync_base_rom_files_to_archipelago_dirs(rom_path: String) -> void:
	if rom_path.strip_edges() == "":
		return
	var base_rom_dirs: Array[String] = [
		USER_TOOLS_DIR.path_join("Archipelago/base_roms"),
		USER_TOOLS_DIR.path_join("Archipelago")
	]
	if OS.get_name() == "Windows":
		var appdata_dir: String = OS.get_environment("APPDATA")
		if appdata_dir != "":
			base_rom_dirs.append(appdata_dir.path_join("Archipelago/base_roms"))
			base_rom_dirs.append(appdata_dir.path_join("Archipelago"))
		var local_appdata_dir: String = OS.get_environment("LOCALAPPDATA")
		if local_appdata_dir != "":
			base_rom_dirs.append(local_appdata_dir.path_join("Archipelago/base_roms"))
			base_rom_dirs.append(local_appdata_dir.path_join("Archipelago"))

	for base_dir in base_rom_dirs:
		DirAccess.make_dir_recursive_absolute(base_dir)
		var destination_filenames: Array[String] = [
			"Pokemon - Emerald Version (USA).gba",
			"Pokemon - Emerald Version (USA, Europe).gba",
			"Super Mario 64 (USA).z64",
			"baserom.us.z64",
			"Super Mario 64 (U) [!].z64"
		]
		for dest_name in destination_filenames:
			var target_dest_path: String = base_dir.path_join(dest_name)
			if not FileAccess.file_exists(target_dest_path):
				DirAccess.copy_absolute(rom_path, target_dest_path)

func _write_synced_host_yaml_file(target_yaml_path: String, absolute_rom_path: String, absolute_bizhawk_path: String) -> void:
	var dir_path: String = target_yaml_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var yaml_content: String = ""
	if FileAccess.file_exists(target_yaml_path):
		var file_access: FileAccess = FileAccess.open(target_yaml_path, FileAccess.READ)
		if file_access:
			yaml_content = file_access.get_as_text()
			file_access.close()

	yaml_content = _update_yaml_emerald_block(yaml_content, absolute_rom_path)
	if absolute_bizhawk_path != "":
		yaml_content = _update_yaml_bizhawk_block(yaml_content, absolute_bizhawk_path)

	var writer_file: FileAccess = FileAccess.open(target_yaml_path, FileAccess.WRITE)
	if writer_file:
		writer_file.store_string(yaml_content)
		writer_file.close()
		print("[Launcher] Synced Archipelago host.yaml at: ", target_yaml_path)

func _update_yaml_emerald_block(yaml_content: String, absolute_rom_path: String) -> String:
	if "pokemon_emerald_options:" in yaml_content:
		var lines: PackedStringArray = yaml_content.split("\n")
		var new_lines: Array[String] = []
		var in_emerald_block: bool = false
		var rom_set: bool = false
		for line in lines:
			if line.strip_edges().begins_with("pokemon_emerald_options:"):
				in_emerald_block = true
				new_lines.append(line)
				continue
			if in_emerald_block and line.strip_edges().begins_with("rom_file:"):
				new_lines.append("  rom_file: \"" + absolute_rom_path + "\"")
				rom_set = true
				in_emerald_block = false
				continue
			if in_emerald_block and not line.begins_with(" ") and line.strip_edges() != "":
				if not rom_set:
					new_lines.append("  rom_file: \"" + absolute_rom_path + "\"")
					rom_set = true
				in_emerald_block = false
			new_lines.append(line)
		if in_emerald_block and not rom_set:
			new_lines.append("  rom_file: \"" + absolute_rom_path + "\"")
		return "\n".join(new_lines)
	else:
		return yaml_content + "\npokemon_emerald_options:\n  rom_file: \"" + absolute_rom_path + "\"\n"

func _update_yaml_bizhawk_block(yaml_content: String, absolute_bizhawk_path: String) -> String:
	if "bizhawkclient_options:" in yaml_content:
		var lines: PackedStringArray = yaml_content.split("\n")
		var new_lines: Array[String] = []
		var in_biz_block: bool = false
		var emu_set: bool = false
		for line in lines:
			if line.strip_edges().begins_with("bizhawkclient_options:"):
				in_biz_block = true
				new_lines.append(line)
				continue
			if in_biz_block and line.strip_edges().begins_with("emuhawk_path:"):
				new_lines.append("  emuhawk_path: \"" + absolute_bizhawk_path + "\"")
				emu_set = true
				in_biz_block = false
				continue
			if in_biz_block and not line.begins_with(" ") and line.strip_edges() != "":
				if not emu_set:
					new_lines.append("  emuhawk_path: \"" + absolute_bizhawk_path + "\"")
					emu_set = true
				in_biz_block = false
			new_lines.append(line)
		if in_biz_block and not emu_set:
			new_lines.append("  emuhawk_path: \"" + absolute_bizhawk_path + "\"")
		return "\n".join(new_lines)
	else:
		return yaml_content + "\nbizhawkclient_options:\n  emuhawk_path: \"" + absolute_bizhawk_path + "\"\n  rom_start: true\n"


# =====================================================================
#                EXECUTABLE RECURSIVE DISCOVERY
# =====================================================================

func find_executable_recursive(dir_path: String, executable_name: String, current_depth: int = 0, max_depth: int = 4) -> String:
	if current_depth > max_depth or not DirAccess.dir_exists_absolute(dir_path):
		return ""
		
	var direct_target_path: String = dir_path.path_join(executable_name)
	if FileAccess.file_exists(direct_target_path):
		return ProjectSettings.globalize_path(direct_target_path)
		
	var dir_access: DirAccess = DirAccess.open(dir_path)
	if dir_access:
		dir_access.list_dir_begin()
		var file_item: String = dir_access.get_next()
		while file_item != "":
			if file_item != "." and file_item != ".." and dir_access.current_is_dir():
				var sub_target_dir: String = dir_path.path_join(file_item)
				var recursive_found: String = find_executable_recursive(sub_target_dir, executable_name, current_depth + 1, max_depth)
				if recursive_found != "":
					return recursive_found
			file_item = dir_access.get_next()
			
	return ""

func find_game_executable(executable_name: String, sub_folders: Array) -> String:
	if DirAccess.dir_exists_absolute(USER_TOOLS_DIR):
		var tool_found: String = find_executable_recursive(USER_TOOLS_DIR, executable_name)
		if tool_found != "":
			print("[Launcher] Found executable in user://tools/: ", tool_found)
			return tool_found

	var root_search_dirs: Array[String] = _get_platform_search_roots()
		
	for root_dir in root_search_dirs:
		if root_dir == "" or not DirAccess.dir_exists_absolute(root_dir):
			continue
			
		for sub_folder in sub_folders:
			var candidate_path: String = root_dir.path_join(sub_folder).path_join(executable_name)
			if FileAccess.file_exists(candidate_path):
				return ProjectSettings.globalize_path(candidate_path)
				
		var direct_path: String = root_dir.path_join(executable_name)
		if FileAccess.file_exists(direct_path):
			return ProjectSettings.globalize_path(direct_path)
			
		var recursive_found: String = find_executable_recursive(root_dir, executable_name, 0, 2)
		if recursive_found != "":
			return recursive_found
			
	return ""

func _get_platform_search_roots() -> Array[String]:
	var roots: Array[String] = []
	if OS.get_name() == "Windows":
		var program_files: String = OS.get_environment("ProgramFiles")
		if program_files != "":
			roots.append(program_files)
		var program_files_x86: String = OS.get_environment("ProgramFiles(x86)")
		if program_files_x86 != "":
			roots.append(program_files_x86)
		var local_appdata: String = OS.get_environment("LOCALAPPDATA")
		if local_appdata != "":
			roots.append(local_appdata)
			roots.append(local_appdata.path_join("Programs"))
			roots.append(local_appdata.path_join("Programs/Archipelago"))
			roots.append(local_appdata.path_join("Archipelago"))
			roots.append(local_appdata.path_join("BizHawk"))
			
		var user_profile: String = OS.get_environment("USERPROFILE")
		if user_profile != "":
			roots.append(user_profile.path_join("Archipelago"))
			roots.append(user_profile.path_join("AppData/Local/Programs/Archipelago"))

		roots.append("C:/Archipelago")
		roots.append("C:/BizHawk")
		roots.append("C:/Emulators/BizHawk")
		roots.append("C:/Program Files/BizHawk")
		roots.append("C:/Program Files/Steam/steamapps/common")
		roots.append("C:/Program Files (x86)/Steam/steamapps/common")
		roots.append("C:/Program Files/Epic Games")
		roots.append("C:/Program Files/GOG Galaxy/Games")
		roots.append("C:/Program Files (x86)/GOG Galaxy/Games")
		roots.append("D:/SteamLibrary/steamapps/common")
		roots.append("E:/SteamLibrary/steamapps/common")
		roots.append("C:/Program Files/Archipelago")
		roots.append("C:/Program Files (x86)/Archipelago")
		roots.append("C:/ProgramData/Archipelago")
	else:
		roots.append(OS.get_environment("HOME"))
		roots.append("/usr/local/bin")
		roots.append("/usr/bin")
	return roots


# =====================================================================
#                PROCESS EXECUTION & LOGGING
# =====================================================================

func launch_process_with_logging(node: Node, executable_path: String, args: Array, tag: String = "Client") -> int:
	print("[Launcher] Spawning process: ", executable_path, " with args: ", args)
	var pipe_dict: Dictionary = OS.execute_with_pipe(executable_path, args)
	if not pipe_dict.has("pid") or pipe_dict["pid"] <= 0:
		print("[Launcher Error] Failed to spawn process: ", executable_path)
		return -1

	var process_id: int = pipe_dict["pid"]
	print("[Launcher] Spawned ", tag, " process with PID: ", process_id)

	var stdout_pipe: FileAccess = pipe_dict.get("stdout")
	var stderr_pipe: FileAccess = pipe_dict.get("stderr")

	if stdout_pipe or stderr_pipe:
		WorkerThreadPool.add_task(func():
			_read_pipe_logs(stdout_pipe, stderr_pipe, tag)
		)

	return process_id

func _read_pipe_logs(stdout_pipe: FileAccess, stderr_pipe: FileAccess, tag: String) -> void:
	while (stdout_pipe and stdout_pipe.is_open()) or (stderr_pipe and stderr_pipe.is_open()):
		var read_anything: bool = false
		if stdout_pipe and stdout_pipe.is_open():
			var log_line: String = stdout_pipe.get_line()
			if log_line != "":
				print("[" + tag + " Output] " + log_line)
				read_anything = true
		if stderr_pipe and stderr_pipe.is_open():
			var log_line: String = stderr_pipe.get_line()
			if log_line != "":
				print("[" + tag + " Error Log] " + log_line)
				read_anything = true
		if not read_anything:
			OS.delay_msec(100)

func execute_preset_launch(node: Node, game_name: String, preset_config: Dictionary, game_path: String, active_launch_game: String) -> void:
	var launch_mode: String = preset_config.get("launch_mode", "direct")
	var clipboard_action: String = preset_config.get("clipboard_action", "")
	
	if clipboard_action == "copy_server_address":
		var archipelago_server_url: String = NetworkManager.get_ap_server_url()
		if archipelago_server_url != "":
			var clean_url: String = archipelago_server_url.replace("ws://", "").replace("wss://", "")
			DisplayServer.clipboard_set(clean_url)
			print("[Launcher] Server address copied to clipboard: ", clean_url)
			
	if launch_mode == "direct":
		print("[Launcher] Executing direct launch process...")
		launch_process_with_logging(node, game_path, [], "Game Executable")
			
	elif launch_mode == "ap_client":
		print("[Launcher] Locating patch file and opening in Archipelago client...")
		var patch_extension: String = preset_config.get("patch_extension", ".apgba")
		ensure_patch_file_exists_or_download(node, active_launch_game, patch_extension, func(success: bool, patch_path: String):
			if not success:
				print("[Launcher Error] Could not retrieve patch file: ", patch_path)
				return
				
			var archipelago_server_url: String = NetworkManager.get_ap_server_url()
			var clean_url: String = archipelago_server_url.replace("ws://", "").replace("wss://", "")
			if clean_url != "":
				DisplayServer.clipboard_set(clean_url)
				
			var target_client_path: String = game_path
			var launch_args: Array = []
			var is_launcher_wrapper: bool = target_client_path.ends_with("ArchipelagoLauncher.exe") or target_client_path.ends_with("Launcher.exe")
			
			if is_launcher_wrapper:
				var component_name: String = preset_config.get("client_component", "BizHawk Client")
				launch_args.append(component_name)

			launch_args.append(ProjectSettings.globalize_path(patch_path))
			if preset_config.get("auto_connect", false) and clean_url != "":
				if is_launcher_wrapper:
					launch_args.append("--")
				launch_args.append("--connect")
				launch_args.append(clean_url)
				
			print("[Launcher] Launching Archipelago client: ", target_client_path, " with args: ", launch_args)
			var process_id: int = OS.create_process(target_client_path, launch_args)
			if process_id > 0:
				print("[Launcher] Archipelago Client spawned successfully with PID: ", process_id)
			else:
				print("[Launcher Error] Failed to spawn Archipelago Client process: ", target_client_path)
		)
		
	elif launch_mode == "patch_rom":
		print("[Launcher] Preparing ROM Patch launch...")
		var patch_extension: String = preset_config.get("patch_extension", ".apz3")
		ensure_patch_file_exists_or_download(node, active_launch_game, patch_extension, func(success: bool, patch_path: String):
			if not success:
				print("[Launcher Error] Could not retrieve patch file: ", patch_path)
				return
				
			var emulator_path: String = paths_config.get("snes_emulator", "")
			if emulator_path == "" or not FileAccess.file_exists(emulator_path):
				print("[Launcher Error] Emulator path not configured.")
				return
				
			print("[Launcher] Launching emulator with ROM patch...")
			launch_process_with_logging(node, emulator_path, [ProjectSettings.globalize_path(patch_path)], "Emulator")
		)
		
	elif launch_mode == "sm64ex":
		print("[Launcher] Preparing Super Mario 64 EX launch...")
		var patch_extension: String = preset_config.get("patch_extension", ".apsm64ex")
		
		var archipelago_server_url: String = NetworkManager.get_ap_server_url()
		var clean_url: String = archipelago_server_url.replace("ws://", "").replace("wss://", "")
		if clean_url != "":
			DisplayServer.clipboard_set(clean_url)
			
		var current_player_name: String = ""
		for player_info in NetworkManager.players:
			if player_info.get("userId") == NetworkManager.user_id:
				current_player_name = player_info.get("name", "")
				break
				
		var target_client_path: String = game_path
		var base_launch_args: Array = []
		
		if preset_config.get("auto_connect", false) and clean_url != "":
			if current_player_name != "":
				base_launch_args.append("--sm64ap_name")
				base_launch_args.append(current_player_name)
			base_launch_args.append("--sm64ap_ip")
			base_launch_args.append(clean_url)

		var start_sm64ex_process: Callable = func(patch_file_path: String = ""):
			var final_args: Array = base_launch_args.duplicate()
			if patch_file_path != "":
				final_args.append("--sm64ap_file")
				final_args.append(ProjectSettings.globalize_path(patch_file_path))
			print("[Launcher] Launching Super Mario 64 EX: ", target_client_path, " with args: ", final_args)
			var process_id: int = OS.create_process(target_client_path, final_args)
			if process_id <= 0:
				process_id = launch_process_with_logging(node, target_client_path, final_args, "Super Mario 64 EX")
			if process_id > 0:
				print("[Launcher] Super Mario 64 EX spawned successfully with PID: ", process_id)
			else:
				print("[Launcher Error] Failed to spawn Super Mario 64 EX process: ", target_client_path)

		ensure_patch_file_exists_or_download(node, active_launch_game, patch_extension, func(success: bool, patch_path_or_err: String):
			if success:
				start_sm64ex_process.call(patch_path_or_err)
			else:
				print("[Launcher] No offline patch file found for SM64EX (expected for multiplayer). Launching with live connection args...")
				start_sm64ex_process.call("")
		)


# =====================================================================
#                PATCH FILE DOWNLOAD & DISCOVERY
# =====================================================================

func is_matching_patch_file(filename: String, patch_extension: String) -> bool:
	var filename_lower: String = filename.to_lower()
	var ext_lower: String = patch_extension.to_lower()
	if filename_lower.ends_with(ext_lower):
		return true
	if (ext_lower == ".apemerald" or ext_lower == ".apgba") and (filename_lower.ends_with(".apemerald") or filename_lower.ends_with(".apgba")):
		return true
	if filename_lower.begins_with("ap_") and filename_lower.contains(".ap"):
		if not filename_lower.ends_with(".zip") and not filename_lower.ends_with(".yaml") and not filename_lower.ends_with(".txt") and not filename_lower.ends_with(".json"):
			return true
	return false

func ensure_patch_file_exists_or_download(node: Node, active_launch_game: String, patch_extension: String, callback: Callable) -> void:
	var download_dir: String = USER_SAVES_DIR.path_join(NetworkManager.room_code)
	DirAccess.make_dir_recursive_absolute(download_dir)
	
	var current_player_name: String = ""
	for player_info in NetworkManager.players:
		if player_info.get("userId") == NetworkManager.user_id:
			current_player_name = player_info.get("name", "")
			break

	var dir_access: DirAccess = DirAccess.open(download_dir)
	if dir_access:
		dir_access.list_dir_begin()
		var file_item: String = dir_access.get_next()
		while file_item != "":
			if is_matching_patch_file(file_item, patch_extension):
				if current_player_name == "" or file_item.to_lower().contains(current_player_name.to_lower()):
					print("[Launcher] Located local player seed patch file: ", file_item)
					callback.call(true, download_dir.path_join(file_item))
					return
			file_item = dir_access.get_next()
			
	print("[Launcher] Requesting player-specific seed patch from server for player '", current_player_name, "'...")
	var http_request: HTTPRequest = HTTPRequest.new()
	node.add_child(http_request)
	
	var patch_request_url: String = NetworkManager.get_http_url() + "/api/seeds/" + NetworkManager.room_code + "/player-patch?playerName=" + current_player_name.uri_encode() + "&gameName=" + active_launch_game.uri_encode() + "&userId=" + NetworkManager.user_id.uri_encode()
	
	http_request.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		http_request.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 0):
			var content_disposition_header: String = ""
			for header_line in headers:
				if header_line.to_lower().begins_with("content-disposition:"):
					content_disposition_header = header_line
					break
					
			var patch_filename: String = "player_seed" + patch_extension
			if content_disposition_header != "" and content_disposition_header.contains("filename="):
				var header_parts: PackedStringArray = content_disposition_header.split("filename=")
				if header_parts.size() > 1:
					patch_filename = header_parts[1].replace("\"", "").replace("'", "").strip_edges()
			else:
				patch_filename = "AP_" + NetworkManager.room_code + "_" + (current_player_name if current_player_name != "" else "Player") + patch_extension

			var saved_patch_path: String = download_dir.path_join(patch_filename)
			var file_writer: FileAccess = FileAccess.open(saved_patch_path, FileAccess.WRITE)
			if file_writer:
				file_writer.store_buffer(body)
				file_writer.close()
				print("[Launcher] Saved targeted player patch file (", body.size(), " bytes) to: ", saved_patch_path)
				callback.call(true, saved_patch_path)
				return
				
		print("[Launcher Warning] Targeted player patch endpoint unavailable or failed. Falling back to seed ZIP download...")
		fallback_download_seed_zip(node, patch_extension, callback)
	)
	
	var request_err: Error = http_request.request(patch_request_url)
	if request_err != OK:
		http_request.queue_free()
		fallback_download_seed_zip(node, patch_extension, callback)

func fallback_download_seed_zip(node: Node, patch_extension: String, callback: Callable) -> void:
	var download_dir: String = USER_SAVES_DIR.path_join(NetworkManager.room_code)
	var http_request: HTTPRequest = HTTPRequest.new()
	node.add_child(http_request)
	
	var temp_zip_path: String = download_dir.path_join("seed_temp.zip")
	http_request.download_file = temp_zip_path
	
	http_request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		http_request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if FileAccess.file_exists(temp_zip_path):
				DirAccess.remove_absolute(temp_zip_path)
			callback.call(false, "Failed to download seed ZIP from server. Status: " + str(response_code))
			return
			
		var zip_reader: ZIPReader = ZIPReader.new()
		var open_err: Error = zip_reader.open(temp_zip_path)
		if open_err != OK:
			DirAccess.remove_absolute(temp_zip_path)
			callback.call(false, "Failed to open downloaded seed ZIP.")
			return
			
		var archive_files: PackedStringArray = zip_reader.get_files()
		for file_entry in archive_files:
			var file_data: PackedByteArray = zip_reader.read_file(file_entry)
			var file_writer: FileAccess = FileAccess.open(download_dir.path_join(file_entry), FileAccess.WRITE)
			if file_writer:
				file_writer.store_buffer(file_data)
				file_writer.close()
		zip_reader.close()
		DirAccess.remove_absolute(temp_zip_path)
		
		var dir_access: DirAccess = DirAccess.open(download_dir)
		if dir_access:
			dir_access.list_dir_begin()
			var file_item: String = dir_access.get_next()
			while file_item != "":
				if is_matching_patch_file(file_item, patch_extension):
					print("[Launcher] Located extracted player seed patch file: ", file_item)
					callback.call(true, download_dir.path_join(file_item))
					return
				file_item = dir_access.get_next()
				
		callback.call(false, "Downloaded ZIP successfully but could not find a patch file matching " + patch_extension)
	)
	
	var download_url: String = NetworkManager.get_http_url() + "/api/seeds/" + NetworkManager.room_code + "/outputs/" + NetworkManager.seed_zip_name.uri_encode()
	http_request.request(download_url)
