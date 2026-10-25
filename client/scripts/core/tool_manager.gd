class_name ToolManager
extends RefCounted

const DEFAULT_ARCHIPELAGO_DOWNLOAD_URL: String = "https://github.com/ArchipelagoMW/Archipelago/releases/download/0.6.7/Setup.Archipelago.0.6.7.exe"

var paths_config: Dictionary
var locator
var save_paths_callback: Callable

class InstallRequest:
	var node: Node
	var tool_name: String
	var download_url: String
	var subfolder: String
	var target_executable: String
	var fallback_url: String
	var generation: int

	func _init(
		p_node: Node,
		p_tool_name: String,
		p_download_url: String,
		p_subfolder: String,
		p_target_executable: String,
		p_fallback_url: String,
		p_generation: int
	) -> void:
		node = p_node
		tool_name = p_tool_name
		download_url = p_download_url
		subfolder = p_subfolder
		target_executable = p_target_executable
		fallback_url = p_fallback_url
		generation = p_generation

static func install_success(path: String) -> Dictionary:
	return {"success": true, "path": path, "error": ""}

static func install_failure(error: String) -> Dictionary:
	return {"success": false, "path": "", "error": error}

func create_install_request(
	node: Node,
	tool_name: String,
	download_url: String,
	subfolder: String,
	target_executable: String,
	fallback_url: String,
	generation: int
) -> InstallRequest:
	return InstallRequest.new(node, tool_name, download_url, subfolder, target_executable, fallback_url, generation)

func _init(p_paths_config: Dictionary, p_locator, p_save_paths_callback: Callable) -> void:
	paths_config = p_paths_config
	locator = p_locator
	save_paths_callback = p_save_paths_callback

func get_preset_packages(preset_config: Dictionary) -> Array:
	if preset_config.get("packages") is Array:
		return preset_config["packages"]

	var packages: Array = []
	if str(preset_config.get("modding_api_url", "")) != "":
		packages.append({
			"name": "Modding API",
			"download_url": preset_config.get("modding_api_url", ""),
			"check_file": preset_config.get("modding_api_check_file", ""),
			"extract_target": preset_config.get("modding_api_extract_target", ""),
			"backup_files": preset_config.get("modding_api_backup_files", ["Assembly-CSharp.dll"])
		})
	if str(preset_config.get("mods_url", "")) != "":
		packages.append({
			"name": "Archipelago Mods",
			"download_url": preset_config.get("mods_url", ""),
			"check_file": preset_config.get("mods_check_file", ""),
			"extract_target": preset_config.get("mods_extract_target", ""),
			"backup_files": preset_config.get("mods_backup_files", [])
		})
	return packages

func resolve_path(tool_key: String, tool_def: Dictionary, fallback_config_key: String = "") -> String:
	var config_key: String = tool_key if fallback_config_key == "" else fallback_config_key
	var stored: String = str(paths_config.get(config_key, ""))
	if stored != "" and FileAccess.file_exists(stored):
		return stored

	var executable: String = str(tool_def.get("executable", ""))
	var sub_folders: Array = tool_def.get("sub_folders", [])
	var aliases: Array = tool_def.get("executable_aliases", []).duplicate()
	if executable != "" and not aliases.has(executable):
		aliases.push_front(executable)

	var found: String = locator.find(executable, sub_folders, aliases, false)
	if found == "":
		found = locator.find(executable, sub_folders, aliases, true)
	if found == "" or not FileAccess.file_exists(found):
		return ""

	paths_config[config_key] = found
	if save_paths_callback.is_valid():
		save_paths_callback.call()
	return found

func resolve_download_url(download_url: String) -> String:
	var resolved_url: String = download_url
	if resolved_url.contains("{backend_url}"):
		return resolved_url.replace("{backend_url}", NetworkManager.get_http_url())
	if not resolved_url.begins_with("http://") and not resolved_url.begins_with("https://"):
		return NetworkManager.get_http_url() + (resolved_url if resolved_url.begins_with("/") else "/" + resolved_url)
	if resolved_url.contains("releases/latest"):
		return DEFAULT_ARCHIPELAGO_DOWNLOAD_URL
	return resolved_url

func get_temp_download_path(tool_name: String, download_url: String) -> String:
	var is_executable: bool = download_url.get_file().strip_edges().to_lower().ends_with(".exe") or download_url.to_lower().contains(".exe")
	var extension: String = ".exe" if is_executable else ".zip"
	return "user://tools".path_join("temp_" + tool_name.validate_filename() + extension)

func validate_download_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"valid": false, "error": "Downloaded file does not exist on disk: " + file_path}

	var file_access: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file_access:
		return {"valid": false, "error": "Cannot open downloaded file for verification: " + file_path}

	var file_size: int = file_access.get_length()
	var header: PackedByteArray = file_access.get_buffer(4)
	file_access.close()
	if file_size < 1024:
		return {"valid": false, "error": "Downloaded file is too small (" + str(file_size) + " bytes). Expected archive or installer; got error page."}

	var is_zip: bool = header.size() >= 2 and header[0] == 0x50 and header[1] == 0x4B
	var is_executable: bool = header.size() >= 2 and header[0] == 0x4D and header[1] == 0x5A
	if not is_zip and not is_executable:
		return {"valid": false, "error": "Downloaded file is not a ZIP archive or Windows installer."}
	return {
		"valid": true,
		"format": "exe" if is_executable else "zip",
		"error": ""
	}
