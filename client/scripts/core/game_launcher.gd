class_name GameLauncher
extends RefCounted

const LauncherUtils = preload("res://scripts/core/launcher_utils.gd")
const ArchipelagoConfig = preload("res://scripts/core/archipelago_config.gd")
const LauncherConfigStoreScript = preload("res://scripts/core/launcher_config_store.gd")
const GameIdentityResolverScript = preload("res://scripts/core/game_identity_resolver.gd")
const RomCatalogServiceScript = preload("res://scripts/core/rom_catalog_service.gd")
const ExecutableLocatorScript = preload("res://scripts/core/executable_locator.gd")
const ToolManagerScript = preload("res://scripts/core/tool_manager.gd")
const ToolInstallerScript = preload("res://scripts/core/tool_installer.gd")
const FirmwareManagerScript = preload("res://scripts/core/firmware_manager.gd")
const ConfigWriterServiceScript = preload("res://scripts/core/config_writer_service.gd")
const ProcessLauncherScript = preload("res://scripts/core/process_launcher.gd")
const PatchManagerScript = preload("res://scripts/core/patch_manager.gd")
const RomArchiveServiceScript = preload("res://scripts/core/rom_archive_service.gd")
const PackageInstallerScript = preload("res://scripts/core/package_installer.gd")
const PcGameInstallerScript = preload("res://scripts/core/pc_game_installer.gd")
const RomDownloadServiceScript = preload("res://scripts/core/rom_download_service.gd")

# --- CONSTANTS ---
const DEFAULT_ARCHIPELAGO_DOWNLOAD_URL: String = "https://github.com/ArchipelagoMW/Archipelago/releases/download/0.6.7/Setup.Archipelago.0.6.7.exe"
const DEFAULT_BIZHAWK_PREREQS_URL: String = "https://github.com/TASEmulators/BizHawk-Prereqs/releases/download/2.4.8_1/bizhawk_prereqs_v2.4.8_1.zip"

const BYTES_PER_MB: float = 1024.0 * 1024.0

const USER_TOOLS_DIR: String = "user://tools"
const USER_BASE_ROMS_DIR: String = "user://base_roms"
const USER_GAMES_DIR: String = "user://games"
const USER_SAVES_DIR: String = "user://saves"
const USER_PATHS_CONFIG_PATH: String = "user://paths_config.json"

# --- LAUNCH PIPELINE ENUM & SIGNALS ---
enum LaunchStage {
	INITIALIZING,
	PREPARING_ROM,
	PREPARING_TOOLS,
	PREPARING_FIRMWARE,
	FETCHING_PATCH,
	SYNCING_CONFIG,
	SPAWNING_PROCESS,
	MODDING_DISC,
	COMPLETED,
	FAILED
}

signal launch_status_updated(stage: int, message: String, progress_pct: float)
signal prompt_file_selection(title: String, instructions: String, filters: PackedStringArray, callback: Callable)
signal prompt_tool_installation(tool_name: String, download_url: String, subfolder: String, target_file: String, callback: Callable)
signal launch_completed(game_name: String, pid: int)
signal launch_failed(game_name: String, error_message: String)
signal config_loaded()

class LaunchContext:
	var game_name: String
	var preset: Dictionary
	var node: Node
	var launch_mode: String = "direct"
	var base_rom_path: String = ""
	var client_exe_path: String = ""
	var emulator_exe_path: String = ""
	var patch_path: String = ""
	var server_url: String = ""
	var process_id: int = -1
	var is_cancelled: bool = false
	
	func _init(p_game: String, p_preset: Dictionary, p_node: Node) -> void:
		game_name = p_game
		preset = p_preset
		node = p_node
		launch_mode = preset.get("launch_mode", "direct")

# State attributes
var launcher_tools: Dictionary = {}
var launcher_presets: Dictionary = {}
var paths_config: Dictionary = {}
var roms_catalog: Dictionary = {}
var _config_store
var _identity_resolver
var _rom_catalog_service
var _executable_locator
var _tool_manager
var _tool_installer
var _firmware_manager
var _config_writer_service
var _process_launcher
var _patch_manager
var _rom_archive_service
var _package_installer
var _pc_game_installer
var _rom_download_service
var _tool_installation_generation: int = 0

func _init() -> void:
	_config_store = LauncherConfigStoreScript.new()
	_config_store.tools = launcher_tools
	_config_store.games = launcher_presets
	_identity_resolver = GameIdentityResolverScript.new(launcher_presets)
	_rom_catalog_service = RomCatalogServiceScript.new(launcher_presets, _identity_resolver)
	_executable_locator = ExecutableLocatorScript.new(USER_GAMES_DIR, USER_TOOLS_DIR)
	_tool_manager = ToolManagerScript.new(paths_config, _executable_locator, save_paths_config)
	_tool_installer = ToolInstallerScript.new(
		_tool_manager,
		find_game_executable,
		find_executable_recursive,
		track_http_download_progress,
		get_progress_bar_str,
		USER_TOOLS_DIR,
		func() -> int: return _tool_installation_generation
	)
	_firmware_manager = FirmwareManagerScript.new(get_game_slug, _inject_emulator_firmware_config, USER_GAMES_DIR)
	_config_writer_service = ConfigWriterServiceScript.new(interpolate_template, _merge_and_interpolate_json)
	_process_launcher = ProcessLauncherScript.new()
	_patch_manager = PatchManagerScript.new(launcher_presets, get_preset, USER_SAVES_DIR)
	_rom_archive_service = RomArchiveServiceScript.new(get_game_slug_for_rom, get_game_dir, get_supported_rom_extensions)
	_package_installer = PackageInstallerScript.new(track_http_download_progress, get_progress_bar_str)
	_pc_game_installer = PcGameInstallerScript.new(resolve_download_url, decrypt_file_aes256, _set_overlay_downloading_state, track_http_download_progress)
	_rom_download_service = RomDownloadServiceScript.new(resolve_download_url, decrypt_file_aes256, unpack_rom_zip, _set_overlay_downloading_state, track_http_download_progress, get_progress_bar_str)
	load_local_presets_sync()


# =====================================================================
#                     CONFIG & CATALOG LOADING
# =====================================================================

func load_local_presets_sync() -> void:
	_config_store.load_local()

func load_launcher_config() -> void:
	load_local_presets_sync()
	var remote_loaded: bool = await _config_store.load_remote()
	if remote_loaded:
		GuidedSetupRegistry.refresh_slug_cache()
		print("[Launcher] Loaded ", launcher_presets.size(), " games and ", launcher_tools.size(), " shared tools from backend REST API.")
		config_loaded.emit()
		return

	print("[Launcher] Using cached launcher configuration because the backend was unavailable.")

func normalize_game_slug(name: String) -> String:
	return _identity_resolver.normalize(name)

func get_game_slug(game_name: String) -> String:
	return _identity_resolver.get_slug(game_name)

func get_game_dir(game_name: String) -> String:
	var slug: String = get_game_slug(game_name)
	var dir_path: String = USER_GAMES_DIR.path_join(slug)
	DirAccess.make_dir_recursive_absolute(dir_path)
	return dir_path

func get_game_slug_for_rom(rom_name: String) -> String:
	return _identity_resolver.game_slug_for_rom(rom_name)

func get_game_rom_path(game_name: String, rom_name: String) -> String:
	return get_game_dir(game_name).path_join(rom_name)

func has_preset(game_name: String) -> bool:
	return _identity_resolver.has_preset(game_name)

func has_curated_preset(game_name: String) -> bool:
	if not has_preset(game_name):
		return false
	var preset: Dictionary = get_preset(game_name)
	var tier: int = int(preset.get("support_tier", 4))
	return tier < 4

func get_preset(game_name: String) -> Dictionary:
	return _identity_resolver.get_preset(game_name)

func get_saved_path(game_name: String, preset: Dictionary = {}) -> String:
	var candidate_keys: Array[String] = [game_name, get_game_slug(game_name)]
	if not preset.is_empty():
		var canon: String = preset.get("game_name", "")
		if canon != "" and not candidate_keys.has(canon):
			candidate_keys.append(canon)
		for a in preset.get("aliases", []):
			var a_str: String = str(a)
			if a_str != "" and not candidate_keys.has(a_str):
				candidate_keys.append(a_str)
	for k in candidate_keys:
		var p: String = paths_config.get(k, "")
		if p != "" and FileAccess.file_exists(p):
			return p
	return ""

func load_roms_catalog() -> void:
	_rom_catalog_service.load_catalog()
	roms_catalog = _rom_catalog_service.catalog
	print("[Launcher] Loaded ROMs catalog (", roms_catalog.size(), " entries)")

func get_rom_download_entry(identifier: String) -> Dictionary:
	_rom_catalog_service.catalog = roms_catalog
	return _rom_catalog_service.get_download_entry(identifier)

func resolve_download_url(raw_url: String) -> String:
	return LauncherUtils.resolve_download_url(raw_url)

func decrypt_file_aes256(encrypted_path: String, output_path: String, passphrase: String) -> bool:
	return LauncherUtils.decrypt_file_aes256(encrypted_path, output_path, passphrase)


func load_paths_config() -> void:
	if FileAccess.file_exists(USER_PATHS_CONFIG_PATH):
		var file_access: FileAccess = FileAccess.open(USER_PATHS_CONFIG_PATH, FileAccess.READ)
		if file_access:
			var parsed_json: Variant = JSON.parse_string(file_access.get_as_text())
			if parsed_json is Dictionary:
				paths_config = parsed_json
				# Sanitize: remove any tools erroneously saved under game keys
				var dirty: bool = false
				for k in paths_config.keys():
					var val: String = str(paths_config[k])
					if val.to_lower().ends_with("archipelagolauncher.exe") or val.to_lower().ends_with("launcher.exe"):
						var p: Dictionary = get_preset(k)
						if not p.is_empty() and (p.get("required_rom", "") != "" or p.get("launch_mode", "") in ["ap_client", "patch_rom"]):
							paths_config.erase(k)
							dirty = true
				if dirty:
					save_paths_config()
				print("[Launcher] Loaded user paths configuration.")
			file_access.close()
	sync_custom_worlds_to_archipelago()

func save_paths_config() -> void:
	var file_access: FileAccess = FileAccess.open(USER_PATHS_CONFIG_PATH, FileAccess.WRITE)
	if file_access:
		file_access.store_string(JSON.stringify(paths_config, "  "))
		file_access.close()
		print("[Launcher] Saved user paths configuration.")


# =====================================================================
#                   ROM UNPACKING & AUTO-DISCOVERY
# =====================================================================

func get_supported_rom_extensions() -> Array[String]:
	var exts: Array[String] = []
	for game_name in launcher_presets.keys():
		var preset: Dictionary = launcher_presets[game_name]
		var req_rom: String = preset.get("required_rom", "")
		var ext: String = req_rom.get_extension().to_lower()
		if ext != "" and not exts.has(ext):
			exts.append(ext)
		for alias in preset.get("rom_aliases", []):
			var a_ext: String = str(alias).get_extension().to_lower()
			if a_ext != "" and not exts.has(a_ext):
				exts.append(a_ext)
	return exts

func unpack_rom_zip(zip_file_path: String, rom_name: String, callback: Callable) -> void:
	_rom_archive_service.unpack(zip_file_path, rom_name, callback)
func find_existing_base_rom(rom_name: String) -> String:
	var game_slug: String = get_game_slug_for_rom(rom_name)
	var game_folder: String = USER_GAMES_DIR.path_join(game_slug)
	var target_unified: String = game_folder.path_join(rom_name)

	# Check if user already configured a path for this game/rom in paths_config
	for g_name in paths_config.keys():
		var p_path: String = str(paths_config[g_name])
		if p_path != "" and FileAccess.file_exists(p_path) and not p_path.to_lower().ends_with(".exe"):
			var p_base: String = p_path.get_file()
			var matches: bool = (p_base == rom_name or p_path == rom_name)
			if matches:
				# If configured path is in legacy base_roms, auto-migrate to unified game directory
				if (p_path.contains("base_roms") or p_path.contains("base_rom")) and game_folder != "":
					if not FileAccess.file_exists(target_unified):
						DirAccess.make_dir_recursive_absolute(game_folder)
						var m_err: Error = DirAccess.copy_absolute(p_path, target_unified)
						if m_err == OK:
							print("[Launcher] Auto-migrated paths_config legacy ROM to unified path: ", target_unified)
							paths_config[g_name] = target_unified
							save_paths_config()
							return target_unified
					else:
						paths_config[g_name] = target_unified
						save_paths_config()
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
	
	# Also search all subdirectories of user://games/
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
		for game_name in launcher_presets.keys():
			var preset: Dictionary = launcher_presets[game_name]
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
					print("[Launcher] Found exact ROM file at: ", full_file_path)
					# If found in legacy base_roms, auto-migrate to user://games/<game_slug>/
					if (dir_path.contains("base_roms") or dir_path.contains("base_rom")) and game_folder != "":
						if not FileAccess.file_exists(target_unified):
							DirAccess.make_dir_recursive_absolute(game_folder)
							var mig_err: Error = DirAccess.copy_absolute(full_file_path, target_unified)
							if mig_err == OK:
								print("[Launcher] Auto-migrated legacy ROM to unified game path: ", target_unified)
								return target_unified
						else:
							return target_unified
					return full_file_path
			
	return _fuzzy_search_matching_rom(candidate_directories, rom_name, target_extension)

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

	for game_name in launcher_presets.keys():
		var preset: Dictionary = launcher_presets[game_name]
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

	var supported_extensions: Array[String] = get_supported_rom_extensions()
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
								print("[Launcher] Discovered matching ROM file (", file_item, ") at: ", found_path)
								if (found_path.contains("base_roms") or found_path.contains("base_rom")):
									var f_slug: String = get_game_slug_for_rom(file_item)
									if f_slug == "":
										f_slug = get_game_slug_for_rom(rom_name)
									var f_folder: String = USER_GAMES_DIR.path_join(f_slug)
									var target_unified: String = f_folder.path_join(file_item)
									if not FileAccess.file_exists(target_unified):
										DirAccess.make_dir_recursive_absolute(f_folder)
										var mig_err: Error = DirAccess.copy_absolute(found_path, target_unified)
										if mig_err == OK:
											print("[Launcher] Auto-migrated fuzzy legacy ROM to unified path: ", target_unified)
											return target_unified
									else:
										return target_unified
								return found_path
				file_item = dir_access.get_next()
				
	return ""

func ensure_rom_exists_or_download(node: Node, rom_name: String, callback: Callable) -> void:
	if rom_name.strip_edges() == "":
		print("[Launcher] Game specifies no required ROM. Skipping ROM download/check.")
		callback.call(true, "")
		return
		
	var game_slug: String = get_game_slug_for_rom(rom_name)
	var target_game_dir: String = get_game_dir(game_slug)
	var target_rom_path: String = target_game_dir.path_join(rom_name)
	
	var existing_rom: String = find_existing_base_rom(rom_name)
	if existing_rom != "":
		_handle_existing_base_rom(node, existing_rom, target_rom_path, rom_name, callback)
		return
		
	var download_entry: Dictionary = get_rom_download_entry(rom_name)
	if download_entry.is_empty():
		for g_name in launcher_presets.keys():
			var preset: Dictionary = launcher_presets[g_name]
			if preset.get("required_rom", "") == rom_name:
				download_entry = get_rom_download_entry(g_name)
				if download_entry.is_empty():
					var p_url: String = preset.get("rom_download_url", "").strip_edges()
					if p_url != "":
						download_entry = {"url": p_url, "key": "", "encrypted": false}
				break
			for alias in preset.get("rom_aliases", []):
				if str(alias) == rom_name:
					download_entry = get_rom_download_entry(str(alias))
					if download_entry.is_empty():
						download_entry = get_rom_download_entry(g_name)
					break
			if not download_entry.is_empty():
				break

	if download_entry.is_empty() or download_entry.get("url", "") == "":
		callback.call(false, "Base ROM \"" + rom_name + "\" is missing. Please configure a download link in user://roms.json or place the file in user://games/" + game_slug + "/")
		return
		
	var catalog_url: String = download_entry.get("url", "")
	var dec_key: String = download_entry.get("key", "")
	
	if catalog_url.begins_with("file://"):
		_handle_local_file_url(node, catalog_url, target_rom_path, rom_name, callback)
		return
		
	_download_base_rom_http(node, catalog_url, target_game_dir, rom_name, target_rom_path, callback, dec_key)

func _handle_existing_base_rom(node: Node, found_rom: String, target_rom_path: String, rom_name: String, callback: Callable) -> void:
	_rom_download_service.process_existing(node, found_rom, target_rom_path, rom_name, callback)

func _handle_local_file_url(node: Node, catalog_url: String, target_rom_path: String, rom_name: String, callback: Callable) -> void:
	_rom_download_service.copy_local_file(node, catalog_url, target_rom_path, rom_name, callback)

func _download_base_rom_http(node: Node, download_url: String, base_roms_dir: String, rom_name: String, target_rom_path: String, callback: Callable, decryption_key: String = "", redirect_depth: int = 0) -> void:
	_rom_download_service.download(node, download_url, base_roms_dir, rom_name, target_rom_path, callback, decryption_key, redirect_depth)

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

func ensure_pc_game_installed(node: Node, game_name: String, preset_config: Dictionary, callback: Callable) -> void:
	var exec_name: String = preset_config.get("client_executable", preset_config.get("executable_name", ""))
	var aliases: Array = preset_config.get("executable_aliases", [])
	
	var download_entry: Dictionary = get_rom_download_entry(game_name)
	if download_entry.is_empty() and exec_name != "":
		download_entry = get_rom_download_entry(exec_name)
	for a in aliases:
		if download_entry.is_empty():
			download_entry = get_rom_download_entry(str(a))
		else:
			break
			
	if download_entry.is_empty() or download_entry.get("url", "") == "":
		callback.call(false, "Game files for \"" + game_name + "\" not found on machine, and no download link configured in roms.json.")
		return
		
	var download_url: String = download_entry.get("url", "")
	var dec_key: String = download_entry.get("key", "")
	var game_dest_dir: String = get_game_dir(game_name)
	
	print("[Launcher] Downloading standalone PC game (", game_name, ") from: ", download_url)
	_download_and_unpack_game_archive(node, download_url, game_dest_dir, game_name, dec_key, func(success: bool, msg: String):
		if not success:
			callback.call(false, msg)
			return
			
		# Scan extracted directory for executable
		var found_exe: String = _executable_locator.find_in_directory(game_dest_dir, exec_name, aliases)
		if found_exe != "":
			paths_config[game_name] = found_exe
			save_paths_config()
			print("[Launcher] PC Game auto-installed and executable located: ", found_exe)
			callback.call(true, found_exe)
		else:
			callback.call(false, "Game archive downloaded and extracted, but could not locate " + exec_name + " in " + game_dest_dir)
	)

func _download_and_unpack_game_archive(node: Node, download_url: String, extract_dir: String, game_name: String, decryption_key: String, callback: Callable, redirect_depth: int = 0) -> void:
	_pc_game_installer.install(node, download_url, extract_dir, game_name, decryption_key, callback, redirect_depth)

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

func update_launch_progress_ui(node: Node, task_title: String, pct: int, downloaded_bytes: int, total_bytes: int, speed_bps: float = 0.0) -> void:
	if not is_instance_valid(node):
		return

	# Update graphical DownloadProgressCard if present in the scene
	var dl_card: Node = null
	if node.has_node("%DownloadProgressCard"):
		dl_card = node.get_node("%DownloadProgressCard")
	elif node.has_node("DownloadProgressCard"):
		dl_card = node.get_node("DownloadProgressCard")
	elif node.has_node("%LaunchOverlay") and node.get_node("%LaunchOverlay").has_node("%DownloadProgressCard"):
		dl_card = node.get_node("%LaunchOverlay").get_node("%DownloadProgressCard")

	if is_instance_valid(dl_card):
		dl_card.visible = true
		dl_card.set_task("Installing " + task_title)
		dl_card.update_progress(pct, downloaded_bytes, total_bytes, speed_bps)

	# Update graphical ProgressBar if present
	if node.has_node("%LaunchProgressBar"):
		var pbar = node.get_node("%LaunchProgressBar")
		if is_instance_valid(pbar):
			pbar.visible = true
			pbar.value = pct

	var display_text: String = "Installing " + task_title + "...\n\n"
	var speed_str: String = ""
	if speed_bps > 0.0:
		var speed_mb: float = speed_bps / BYTES_PER_MB
		speed_str = " (" + String.num(speed_mb, 1) + " MB/s)"
		
	if total_bytes > 0:
		var dl_mb: float = float(downloaded_bytes) / BYTES_PER_MB
		var total_mb: float = float(total_bytes) / BYTES_PER_MB
		display_text += "Progress: " + str(pct) + "%\n"
		display_text += "Downloaded: " + String.num(dl_mb, 1) + " MB / " + String.num(total_mb, 1) + " MB" + speed_str
		if speed_bps > 50000.0 and total_bytes > downloaded_bytes:
			var remaining_bytes = total_bytes - downloaded_bytes
			var seconds_left = int(float(remaining_bytes) / speed_bps)
			if seconds_left < 60:
				display_text += " • ETA: ~" + str(seconds_left) + "s"
			else:
				var mins = int(seconds_left / 60)
				var secs = seconds_left % 60
				display_text += " • ETA: ~" + str(mins) + "m " + str(secs) + "s"
	else:
		var dl_mb: float = float(downloaded_bytes) / BYTES_PER_MB
		display_text += "Progress: " + str(pct) + "%\n"
		display_text += "Downloaded: " + String.num(dl_mb, 1) + " MB" + speed_str
		
	if "launch_instructions" in node and is_instance_valid(node.launch_instructions):
		node.launch_instructions.text = display_text

func track_http_download_progress(node: Node, http_request: HTTPRequest, task_title: String, is_active_flag: Array) -> void:
	var last_bytes: int = 0
	var last_time: float = float(Time.get_ticks_msec()) / 1000.0
	var current_speed: float = 0.0
	
	while is_active_flag[0] and is_instance_valid(http_request):
		var downloaded_bytes: int = http_request.get_downloaded_bytes()
		var total_bytes: int = http_request.get_body_size()
		var percentage: int = int((float(downloaded_bytes) / float(total_bytes)) * 100.0) if total_bytes > 0 else 0
		
		var now: float = float(Time.get_ticks_msec()) / 1000.0
		var dt: float = now - last_time
		if dt >= 0.4:
			var bytes_diff: int = downloaded_bytes - last_bytes
			if bytes_diff >= 0:
				var measured: float = float(bytes_diff) / dt
				current_speed = (current_speed * 0.4) + (measured * 0.6) if current_speed > 0.0 else measured
			last_bytes = downloaded_bytes
			last_time = now
			
		update_launch_progress_ui(node, task_title, percentage, downloaded_bytes, total_bytes, current_speed)
		if is_instance_valid(node) and node.get_tree():
			await node.get_tree().create_timer(0.15).timeout
		else:
			break

func cancel_tool_installation() -> void:
	_tool_installation_generation += 1
	WayfinderLogger.log_message("INSTALL", "Tool installation cancelled by user.")

func ensure_tool_installed_or_download(node: Node, tool_name: String, download_url: String, subfolder: String, target_exe: String, callback: Callable, fallback_url: String = "", installation_generation: int = -1) -> void:
	if installation_generation < 0:
		_tool_installation_generation += 1
		installation_generation = _tool_installation_generation
	_tool_installer.install(node, tool_name, download_url, subfolder, target_exe, callback, fallback_url, installation_generation)

func download_and_extract_zip_to_dir(node: Node, download_url: String, target_dir: String, display_name: String, callback: Callable, backup_files: Array = []) -> void:
	_package_installer.install(node, download_url, target_dir, display_name, callback, backup_files)

func ensure_emulator_firmware(node: Node, preset_config: Dictionary, emulator_exe_path: String, rom_path: String, callback: Callable) -> void:
	_firmware_manager.ensure(node, preset_config, emulator_exe_path, rom_path, callback)
func _inject_emulator_firmware_config(emulator_dir: String, emu_cfg: Dictionary) -> void:
	ArchipelagoConfig.inject_emulator_firmware_config(emulator_dir, emu_cfg)


# =====================================================================
#                ARCHIPELAGO CONFIG SYNC (host.yaml)
# =====================================================================

func sync_archipelago_host_yaml(rom_path: String, bizhawk_path: String = "") -> void:
	if bizhawk_path == "":
		bizhawk_path = paths_config.get("bizhawk_emulator", "")
		if bizhawk_path == "" or not FileAccess.file_exists(bizhawk_path):
			bizhawk_path = find_executable_recursive(USER_TOOLS_DIR, "EmuHawk.exe")

	var possible_host_yaml_paths: Array[String] = _get_archipelago_host_yaml_paths()
	var absolute_rom_path: String = ProjectSettings.globalize_path(rom_path).replace("\\", "/")
	var absolute_bizhawk_path: String = ProjectSettings.globalize_path(bizhawk_path).replace("\\", "/") if bizhawk_path != "" else ""

	_sync_base_rom_files_to_archipelago_dirs(rom_path)
	sync_custom_worlds_to_archipelago()

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

func get_matching_rom_aliases(rom_path: String) -> Array[String]:
	var rom_ext: String = rom_path.get_extension().to_lower()
	var destination_filenames: Array[String] = []
	for game_name in launcher_presets.keys():
		var preset: Dictionary = launcher_presets[game_name]
		var req_rom: String = preset.get("required_rom", "")
		if req_rom != "" and req_rom.get_extension().to_lower() == rom_ext:
			if not destination_filenames.has(req_rom):
				destination_filenames.append(req_rom)
		var aliases: Array = preset.get("rom_aliases", [])
		for a in aliases:
			var alias_str: String = str(a)
			if alias_str != "" and alias_str.get_extension().to_lower() == rom_ext:
				if not destination_filenames.has(alias_str):
					destination_filenames.append(alias_str)
	return destination_filenames

func _sync_base_rom_files_to_archipelago_dirs(rom_path: String) -> void:
	if rom_path.strip_edges() == "":
		return

	var base_rom_dirs: Array[String] = [
		USER_TOOLS_DIR.path_join("Archipelago/base_roms"),
		USER_TOOLS_DIR.path_join("Archipelago")
	]

	var src_len: int = 0
	var src_fa: FileAccess = FileAccess.open(rom_path, FileAccess.READ)
	if src_fa:
		src_len = src_fa.get_length()
		src_fa.close()

	# If CD-ROM / large file (> 50MB), only copy primary filename to avoid copying 513MB multiple times
	var destination_filenames: Array[String] = []
	if src_len > 50 * 1024 * 1024:
		destination_filenames.append(rom_path.get_file())
	else:
		destination_filenames = get_matching_rom_aliases(rom_path)
	if destination_filenames.is_empty():
		return

	for base_dir in base_rom_dirs:
		DirAccess.make_dir_recursive_absolute(base_dir)
		for dest_name in destination_filenames:
			var target_dest_path: String = base_dir.path_join(dest_name)
			var should_copy: bool = true
			if FileAccess.file_exists(target_dest_path):
				var dest_fa: FileAccess = FileAccess.open(target_dest_path, FileAccess.READ)
				if dest_fa:
					var dest_len: int = dest_fa.get_length()
					dest_fa.close()
					if dest_len == src_len and (src_len == 0 or dest_len > 1024):
						should_copy = false
			if should_copy:
				DirAccess.copy_absolute(rom_path, target_dest_path)

	# Dynamic supplemental / multi-track ROM syncing (e.g. CD-ROM audio tracks)
	for game_key in launcher_presets.keys():
		var preset: Dictionary = launcher_presets[game_key]
		var req_audio: String = preset.get("required_audio_rom", "")
		if req_audio != "":
			var suppl_path: String = _find_supplemental_rom_path(rom_path, req_audio)
			if suppl_path != "":
				var s_fa: FileAccess = FileAccess.open(suppl_path, FileAccess.READ)
				var s_len: int = 0
				if s_fa:
					s_len = s_fa.get_length()
					s_fa.close()
				for base_dir in base_rom_dirs:
					var s_dest: String = base_dir.path_join(req_audio)
					var should_copy_s: bool = true
					if FileAccess.file_exists(s_dest):
						var dest_fa: FileAccess = FileAccess.open(s_dest, FileAccess.READ)
						if dest_fa:
							var dest_len: int = dest_fa.get_length()
							dest_fa.close()
							if dest_len == s_len and dest_len > 1024:
								should_copy_s = false
					if should_copy_s:
						DirAccess.copy_absolute(suppl_path, s_dest)

func _find_supplemental_rom_path(rom_path: String, target_filename: String) -> String:
	if target_filename == "":
		return ""
	var game_slug: String = get_game_slug_for_rom(target_filename)
	var game_folder: String = USER_GAMES_DIR.path_join(game_slug)
	var candidate_paths: Array[String] = [
		game_folder.path_join(target_filename),
		ProjectSettings.globalize_path(game_folder).path_join(target_filename),
		USER_BASE_ROMS_DIR.path_join(target_filename),
		ProjectSettings.globalize_path(USER_BASE_ROMS_DIR).path_join(target_filename)
	]
	if rom_path != "":
		var base_dir: String = rom_path.get_base_dir()
		candidate_paths.append(base_dir.path_join(target_filename))
		if "Track 1" in rom_path and "Track 2" in target_filename:
			candidate_paths.append(rom_path.replace("Track 1", "Track 2"))
		elif "track 1" in rom_path and "track 2" in target_filename.to_lower():
			candidate_paths.append(rom_path.replace("track 1", "track 2"))
		elif "Disc 1" in rom_path and "Disc 2" in target_filename:
			candidate_paths.append(rom_path.replace("Disc 1", "Disc 2"))
		elif "disc 1" in rom_path and "disc 2" in target_filename.to_lower():
			candidate_paths.append(rom_path.replace("disc 1", "disc 2"))
	
	for c_path in candidate_paths:
		var norm_path: String = ProjectSettings.globalize_path(c_path).replace("\\", "/")
		if FileAccess.file_exists(norm_path):
			return norm_path
	return ""

func _write_synced_host_yaml_file(target_yaml_path: String, absolute_rom_path: String, absolute_bizhawk_path: String) -> void:
	var dir_path: String = target_yaml_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var yaml_content: String = ""
	if FileAccess.file_exists(target_yaml_path):
		var file_access: FileAccess = FileAccess.open(target_yaml_path, FileAccess.READ)
		if file_access:
			yaml_content = file_access.get_as_text()
			file_access.close()

	var rom_ext: String = absolute_rom_path.get_extension().to_lower()
	for game_key in launcher_presets.keys():
		var preset: Dictionary = launcher_presets[game_key]
		if preset.has("host_yaml") and preset["host_yaml"] is Dictionary:
			var host_cfg: Dictionary = preset["host_yaml"]
			var section: String = host_cfg.get("section", "")
			var option_key: String = host_cfg.get("rom_file_key", "rom_file")
			var req_rom: String = preset.get("required_rom", "")
			var req_ext: String = req_rom.get_extension().to_lower()
			
			var is_matching_rom: bool = false
			if req_ext != "" and req_ext == rom_ext:
				is_matching_rom = true
			else:
				for alias in preset.get("rom_aliases", []):
					if str(alias).get_extension().to_lower() == rom_ext:
						is_matching_rom = true
						break
			
			if is_matching_rom and section != "":
				var sections_to_update: Array[String] = [section]
				for extra_sec in host_cfg.get("extra_sections", []):
					if not str(extra_sec) in sections_to_update:
						sections_to_update.append(str(extra_sec))
				
				var audio_opt_key: String = host_cfg.get("audio_file_key", "")
				var req_audio: String = preset.get("required_audio_rom", "")
				var audio_path: String = ""
				if audio_opt_key != "" and req_audio != "":
					audio_path = _find_supplemental_rom_path(absolute_rom_path, req_audio)
				
				for sec in sections_to_update:
					yaml_content = _update_yaml_section_key(yaml_content, sec, option_key, absolute_rom_path)
					if audio_opt_key != "" and audio_path != "":
						yaml_content = _update_yaml_section_key(yaml_content, sec, audio_opt_key, audio_path)

	if absolute_bizhawk_path != "":
		yaml_content = _update_yaml_bizhawk_block(yaml_content, absolute_bizhawk_path)
		# Clean up any residual mock test paths in host.yaml
		if yaml_content.contains("mock_test_tools"):
			var lines_cleaned: PackedStringArray = yaml_content.split("\n")
			for i in range(lines_cleaned.size()):
				if lines_cleaned[i].contains("mock_test_tools"):
					lines_cleaned[i] = "  emuhawk_path: \"" + absolute_bizhawk_path + "\""
			yaml_content = "\n".join(lines_cleaned)

	var writer_file: FileAccess = FileAccess.open(target_yaml_path, FileAccess.WRITE)
	if writer_file:
		writer_file.store_string(yaml_content)
		writer_file.close()
		print("[Launcher] Synced Archipelago host.yaml at: ", target_yaml_path)

func _update_yaml_section_key(yaml_content: String, section_key: String, option_key: String, option_val: String, extra_lines: Array[String] = []) -> String:
	return ArchipelagoConfig.update_yaml_section_key(yaml_content, section_key, option_key, option_val, extra_lines)

func _update_yaml_bizhawk_block(yaml_content: String, absolute_bizhawk_path: String) -> String:
	return ArchipelagoConfig.update_yaml_bizhawk_block(yaml_content, absolute_bizhawk_path)


# =====================================================================
#                CUSTOM APWORLD SYNC & DOWNLOAD
# =====================================================================

func get_custom_world_destinations() -> Array[String]:
	var dests: Array[String] = ArchipelagoConfig.get_custom_world_destinations(USER_TOOLS_DIR)
	var launcher_exe: String = find_game_executable("ArchipelagoLauncher.exe", ["Archipelago"], [], false)
	if launcher_exe != "":
		var exe_dir: String = launcher_exe.get_base_dir()
		var candidate_custom: String = exe_dir.path_join("custom_worlds")
		if not dests.has(candidate_custom):
			dests.append(candidate_custom)
		var candidate_lib: String = exe_dir.path_join("lib/worlds")
		if not dests.has(candidate_lib):
			dests.append(candidate_lib)
	return dests

func sync_custom_worlds_to_archipelago() -> void:
	var source_apworlds: Dictionary = {}
	var source_dirs: Array[String] = [
		"res://custom_worlds",
		"user://custom_worlds"
	]
	
	for s_dir in source_dirs:
		if not DirAccess.dir_exists_absolute(s_dir):
			continue
		var dir: DirAccess = DirAccess.open(s_dir)
		if dir:
			dir.list_dir_begin()
			var fn: String = dir.get_next()
			while fn != "":
				if not dir.current_is_dir() and fn.ends_with(".apworld"):
					source_apworlds[fn] = s_dir.path_join(fn)
				fn = dir.get_next()

	if source_apworlds.is_empty():
		return

	var dest_dirs: Array[String] = get_custom_world_destinations()
	for dest_dir in dest_dirs:
		var parent_dir: String = dest_dir.get_base_dir()
		if not DirAccess.dir_exists_absolute(parent_dir) and not dest_dir.begins_with(USER_TOOLS_DIR):
			continue
			
		DirAccess.make_dir_recursive_absolute(dest_dir)
		for fn in source_apworlds.keys():
			var src_path: String = source_apworlds[fn]
			var dst_path: String = dest_dir.path_join(fn)
			
			var should_copy: bool = false
			if not FileAccess.file_exists(dst_path):
				should_copy = true
			else:
				var src_fa: FileAccess = FileAccess.open(src_path, FileAccess.READ)
				var dst_fa: FileAccess = FileAccess.open(dst_path, FileAccess.READ)
				if src_fa and dst_fa:
					if src_fa.get_length() != dst_fa.get_length():
						should_copy = true
				if src_fa: src_fa.close()
				if dst_fa: dst_fa.close()

			if should_copy:
				var copy_err: Error = DirAccess.copy_absolute(src_path, dst_path)
				if copy_err == OK:
					print("[Launcher] Synced custom world: ", fn, " to: ", dst_path)
				else:
					print("[Launcher Warning] Failed to copy custom world: ", fn, " to: ", dst_path, " (Error: ", copy_err, ")")

func sync_custom_worlds_from_server(node: Node, callback: Callable = Callable()) -> void:
	if not is_instance_valid(node):
		if callback.is_valid():
			callback.call(false)
		return
		
	var http: HTTPRequest = HTTPRequest.new()
	http.use_threads = true
	http.download_chunk_size = 1048576 # 1 MB buffer for maximum download throughput
	node.add_child(http)
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			sync_custom_worlds_to_archipelago()
			if callback.is_valid():
				callback.call(false)
			return
			
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if not (parsed is Dictionary) or not parsed.has("worlds"):
			sync_custom_worlds_to_archipelago()
			if callback.is_valid():
				callback.call(false)
			return
			
		var worlds: Array = parsed.get("worlds", [])
		_download_next_custom_world(node, worlds, 0, callback)
	)
	
	var list_url: String = NetworkManager.get_http_url() + "/api/custom-worlds"
	var err: Error = http.request(list_url)
	if err != OK:
		http.queue_free()
		sync_custom_worlds_to_archipelago()
		if callback.is_valid():
			callback.call(false)

func _download_next_custom_world(node: Node, worlds: Array, index: int, finish_cb: Callable) -> void:
	if index >= worlds.size():
		sync_custom_worlds_to_archipelago()
		if finish_cb.is_valid():
			finish_cb.call(true)
		return

	var world_info: Dictionary = worlds[index]
	var fn: String = world_info.get("filename", "")
	var server_size: int = int(world_info.get("size", 0))
	if fn == "":
		_download_next_custom_world(node, worlds, index + 1, finish_cb)
		return

	var user_cw_dir: String = "user://custom_worlds"
	DirAccess.make_dir_recursive_absolute(user_cw_dir)
	var local_file: String = user_cw_dir.path_join(fn)
	var local_bundle_file: String = "res://custom_worlds".path_join(fn)

	var need_download: bool = true
	if FileAccess.file_exists(local_file):
		var fa = FileAccess.open(local_file, FileAccess.READ)
		if fa:
			if server_size <= 0 or fa.get_length() == server_size:
				need_download = false
			fa.close()
	elif FileAccess.file_exists(local_bundle_file):
		var fa = FileAccess.open(local_bundle_file, FileAccess.READ)
		if fa:
			if server_size <= 0 or fa.get_length() == server_size:
				need_download = false
			fa.close()

	if not need_download:
		_download_next_custom_world(node, worlds, index + 1, finish_cb)
		return

	var http: HTTPRequest = HTTPRequest.new()
	http.use_threads = true
	http.download_chunk_size = 1048576 # 1 MB buffer for maximum download throughput
	node.add_child(http)
	http.download_file = local_file
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			print("[Launcher] Downloaded updated custom world from server: ", fn)
		_download_next_custom_world(node, worlds, index + 1, finish_cb)
	)
	var dl_url: String = NetworkManager.get_http_url() + "/api/custom-worlds/" + fn.uri_encode()
	http.request(dl_url)


# =====================================================================
#                EXECUTABLE RECURSIVE DISCOVERY
# =====================================================================

func find_executable_recursive(dir_path: String, executable_name: String, current_depth: int = 0, max_depth: int = 4) -> String:
	return _executable_locator.find_recursive(dir_path, executable_name, current_depth, max_depth)

func find_game_executable(executable_name: String, sub_folders: Array, executable_aliases: Array = [], allow_deep_search: bool = true) -> String:
	return _executable_locator.find(executable_name, sub_folders, executable_aliases, allow_deep_search)

func check_hollow_knight_modding_status(exe_or_game_dir: String) -> Dictionary:
	return LauncherUtils.check_hollow_knight_modding_status(exe_or_game_dir)

func _get_platform_search_roots() -> Array[String]:
	return LauncherUtils.get_platform_search_roots()


# =====================================================================
#                PROCESS EXECUTION & LOGGING
# =====================================================================

func interpolate_template(template_str: String, context: Dictionary) -> String:
	return LauncherUtils.interpolate_template(template_str, context)

func build_launch_context(game_path: String, patch_path: String = "", rom_path: String = "", game_name: String = "", total_games: int = 1) -> Dictionary:
	var player_name: String = ""
	for player_info in NetworkManager.players:
		if player_info.get("userId") == NetworkManager.user_id:
			player_name = player_info.get("name", "")
			break
	if player_name == "":
		player_name = NetworkManager.player_name

	var server_url: String = NetworkManager.get_ap_server_url()
	var server_clean_url: String = server_url.replace("ws://", "").replace("wss://", "").trim_suffix("/")
	var server_host: String = "localhost"
	var server_port: String = "38000"
	if server_url.begins_with("wss://") or "/ap/" in server_url:
		server_clean_url = server_url
		server_host = "wayfinder.disaac1.com"
		server_port = "443"
	elif server_clean_url.contains(":"):
		var parts: PackedStringArray = server_clean_url.split(":")
		server_host = parts[0]
		server_port = parts[1]
	elif server_clean_url != "":
		server_host = server_clean_url
	else:
		server_clean_url = "localhost:38000"

	var slot_name: String = player_name
	if game_name != "":
		var custom_tag: String = get_preset(game_name).get("short_tag", "")
		slot_name = YamlBuilder.get_slot_name(player_name, game_name, total_games, custom_tag)

	var user_profile: String = OS.get_environment("USERPROFILE").replace("\\", "/")
	var local_appdata: String = OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	var appdata_locallow: String = (OS.get_environment("USERPROFILE") + "/AppData/LocalLow").replace("\\", "/")
	var appdata_roaming: String = OS.get_environment("APPDATA").replace("\\", "/")

	var context: Dictionary = {
		"player_name": player_name,
		"slot_name": slot_name,
		"server_url": server_url,
		"server_clean_url": server_clean_url,
		"server_host": server_host,
		"server_port": server_port,
		"room_code": NetworkManager.room_code,
		"patch_path": ProjectSettings.globalize_path(patch_path) if patch_path != "" else "",
		"rom_path": ProjectSettings.globalize_path(rom_path) if rom_path != "" else "",
		"game_path": ProjectSettings.globalize_path(game_path) if game_path != "" else "",
		"game_dir": ProjectSettings.globalize_path(game_path.get_base_dir()) if game_path != "" else "",
		"user_profile": user_profile,
		"local_appdata": local_appdata,
		"appdata_locallow": appdata_locallow,
		"appdata_roaming": appdata_roaming,
		"user_tools_dir": ProjectSettings.globalize_path(USER_TOOLS_DIR),
		"user_saves_dir": ProjectSettings.globalize_path(USER_SAVES_DIR)
	}
	return context

func apply_config_writer(preset_config: Dictionary, context: Dictionary) -> bool:
	return _config_writer_service.apply(preset_config, context)

func _merge_and_interpolate_json(base: Dictionary, updates: Dictionary, context: Dictionary) -> Dictionary:
	return LauncherUtils.merge_and_interpolate_json(base, updates, context)

func launch_process_with_logging(node: Node, executable_path: String, args: Array, tag: String = "Client") -> int:
	return _process_launcher.launch(node, executable_path, args, tag)

func _read_pipe_logs(stdout_pipe: FileAccess, stderr_pipe: FileAccess, tag: String) -> void:
	_process_launcher._read_pipe_logs(stdout_pipe, stderr_pipe, tag)

func inject_server_into_ap_patch(patch_path: String, clean_url: String) -> void:
	ArchipelagoConfig.inject_server_into_ap_patch(patch_path, clean_url)

func update_archipelago_persistent_storage(clean_url: String) -> void:
	ArchipelagoConfig.update_archipelago_persistent_storage(clean_url, USER_TOOLS_DIR)

# =====================================================================
#             STREAMLINED ASYNC LAUNCH PIPELINE
# =====================================================================

func _report_status(ctx: LaunchContext, stage: LaunchStage, message: String, pct: float) -> void:
	WayfinderLogger.log_message("LAUNCH", "[" + str(stage) + " - " + str(int(pct)) + "%] " + message)
	emit_signal("launch_status_updated", int(stage), message, pct)
	if is_instance_valid(ctx.node):
		_update_modding_status(ctx.node, message, int(pct))

func launch_game(node: Node, game_name: String) -> bool:
	WayfinderLogger.log_message("LAUNCH", "Initiating launch pipeline for game: " + game_name)
	if game_name.strip_edges() == "":
		var err_msg: String = "Game name cannot be empty."
		WayfinderLogger.log_message("ERROR", err_msg)
		emit_signal("launch_failed", game_name, err_msg)
		if is_instance_valid(node):
			_update_modding_status(node, err_msg, 0)
		return false

	var preset: Dictionary = get_preset(game_name)
	if preset.is_empty():
		var err_msg: String = "No preset configuration found for " + game_name
		WayfinderLogger.log_message("ERROR", err_msg)
		emit_signal("launch_failed", game_name, err_msg)
		if is_instance_valid(node):
			_update_modding_status(node, err_msg, 0)
		return false
		
	var ctx: LaunchContext = LaunchContext.new(game_name, preset, node)
	_report_status(ctx, LaunchStage.INITIALIZING, "Preparing " + game_name + "...", 5)
	
	if not await _pipeline_prepare_base_assets(ctx):
		return false
	if not await _pipeline_prepare_tools(ctx):
		return false
	if not await _pipeline_prepare_firmware(ctx):
		return false
	if not await _pipeline_prepare_session_payload(ctx):
		return false
	if not await _pipeline_sync_environment(ctx):
		return false
	if not await _pipeline_spawn_process(ctx):
		return false
	await _pipeline_monitor_post_launch(ctx)
	
	emit_signal("launch_completed", game_name, ctx.process_id)
	return true

func _pipeline_prepare_base_assets(ctx: LaunchContext) -> bool:
	_report_status(ctx, LaunchStage.PREPARING_ROM, "Verifying game assets for " + ctx.game_name + "...", 15)
	var req_rom: String = ctx.preset.get("required_rom", "")
	var is_rom_game: bool = (req_rom != "" or ctx.launch_mode in ["ap_client", "patch_rom"])
	
	if is_rom_game and req_rom != "":
		_report_status(ctx, LaunchStage.PREPARING_ROM, "Verifying base ROM: " + req_rom + "...", 15)
		
		# 1. Check paths_config via get_saved_path
		var stored_path: String = get_saved_path(ctx.game_name, ctx.preset)
		if stored_path != "" and FileAccess.file_exists(stored_path) and not stored_path.to_lower().ends_with(".exe"):
			ctx.base_rom_path = stored_path
			return true
			
		# 2. Check local games folder or legacy locations
		var found_rom: String = find_existing_base_rom(req_rom)
		if found_rom != "":
			ctx.base_rom_path = found_rom
			paths_config[ctx.game_name] = found_rom
			save_paths_config()
			return true
			
		# 3. Check automated download in roms_catalog
		var dl_entry: Dictionary = get_rom_download_entry(req_rom)
		if dl_entry.is_empty():
			dl_entry = get_rom_download_entry(ctx.game_name)
		if not dl_entry.is_empty() and dl_entry.get("url", "") != "":
			_report_status(ctx, LaunchStage.PREPARING_ROM, "Downloading base ROM for " + ctx.game_name + "...", 20)
			var rom_res: Dictionary = await _async_ensure_rom(ctx.node, req_rom)
			if rom_res.get("success", false) and rom_res.get("path", "") != "":
				ctx.base_rom_path = rom_res.get("path")
				paths_config[ctx.game_name] = ctx.base_rom_path
				save_paths_config()
				return true
				
		# 4. Prompt user to select file
		_report_status(ctx, LaunchStage.PREPARING_ROM, "Base ROM required: " + req_rom, 15)
		var prompt_state: Dictionary = {"path": "", "done": false}
		var filters: PackedStringArray = PackedStringArray(["*.bin, *.iso, *.cue, *.gba, *.smc, *.sfc, *.z64, *.n64 ; ROM Files", "*.* ; All Files"])
		emit_signal("prompt_file_selection", "Base ROM Required for " + ctx.game_name, "Please select your vanilla base ROM file (" + req_rom + ").", filters, func(chosen: String):
			prompt_state["path"] = chosen
			prompt_state["done"] = true
		)
		while not prompt_state["done"]:
			if not is_instance_valid(ctx.node) or not ctx.node.get_tree():
				return false
			await ctx.node.get_tree().create_timer(0.05).timeout
			
		var user_selected_path: String = prompt_state["path"]
		if user_selected_path == "" or not FileAccess.file_exists(user_selected_path):
			emit_signal("launch_failed", ctx.game_name, "Base ROM selection was cancelled or file does not exist.")
			return false
			
		var game_dir: String = get_game_dir(ctx.game_name)
		var target_dest: String = game_dir.path_join(req_rom)
		if user_selected_path != target_dest:
			var copy_err: Error = DirAccess.copy_absolute(user_selected_path, target_dest)
			ctx.base_rom_path = target_dest if copy_err == OK else user_selected_path
		else:
			ctx.base_rom_path = user_selected_path
		paths_config[ctx.game_name] = ctx.base_rom_path
		save_paths_config()
		return true

	else:
		# Direct executable game
		var stored_exe: String = get_saved_path(ctx.game_name, ctx.preset)
		if stored_exe != "" and FileAccess.file_exists(stored_exe):
			ctx.base_rom_path = stored_exe
			return true
			
		var exec_name: String = ctx.preset.get("client_executable", ctx.preset.get("executable_name", ""))
		var sub_folders: Array = ctx.preset.get("sub_folders", [])
		var aliases: Array = ctx.preset.get("executable_aliases", [])
		if exec_name != "" or not aliases.is_empty():
			var discovered: String = find_game_executable(exec_name, sub_folders, aliases, true)
			if discovered != "":
				ctx.base_rom_path = discovered
				paths_config[ctx.game_name] = discovered
				save_paths_config()
				return true
				
		# Check if download link is available in roms_catalog for PC game
		var pc_dl_entry: Dictionary = get_rom_download_entry(ctx.game_name)
		if pc_dl_entry.is_empty() and exec_name != "":
			pc_dl_entry = get_rom_download_entry(exec_name)
		for a in aliases:
			if pc_dl_entry.is_empty():
				pc_dl_entry = get_rom_download_entry(str(a))
			else:
				break
		if not pc_dl_entry.is_empty() and pc_dl_entry.get("url", "") != "":
			_report_status(ctx, LaunchStage.PREPARING_ROM, "Downloading PC game files for " + ctx.game_name + "...", 20)
			var pc_res: Dictionary = await _async_ensure_pc_game(ctx.node, ctx.game_name, ctx.preset)
			if pc_res.get("success", false) and pc_res.get("path", "") != "":
				ctx.base_rom_path = pc_res.get("path")
				paths_config[ctx.game_name] = ctx.base_rom_path
				save_paths_config()
				return true
				
		# Prompt executable selection
		var prompt_state: Dictionary = {"path": "", "done": false}
		var filters: PackedStringArray = PackedStringArray(["*.exe ; Executables", "*.* ; All Files"])
		emit_signal("prompt_file_selection", "Executable Required for " + ctx.game_name, "Please locate where " + ctx.game_name + " is installed.", filters, func(chosen: String):
			prompt_state["path"] = chosen
			prompt_state["done"] = true
		)
		while not prompt_state["done"]:
			if not is_instance_valid(ctx.node) or not ctx.node.get_tree():
				return false
			await ctx.node.get_tree().create_timer(0.05).timeout
			
		var user_exe: String = prompt_state["path"]
		if user_exe == "" or not FileAccess.file_exists(user_exe):
			emit_signal("launch_failed", ctx.game_name, "Executable selection was cancelled or file does not exist.")
			return false
		ctx.base_rom_path = user_exe
		paths_config[ctx.game_name] = user_exe
		save_paths_config()
		return true

func _pipeline_prepare_tools(ctx: LaunchContext) -> bool:
	_report_status(ctx, LaunchStage.PREPARING_TOOLS, "Preparing tools and dependencies...", 30)
	# Client Tool (e.g. Archipelago Launcher)
	var client_tool_key: String = ctx.preset.get("client_tool", "")
	if client_tool_key != "":
		_report_status(ctx, LaunchStage.PREPARING_TOOLS, "Verifying client tool...", 30)
		var client_tool: Dictionary = launcher_tools.get(client_tool_key, {})
		var client_path: String = _resolve_tool_path(client_tool_key, client_tool)
		if client_path != "":
			ctx.client_exe_path = client_path
		else:
			var c_url: String = client_tool.get("download_url", DEFAULT_ARCHIPELAGO_DOWNLOAD_URL)
			var c_fallback: String = client_tool.get("fallback_download_url", DEFAULT_ARCHIPELAGO_DOWNLOAD_URL)
			var subs_arr: Array = client_tool.get("sub_folders", ["Archipelago"])
			var c_sub: String = subs_arr[0] if not subs_arr.is_empty() else "Archipelago"
			var c_exe: String = client_tool.get("executable", "ArchipelagoLauncher.exe")
			var tool_res: Dictionary = await _async_ensure_tool(ctx.node, client_tool.get("name", "Archipelago Client"), c_url, c_sub, c_exe, c_fallback)
			if tool_res.get("success", false) and tool_res.get("path", "") != "":
				ctx.client_exe_path = tool_res.get("path")
				paths_config[client_tool_key] = ctx.client_exe_path
				save_paths_config()
			else:
				var detail: String = tool_res.get("error", "Unknown error")
				emit_signal("launch_failed", ctx.game_name, "Failed to install client tool (" + client_tool_key + "): " + detail)
				return false
				
	# Emulator Tool (e.g. BizHawk / SNES9x)
	var emu_tool_key: String = ctx.preset.get("emulator_tool", "")
	if emu_tool_key != "":
		_report_status(ctx, LaunchStage.PREPARING_TOOLS, "Verifying emulator...", 40)
		var emu_tool: Dictionary = launcher_tools.get(emu_tool_key, {})
		var emu_cfg_key: String = emu_tool_key + "_emulator"
		var emu_path: String = _resolve_tool_path(emu_tool_key, emu_tool, emu_cfg_key)
		if emu_path != "":
			ctx.emulator_exe_path = emu_path
		else:
			var e_url: String = emu_tool.get("download_url", "")
			var e_fallback: String = emu_tool.get("fallback_download_url", "")
			var e_subs_arr: Array = emu_tool.get("sub_folders", ["BizHawk"])
			var e_sub: String = e_subs_arr[0] if not e_subs_arr.is_empty() else "BizHawk"
			var e_exe: String = emu_tool.get("executable", "EmuHawk.exe")
			var emu_res: Dictionary = await _async_ensure_tool(ctx.node, emu_tool.get("name", "Emulator"), e_url, e_sub, e_exe, e_fallback)
			if emu_res.get("success", false) and emu_res.get("path", "") != "":
				ctx.emulator_exe_path = emu_res.get("path")
				paths_config[emu_cfg_key] = ctx.emulator_exe_path
				save_paths_config()
			else:
				var detail: String = emu_res.get("error", "Unknown error")
				emit_signal("launch_failed", ctx.game_name, "Failed to install emulator (" + emu_tool_key + "): " + detail)
				return false
				
	# 1. Declarative Steam Beta Requirement Check (Agnostic)
	if ctx.preset.has("required_steam_beta"):
		var steam_id: String = str(ctx.preset.get("steam_appid", "")).strip_edges()
		var beta_cfg: Dictionary = ctx.preset.get("required_steam_beta", {})
		if steam_id != "" and not beta_cfg.is_empty():
			var steam_res: Dictionary = LauncherUtils.check_steam_beta_status(ctx.base_rom_path, steam_id, beta_cfg, ctx.game_name)
			if steam_res.get("needs_downgrade", false):
				var target_branch: String = steam_res.get("target_beta", "required")
				emit_signal("launch_failed", ctx.game_name, ctx.game_name + " must be set to the " + target_branch + " Steam Beta branch before launching.")
				return false

	# 2. Declarative Mod File Activation Check (Agnostic)
	if ctx.preset.has("mod_activation"):
		var act_cfg: Dictionary = ctx.preset.get("mod_activation", {})
		if not act_cfg.is_empty() and act_cfg.get("auto_activate", true):
			var act_info: Dictionary = LauncherUtils.check_mod_activation_status(ctx.base_rom_path, act_cfg)
			if act_info.get("state", "") == "disabled_in_lumafly":
				_report_status(ctx, LaunchStage.PREPARING_TOOLS, "Activating modded game files...", 35)
				LauncherUtils.activate_mod_file(ctx.base_rom_path, act_cfg)

	# Custom Mod Packages (e.g. Modding API, Archipelago Mods)
	var packages: Array = _get_preset_packages(ctx.preset)
	if not packages.is_empty() and ctx.base_rom_path != "":
		var game_dir: String = ctx.base_rom_path.get_base_dir()
		for pkg_idx in range(packages.size()):
			var pkg = packages[pkg_idx]
			if pkg is Dictionary:
				var check_rel: String = pkg.get("check_file", "")
				var needs_install: bool = false
				if check_rel != "":
					var full_check: String = game_dir.path_join(check_rel)
					if not FileAccess.file_exists(full_check):
						needs_install = true
				var pkg_url: String = pkg.get("download_url", "")
				if needs_install and pkg_url != "":
					var resolved_url: String = pkg_url.replace("{backend_url}", NetworkManager.get_http_url())
					if resolved_url.begins_with("http://localhost:8080"):
						resolved_url = resolved_url.replace("http://localhost:8080", NetworkManager.get_http_url())
					var pkg_name: String = pkg.get("name", "Package " + str(pkg_idx + 1))
					var target_rel: String = pkg.get("extract_target", "")
					var target_extract_dir: String = game_dir if target_rel == "" else game_dir.path_join(target_rel)
					var backups: Array = pkg.get("backup_files", [])
					_report_status(ctx, LaunchStage.PREPARING_TOOLS, "Installing " + pkg_name + "...", 42)
					var pkg_res: Dictionary = await _async_download_package(ctx.node, resolved_url, target_extract_dir, pkg_name, backups)
					if not pkg_res.get("success", false):
						emit_signal("launch_failed", ctx.game_name, "Failed to install " + pkg_name + ": " + pkg_res.get("error", ""))
						return false
						
	return true

func _pipeline_prepare_firmware(ctx: LaunchContext) -> bool:
	if not ctx.preset.has("required_firmware") or ctx.emulator_exe_path == "":
		return true
	_report_status(ctx, LaunchStage.PREPARING_FIRMWARE, "Configuring emulator firmware & BIOS...", 50)
	var fw_ok: bool = await _async_ensure_firmware(ctx.node, ctx.preset, ctx.emulator_exe_path, ctx.base_rom_path)
	if not fw_ok:
		print("[Launcher Warning] Firmware setup returned false; proceeding with launch.")
	return true

func _pipeline_prepare_session_payload(ctx: LaunchContext) -> bool:
	if ctx.launch_mode in ["ap_client", "patch_rom", "native_cli"]:
		_report_status(ctx, LaunchStage.FETCHING_PATCH, "Retrieving multiworld seed patch...", 65)
		var patch_ext: String = ctx.preset.get("patch_extension", "")
		var patch_res: Dictionary = await _async_ensure_patch(ctx.node, ctx.game_name, patch_ext)
		if not patch_res.get("success", false) or patch_res.get("path", "") == "":
			emit_signal("launch_failed", ctx.game_name, "Could not retrieve seed patch: " + patch_res.get("error", ""))
			return false
		ctx.patch_path = patch_res.get("path")
		
		# Server connection URL
		var ap_url: String = NetworkManager.get_ap_server_url()
		var clean_url: String = ap_url.replace("ws://", "").replace("wss://", "").trim_suffix("/")
		if clean_url == "":
			clean_url = "localhost:38000"
		if ap_url.begins_with("wss://") or "/ap/" in ap_url:
			clean_url = ap_url
		ctx.server_url = clean_url
		DisplayServer.clipboard_set(clean_url)
		
		if ctx.launch_mode == "ap_client":
			inject_server_into_ap_patch(ctx.patch_path, clean_url)
			update_archipelago_persistent_storage(clean_url)
			
			var req_audio: String = ctx.preset.get("required_audio_rom", "")
			if req_audio != "":
				var patch_dir: String = ctx.patch_path.get_base_dir()
				var patch_audio_dest: String = patch_dir.path_join(req_audio)
				if not FileAccess.file_exists(patch_audio_dest):
					var t2_src: String = _find_supplemental_rom_path("", req_audio)
					if t2_src != "":
						DirAccess.copy_absolute(t2_src, patch_audio_dest)
						print("[Launcher] Copied required audio track to patch folder: ", patch_audio_dest)
	return true

func _pipeline_sync_environment(ctx: LaunchContext) -> bool:
	_report_status(ctx, LaunchStage.SYNCING_CONFIG, "Syncing configuration...", 78)
	if ctx.launch_mode == "ap_client":
		sync_custom_worlds_to_archipelago()
		sync_archipelago_host_yaml(ctx.base_rom_path, ctx.emulator_exe_path)
	elif ctx.launch_mode in ["direct", "mod_injector"]:
		var total_games: int = 1
		if is_instance_valid(ctx.node) and "local_selected_games" in ctx.node and not ctx.node.local_selected_games.is_empty():
			total_games = ctx.node.local_selected_games.size()
		var context: Dictionary = build_launch_context(ctx.base_rom_path, "", "", ctx.game_name, total_games)
		apply_config_writer(ctx.preset, context)
	return true

func _pipeline_spawn_process(ctx: LaunchContext) -> bool:
	_report_status(ctx, LaunchStage.SPAWNING_PROCESS, "Starting game process...", 88)
	if ctx.launch_mode == "ap_client":
		var global_patch_path: String = ProjectSettings.globalize_path(ctx.patch_path)
		var launch_args: Array = [global_patch_path]
		if ctx.preset.get("auto_connect", false) and ctx.server_url != "":
			launch_args.append("--")
			launch_args.append("--connect")
			launch_args.append(ctx.server_url)
			
		var target_client: String = ctx.client_exe_path
		if target_client != "" and FileAccess.file_exists(target_client):
			var abs_client: String = ProjectSettings.globalize_path(target_client)
			print("[Launcher] Spawning Archipelago with patch: ", abs_client, " args: ", launch_args)
			ctx.process_id = OS.create_process(abs_client, launch_args)
		else:
			print("[Launcher] Opening patch file directly via OS: ", global_patch_path)
			var shell_err = OS.shell_open(global_patch_path)
			if shell_err == OK:
				ctx.process_id = 1
				
		if ctx.process_id <= 0:
			emit_signal("launch_failed", ctx.game_name, "Failed to spawn Archipelago process: " + target_client)
			return false
		print("[Launcher] Archipelago Client spawned successfully (PID: ", ctx.process_id, ")")
		return true

	elif ctx.launch_mode in ["direct", "steam", "mod_injector"]:
		var abs_game_path: String = ProjectSettings.globalize_path(ctx.base_rom_path)
		var steam_appid: String = str(ctx.preset.get("steam_appid", "")).strip_edges()
		if steam_appid != "":
			var appid_path: String = abs_game_path.get_base_dir().path_join("steam_appid.txt")
			if not FileAccess.file_exists(appid_path):
				var fa: FileAccess = FileAccess.open(appid_path, FileAccess.WRITE)
				if fa:
					fa.store_string(steam_appid)
					fa.close()
			OS.set_environment("SteamAppId", steam_appid)
			OS.set_environment("SteamGameId", steam_appid)

		var prefer_steam: bool = ctx.preset.get("prefer_steam_protocol", false) or ctx.launch_mode == "steam"
		var is_steam_path: bool = abs_game_path.to_lower().contains("steamapps") or abs_game_path.to_lower().contains("steam")
		if steam_appid != "" and (ctx.launch_mode == "steam" or (prefer_steam and is_steam_path)):
			print("[Launcher] Launching via Steam protocol: steam://rungameid/", steam_appid)
			OS.shell_open("steam://rungameid/" + steam_appid)
			ctx.process_id = 1
			return true

		var total_games: int = 1
		if is_instance_valid(ctx.node) and "local_selected_games" in ctx.node and not ctx.node.local_selected_games.is_empty():
			total_games = ctx.node.local_selected_games.size()
		var context: Dictionary = build_launch_context(abs_game_path, "", "", ctx.game_name, total_games)
		var custom_args: Array = []
		if ctx.preset.has("cli") and ctx.preset["cli"] is Dictionary:
			var cli_cfg: Dictionary = ctx.preset["cli"]
			if cli_cfg.has("environment_variables") and cli_cfg["environment_variables"] is Dictionary:
				var envs: Dictionary = cli_cfg["environment_variables"]
				for env_k in envs.keys():
					OS.set_environment(str(env_k), interpolate_template(str(envs[env_k]), context))
			for arg in cli_cfg.get("args_template", []):
				custom_args.append(interpolate_template(str(arg), context))

		ctx.process_id = launch_process_with_logging(ctx.node, abs_game_path, custom_args, ctx.game_name)
		if ctx.process_id <= 0:
			emit_signal("launch_failed", ctx.game_name, "Failed to launch game executable: " + abs_game_path)
			return false
		return true

	elif ctx.launch_mode == "patch_rom":
		var abs_emu: String = ProjectSettings.globalize_path(ctx.emulator_exe_path)
		var abs_patch: String = ProjectSettings.globalize_path(ctx.patch_path)
		print("[Launcher] Spawning emulator: ", abs_emu, " with ROM patch: ", abs_patch)
		ctx.process_id = OS.create_process(abs_emu, [abs_patch])
		if ctx.process_id <= 0:
			emit_signal("launch_failed", ctx.game_name, "Failed to launch emulator: " + abs_emu)
			return false
		return true

	elif ctx.launch_mode == "native_cli":
		var abs_native: String = ProjectSettings.globalize_path(ctx.base_rom_path)
		var final_args: Array = []
		var context: Dictionary = build_launch_context(abs_native, ctx.patch_path)
		if ctx.preset.has("cli") and ctx.preset["cli"] is Dictionary:
			var cli_cfg: Dictionary = ctx.preset["cli"]
			if cli_cfg.has("environment_variables") and cli_cfg["environment_variables"] is Dictionary:
				var envs: Dictionary = cli_cfg["environment_variables"]
				for env_k in envs.keys():
					OS.set_environment(str(env_k), interpolate_template(str(envs[env_k]), context))
			for arg_item in cli_cfg.get("args_template", []):
				final_args.append(interpolate_template(str(arg_item), context))
			if ctx.patch_path != "" and cli_cfg.has("patch_arg"):
				final_args.append(cli_cfg["patch_arg"])
				final_args.append(ProjectSettings.globalize_path(ctx.patch_path))
		else:
			if ctx.patch_path != "":
				final_args.append(ProjectSettings.globalize_path(ctx.patch_path))
		ctx.process_id = OS.create_process(abs_native, final_args)
		if ctx.process_id <= 0:
			ctx.process_id = launch_process_with_logging(ctx.node, abs_native, final_args, ctx.game_name)
		if ctx.process_id <= 0:
			emit_signal("launch_failed", ctx.game_name, "Failed to spawn native CLI process: " + abs_native)
			return false
		return true

	return false

func _pipeline_monitor_post_launch(ctx: LaunchContext) -> void:
	var tracking_cfg: Dictionary = ctx.preset.get("patch_progress_tracking", {})
	var has_tracking: bool = not tracking_cfg.is_empty()
	if has_tracking and ctx.patch_path != "":
		var custom_msg: String = tracking_cfg.get("status_message", "Modding game files...\nPlease wait...")
		_report_status(ctx, LaunchStage.MODDING_DISC, custom_msg, 50)
		await _track_client_modding_and_finish(ctx.node, ctx.patch_path, true, tracking_cfg)
	else:
		_report_status(ctx, LaunchStage.COMPLETED, "Game launched successfully!", 100)
		if is_instance_valid(ctx.node) and ctx.node.get_tree():
			await ctx.node.get_tree().create_timer(0.8).timeout
		_dismiss_modding_overlay(ctx.node)

func _async_ensure_rom(node: Node, rom_name: String) -> Dictionary:
	var state: Dictionary = {"done": false, "ok": false, "val": ""}
	ensure_rom_exists_or_download(node, rom_name, func(ok: bool, val: String):
		state["ok"] = ok
		state["val"] = val
		state["done"] = true
	)
	while not state["done"]:
		if not is_instance_valid(node) or not node.get_tree():
			return {"success": false, "error": "Context destroyed"}
		await node.get_tree().create_timer(0.05).timeout
	return {"success": state["ok"], "path": state["val"] if state["ok"] else "", "error": state["val"] if not state["ok"] else ""}

func _async_ensure_pc_game(node: Node, game_name: String, preset_config: Dictionary) -> Dictionary:
	var state: Dictionary = {"done": false, "ok": false, "val": ""}
	ensure_pc_game_installed(node, game_name, preset_config, func(ok: bool, val: String):
		state["ok"] = ok
		state["val"] = val
		state["done"] = true
	)
	while not state["done"]:
		if not is_instance_valid(node) or not node.get_tree():
			return {"success": false, "error": "Context destroyed"}
		await node.get_tree().create_timer(0.05).timeout
	return {"success": state["ok"], "path": state["val"] if state["ok"] else "", "error": state["val"] if not state["ok"] else ""}

func _async_ensure_tool(node: Node, tool_name: String, download_url: String, subfolder: String, target_file: String, fallback_url: String = "") -> Dictionary:
	_tool_installation_generation += 1
	var request = _tool_manager.create_install_request(
		node,
		tool_name,
		download_url,
		subfolder,
		target_file,
		fallback_url,
		_tool_installation_generation
	)
	var state: Dictionary = {"done": false, "ok": false, "val": ""}
	ensure_tool_installed_or_download(node, tool_name, download_url, subfolder, target_file, func(ok: bool, val: String):
		state["ok"] = ok
		state["val"] = val
		state["done"] = true
	, request.fallback_url, request.generation)
	while not state["done"]:
		if not is_instance_valid(node) or not node.get_tree():
			cancel_tool_installation()
			return _tool_manager.install_failure("Context destroyed")
		await node.get_tree().create_timer(0.05).timeout
	if state["ok"]:
		return _tool_manager.install_success(state["val"])
	return _tool_manager.install_failure(state["val"])

func _async_ensure_firmware(node: Node, preset: Dictionary, emu_path: String, rom_path: String) -> bool:
	var state: Dictionary = {"done": false, "ok": false}
	ensure_emulator_firmware(node, preset, emu_path, rom_path, func(ok: bool, _val: String):
		state["ok"] = ok
		state["done"] = true
	)
	while not state["done"]:
		if not is_instance_valid(node) or not node.get_tree():
			return false
		await node.get_tree().create_timer(0.05).timeout
	return state["ok"]

func _async_ensure_patch(node: Node, game_name: String, patch_ext: String) -> Dictionary:
	var state: Dictionary = {"done": false, "ok": false, "val": ""}
	ensure_patch_file_exists_or_download(node, game_name, patch_ext, func(ok: bool, val: String):
		state["ok"] = ok
		state["val"] = val
		state["done"] = true
	)
	while not state["done"]:
		if not is_instance_valid(node) or not node.get_tree():
			return {"success": false, "error": "Context destroyed"}
		await node.get_tree().create_timer(0.05).timeout
	return {"success": state["ok"], "path": state["val"] if state["ok"] else "", "error": state["val"] if not state["ok"] else ""}

func _async_download_package(node: Node, url: String, target_dir: String, label: String, backups: Array) -> Dictionary:
	var state: Dictionary = {"done": false, "ok": false, "err": ""}
	download_and_extract_zip_to_dir(node, url, target_dir, label, func(ok: bool, err: String):
		state["ok"] = ok
		state["err"] = err
		state["done"] = true
	, backups)
	while not state["done"]:
		if not is_instance_valid(node) or not node.get_tree():
			return {"success": false, "error": "Context destroyed"}
		await node.get_tree().create_timer(0.05).timeout
	return {"success": state["ok"], "error": state["err"]}

func _get_preset_packages(preset_config: Dictionary) -> Array:
	return _tool_manager.get_preset_packages(preset_config)

func _resolve_tool_path(tool_key: String, tool_def: Dictionary, fallback_cfg_key: String = "") -> String:
	return _tool_manager.resolve_path(tool_key, tool_def, fallback_cfg_key)

func execute_preset_launch(node: Node, game_name: String, preset_config: Dictionary, game_path: String, active_launch_game: String) -> void:
	var effective_game: String = game_name if game_name != "" else active_launch_game
	if game_path != "" and effective_game != "":
		paths_config[effective_game] = game_path
		save_paths_config()
	launch_game(node, effective_game)


# =====================================================================
#                GAME LAUNCH STATUS & DETECTION
# =====================================================================

func get_game_launch_status(game_name: String) -> Dictionary:
	var preset: Dictionary = get_preset(game_name)
	var launch_mode: String = preset.get("launch_mode", "direct")
	var req_rom: String = preset.get("required_rom", "")
	var is_rom_game: bool = (req_rom != "" or launch_mode == "patch_rom" or preset.get("is_rom", false))

	var stored_path: String = get_saved_path(game_name, preset)

	if stored_path != "" and FileAccess.file_exists(stored_path):
		var is_invalid_for_rom: bool = is_rom_game and (stored_path.to_lower().ends_with(".exe"))
		if not is_invalid_for_rom:
			if not paths_config.has(game_name) or paths_config[game_name] != stored_path:
				paths_config[game_name] = stored_path
				save_paths_config()
			if preset.has("required_steam_beta"):
				var steam_id: String = str(preset.get("steam_appid", "")).strip_edges()
				var beta_cfg: Dictionary = preset.get("required_steam_beta", {})
				if steam_id != "" and not beta_cfg.is_empty():
					var steam_res: Dictionary = LauncherUtils.check_steam_beta_status(stored_path, steam_id, beta_cfg, game_name)
					if steam_res.get("needs_downgrade", false):
						return {
							"is_configured": false,
							"path": stored_path,
							"is_default_location": false,
							"status_text": "⚠️ Steam Beta Required",
							"status_color": Color(0.95, 0.65, 0.15),
							"steam_beta_status": steam_res
						}
			return {
				"is_configured": true,
				"path": stored_path,
				"is_default_location": false,
				"status_text": "● Configured",
				"status_color": Color(0.2, 0.85, 0.45)
			}
	
	if not is_rom_game:
		var target_exe: String = preset.get("default_executable", preset.get("client_executable", preset.get("executable_name", preset.get("target_exe", ""))))
		var sub_folders: Array = preset.get("common_folders", preset.get("sub_folders", []))
		var aliases: Array = preset.get("executable_aliases", [])
		if target_exe != "" or not aliases.is_empty():
			# Fast direct candidate check only - do not deep search during status queries
			var found_exe: String = find_game_executable(target_exe, sub_folders, aliases, false)
			if found_exe != "" and FileAccess.file_exists(found_exe):
				paths_config[game_name] = found_exe
				save_paths_config()
			if preset.has("required_steam_beta"):
				var steam_id: String = str(preset.get("steam_appid", "")).strip_edges()
				var beta_cfg: Dictionary = preset.get("required_steam_beta", {})
				if steam_id != "" and not beta_cfg.is_empty():
					var steam_res: Dictionary = LauncherUtils.check_steam_beta_status(found_exe, steam_id, beta_cfg, game_name)
					if steam_res.get("needs_downgrade", false):
						return {
							"is_configured": false,
							"path": found_exe,
							"is_default_location": true,
							"status_text": "⚠️ Steam Beta Required",
							"status_color": Color(0.95, 0.65, 0.15),
							"steam_beta_status": steam_res
						}
				return {
					"is_configured": true,
					"path": found_exe,
					"is_default_location": true,
					"status_text": "● Installed (Auto-Detected)",
					"status_color": Color(0.2, 0.85, 0.45)
				}
	else:
		if req_rom != "":
			var found_rom: String = find_existing_base_rom(req_rom)
			if found_rom != "" and FileAccess.file_exists(found_rom):
				paths_config[game_name] = found_rom
				save_paths_config()
				return {
					"is_configured": true,
					"path": found_rom,
					"is_default_location": true,
					"status_text": "● ROM Ready (Auto-Detected)",
					"status_color": Color(0.2, 0.85, 0.45)
				}
				
	var dl_check: Dictionary = get_rom_download_entry(game_name)
	if dl_check.is_empty() and req_rom != "":
		dl_check = get_rom_download_entry(req_rom)
	if not dl_check.is_empty() and dl_check.get("url", "") != "":
		return {
			"is_configured": false,
			"path": "",
			"is_default_location": false,
			"status_text": "○ Download Available",
			"status_color": Color(0.2, 0.75, 1.0)
		}

	return {
		"is_configured": false,
		"path": "",
		"is_default_location": false,
		"status_text": "○ Setup / Path Required",
		"status_color": Color(0.9, 0.6, 0.15)
	}

func is_game_configured(game_name: String) -> bool:
	return get_game_launch_status(game_name).get("is_configured", false)


# =====================================================================
#                PATCH FILE DOWNLOAD & DISCOVERY
# =====================================================================

func is_matching_patch_file(filename: String, patch_extension: String, game_name: String = "") -> bool:
	return _patch_manager.is_matching_file(filename, patch_extension, game_name)

func ensure_patch_file_exists_or_download(node: Node, active_launch_game: String, patch_extension: String, callback: Callable) -> void:
	_patch_manager.ensure(node, active_launch_game, patch_extension, callback)

func fallback_download_seed_zip(node: Node, active_launch_game: String, patch_extension: String, callback: Callable) -> void:
	_patch_manager.fallback(node, active_launch_game, patch_extension, callback)
# =====================================================================
#             MODDING STATUS & PROGRESS TRACKING
# =====================================================================

func _update_modding_status(node: Node, message: String, pct: int) -> void:
	if not is_instance_valid(node):
		return
	if node.has_method("set_modding_status"):
		node.set_modding_status(message, pct)
		return
	elif node.has_node("%LaunchOverlay") and node.get_node("%LaunchOverlay").has_method("set_modding_status"):
		node.get_node("%LaunchOverlay").set_modding_status(message, pct)
		return
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
	if node.has_node("%LaunchProgressBar"):
		var pbar = node.get_node("%LaunchProgressBar")
		pbar.visible = true
		pbar.value = pct
	if "launch_title" in node and is_instance_valid(node.launch_title):
		node.launch_title.text = "Modding & Launching Game"
	if "launch_instructions" in node and is_instance_valid(node.launch_instructions):
		node.launch_instructions.text = message

func _dismiss_modding_overlay(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.has_node("%LaunchOverlay"):
		var overlay = node.get_node("%LaunchOverlay")
		if overlay.has_method("close"):
			overlay.close()
		else:
			overlay.visible = false
	if node.has_node("%LaunchProgressBar"):
		node.get_node("%LaunchProgressBar").visible = false
	if node.has_method("_render_play_dashboard"):
		node._render_play_dashboard()

func _check_extension_exists_in_dir(dir_path: String, target_ext: String) -> bool:
	var da: DirAccess = DirAccess.open(dir_path)
	if not da:
		da = DirAccess.open(ProjectSettings.globalize_path(dir_path))
	if not da:
		return false
	da.list_dir_begin()
	var f: String = da.get_next()
	var ext_lower: String = target_ext.to_lower()
	while f != "":
		if not da.current_is_dir() and f.to_lower().ends_with(ext_lower):
			return true
		f = da.get_next()
	return false

func _track_client_modding_and_finish(node: Node, patch_path: String, has_tracking: bool, tracking_cfg: Dictionary = {}) -> void:
	if not has_tracking:
		if is_instance_valid(node) and node.get_tree():
			await node.get_tree().create_timer(1.2).timeout
		_dismiss_modding_overlay(node)
		return
		
	var patch_base: String = patch_path.get_basename()
	var comp_ext: String = tracking_cfg.get("completion_extension", "")
	var prog_ext: String = tracking_cfg.get("progress_extension", "")
	var exp_bytes: float = float(tracking_cfg.get("expected_bytes", 0.0))
	var expected_comp: String = (patch_base + comp_ext) if comp_ext != "" else ""
	var expected_prog: String = (patch_base + prog_ext) if prog_ext != "" else ""
	var total_mb_str: String = String.num(exp_bytes / (1024.0 * 1024.0), 0) if exp_bytes > 0.0 else ""
	
	var elapsed_ticks: int = 0
	var max_wait_ticks: int = 120 # up to 60 seconds (120 * 0.5s)
	var highest_pct: int = 50
	
	while elapsed_ticks < max_wait_ticks:
		if not is_instance_valid(node) or not node.get_tree():
			break
		await node.get_tree().create_timer(0.5).timeout
		elapsed_ticks += 1
		
		var comp_exists: bool = false
		if expected_comp != "":
			comp_exists = FileAccess.file_exists(expected_comp) or FileAccess.file_exists(ProjectSettings.globalize_path(expected_comp))
			if not comp_exists:
				comp_exists = _check_extension_exists_in_dir(expected_comp.get_base_dir(), comp_ext)
			
		if comp_exists:
			var done_msg: String = "Patch modification complete" + ((" (" + total_mb_str + " MB)") if total_mb_str != "" else "") + "!\n\nClient starting up..."
			_update_modding_status(node, done_msg, 100)
			if is_instance_valid(node) and node.get_tree():
				await node.get_tree().create_timer(1.2).timeout
			_dismiss_modding_overlay(node)
			return
			
		var prog_exists: bool = false
		if expected_prog != "":
			prog_exists = FileAccess.file_exists(expected_prog) or FileAccess.file_exists(ProjectSettings.globalize_path(expected_prog))
		if prog_exists and exp_bytes > 0.0:
			var check_prog_path: String = expected_prog if FileAccess.file_exists(expected_prog) else ProjectSettings.globalize_path(expected_prog)
			var cur_fa: FileAccess = FileAccess.open(check_prog_path, FileAccess.READ)
			var cur_sz: int = 0
			if cur_fa:
				cur_sz = cur_fa.get_length()
				cur_fa.close()
			if cur_sz > 0:
				var mb_val: float = float(cur_sz) / (1024.0 * 1024.0)
				var pct_calc: int = int(clamp(50.0 + (float(cur_sz) / max(exp_bytes, 1.0)) * 45.0, 50, 95))
				highest_pct = max(highest_pct, pct_calc)
				_update_modding_status(node, "Modding image in progress...\n\nWriting patched output: " + String.num(mb_val, 1) + " MB / " + total_mb_str + " MB\nCalculating multiworld data...", highest_pct)
			else:
				var smooth_pct: int = int(clamp(50.0 + (float(elapsed_ticks) / float(max_wait_ticks)) * 42.0, 50, 92))
				highest_pct = max(highest_pct, smooth_pct)
				_update_modding_status(node, "Archipelago patcher active...\nModding game files, please wait...", highest_pct)
		else:
			# Monotonic smooth progress from 50% up to 92% (NEVER jumps backward)
			var smooth_pct: int = int(clamp(50.0 + (float(elapsed_ticks) / float(max_wait_ticks)) * 42.0, 50, 92))
			highest_pct = max(highest_pct, smooth_pct)
			_update_modding_status(node, "Archipelago patcher active...\nModding game files, please wait...", highest_pct)

	_dismiss_modding_overlay(node)
