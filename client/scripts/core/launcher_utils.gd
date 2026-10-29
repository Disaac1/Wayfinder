class_name LauncherUtils
extends RefCounted

## Resolves shareable URLs (e.g. Google Drive) to direct download URLs
static func resolve_download_url(raw_url: String) -> String:
	var trimmed: String = raw_url.strip_edges()
	if "drive.google.com" in trimmed:
		var file_id: String = ""
		# Pattern 1: /file/d/<FILE_ID>
		var regex_d = RegEx.new()
		regex_d.compile("drive\\.google\\.com/file/d/([a-zA-Z0-9_-]+)")
		var match_d = regex_d.search(trimmed)
		if match_d:
			file_id = match_d.get_string(1)
		else:
			# Pattern 2: id=<FILE_ID>
			var regex_id = RegEx.new()
			regex_id.compile("[?&]id=([a-zA-Z0-9_-]+)")
			var match_id = regex_id.search(trimmed)
			if match_id:
				file_id = match_id.get_string(1)
				
		if file_id != "":
			var resolved = "https://drive.usercontent.google.com/download?id=" + file_id + "&export=download&confirm=t"
			print("[LauncherUtils] Resolved Google Drive link to direct download: ", resolved)
			return resolved
	return trimmed

## Decrypts an AES-256 CBC encrypted file with SHA-256 derived passphrase
static func decrypt_file_aes256(encrypted_path: String, output_path: String, passphrase: String, progress_callback: Callable = Callable()) -> bool:
	print("[LauncherUtils Crypto] Decrypting AES-256 archive: ", encrypted_path)
	var in_file: FileAccess = FileAccess.open(encrypted_path, FileAccess.READ)
	if not in_file:
		print("[LauncherUtils Error] Could not open encrypted file for reading: ", encrypted_path)
		return false
		
	var total_len: int = in_file.get_length()
	if total_len < 16:
		print("[LauncherUtils Error] Encrypted file is too small (", total_len, " bytes)")
		in_file.close()
		return false
		
	var iv: PackedByteArray = in_file.get_buffer(16)
	var key: PackedByteArray = passphrase.sha256_buffer()
	var aes: AESContext = AESContext.new()
	var err: Error = aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	if err != OK:
		print("[LauncherUtils Error] Failed to start AESContext decryption: ", err)
		in_file.close()
		return false
		
	var out_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if not out_file:
		print("[LauncherUtils Error] Could not open output file for decrypted data: ", output_path)
		in_file.close()
		return false
		
	var CHUNK_SIZE: int = 1024 * 1024
	var payload_size: int = total_len - 16
	var remaining: int = payload_size
	var prev_decrypted: PackedByteArray = PackedByteArray()
	var last_reported_pct: int = -1
	
	while remaining > 0:
		var to_read: int = min(remaining, CHUNK_SIZE)
		to_read = int(to_read / 16) * 16
		if to_read == 0:
			to_read = remaining
		var cipher_chunk: PackedByteArray = in_file.get_buffer(to_read)
		remaining -= cipher_chunk.size()
		
		var dec_chunk: PackedByteArray = aes.update(cipher_chunk)
		if remaining > 0:
			if not prev_decrypted.is_empty():
				out_file.store_buffer(prev_decrypted)
			prev_decrypted = dec_chunk
		else:
			if not prev_decrypted.is_empty():
				out_file.store_buffer(prev_decrypted)
			# Final chunk - strip PKCS#7 padding
			if not dec_chunk.is_empty():
				var pad_len: int = dec_chunk[dec_chunk.size() - 1]
				if pad_len > 0 and pad_len <= 16 and pad_len <= dec_chunk.size():
					var valid_pad: bool = true
					for i in range(dec_chunk.size() - pad_len, dec_chunk.size()):
						if dec_chunk[i] != pad_len:
							valid_pad = false
							break
					if valid_pad:
						dec_chunk = dec_chunk.slice(0, dec_chunk.size() - pad_len)
				out_file.store_buffer(dec_chunk)
		
		if progress_callback.is_valid():
			var done_bytes: int = payload_size - remaining
			var pct: int = int((float(done_bytes) / float(max(payload_size, 1))) * 100.0)
			if pct != last_reported_pct:
				last_reported_pct = pct
				progress_callback.call(pct, done_bytes, payload_size)
				
	aes.finish()
	in_file.close()
	out_file.close()
	print("[LauncherUtils Crypto] Successfully decrypted file to: ", output_path)
	return true

## Recursively discovers an executable in a directory up to max_depth
static func find_executable_recursive(dir_path: String, executable_name: String, current_depth: int = 0, max_depth: int = 4) -> String:
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

## Searches for a game executable across local games, tools, and platform search paths
static func find_game_executable(executable_name: String, sub_folders: Array, executable_aliases: Array = [], user_games_dir: String = "user://games", user_tools_dir: String = "user://tools", allow_deep_search: bool = true) -> String:
	var names_to_check: Array[String] = []
	if executable_name.strip_edges() != "":
		names_to_check.append(executable_name.strip_edges())
	for a in executable_aliases:
		var s: String = str(a).strip_edges()
		if s != "" and not names_to_check.has(s):
			names_to_check.append(s)

	# 1. Fast direct O(1) checks in user://games/ and user://tools/
	for exe in names_to_check:
		var g_direct: String = user_games_dir.path_join(exe)
		if FileAccess.file_exists(g_direct):
			return ProjectSettings.globalize_path(g_direct)
		for sub in sub_folders:
			var candidate: String = user_games_dir.path_join(sub).path_join(exe)
			if FileAccess.file_exists(candidate):
				return ProjectSettings.globalize_path(candidate)

		var t_direct: String = user_tools_dir.path_join(exe)
		if FileAccess.file_exists(t_direct):
			return ProjectSettings.globalize_path(t_direct)
		for sub in sub_folders:
			var candidate: String = user_tools_dir.path_join(sub).path_join(exe)
			if FileAccess.file_exists(candidate):
				return ProjectSettings.globalize_path(candidate)

	# 2. Fast direct O(1) candidate checks across all platform roots (Steam, GOG, Epic, etc.)
	var root_search_dirs: Array[String] = get_platform_search_roots()
	for root_dir in root_search_dirs:
		if root_dir == "" or not DirAccess.dir_exists_absolute(root_dir):
			continue
		for sub_folder in sub_folders:
			for exe in names_to_check:
				var candidate_path: String = root_dir.path_join(sub_folder).path_join(exe)
				if FileAccess.file_exists(candidate_path):
					return ProjectSettings.globalize_path(candidate_path)
		for exe in names_to_check:
			var direct_path: String = root_dir.path_join(exe)
			if FileAccess.file_exists(direct_path):
				return ProjectSettings.globalize_path(direct_path)

	# 3. Targeted shallow/deep search ONLY if enabled
	# Never scan the entire C:/Program Files or C:/Program Files (x86) root recursively
	if not allow_deep_search:
		return ""

	var deep_search_dirs: Array[String] = []
	if DirAccess.dir_exists_absolute(user_games_dir):
		deep_search_dirs.append(user_games_dir)
	if DirAccess.dir_exists_absolute(user_tools_dir):
		deep_search_dirs.append(user_tools_dir)

	var excluded_root_prefixes: Array[String] = []
	if OS.get_name() == "Windows":
		var pf = OS.get_environment("ProgramFiles").replace("\\", "/").trim_suffix("/")
		var pfx86 = OS.get_environment("ProgramFiles(x86)").replace("\\", "/").trim_suffix("/")
		var local_app = OS.get_environment("LOCALAPPDATA").replace("\\", "/").trim_suffix("/")
		var user_prof = OS.get_environment("USERPROFILE").replace("\\", "/").trim_suffix("/")
		if pf != "": excluded_root_prefixes.append(pf)
		if pfx86 != "": excluded_root_prefixes.append(pfx86)
		if local_app != "":
			excluded_root_prefixes.append(local_app)
			excluded_root_prefixes.append(local_app + "/Programs")
		if user_prof != "":
			excluded_root_prefixes.append(user_prof)
			excluded_root_prefixes.append(user_prof + "/Desktop")
			excluded_root_prefixes.append(user_prof + "/Downloads")
		excluded_root_prefixes.append("C:/Program Files")
		excluded_root_prefixes.append("C:/Program Files (x86)")
		excluded_root_prefixes.append("C:/ProgramData")

	for root_dir in root_search_dirs:
		var norm = root_dir.replace("\\", "/").trim_suffix("/")
		if excluded_root_prefixes.has(norm):
			continue
		if DirAccess.dir_exists_absolute(root_dir) and not deep_search_dirs.has(root_dir):
			deep_search_dirs.append(root_dir)

	for target_dir in deep_search_dirs:
		for exe in names_to_check:
			var recursive_found: String = find_executable_recursive(target_dir, exe, 0, 2)
			if recursive_found != "":
				return recursive_found

	return ""

## Returns OS-specific search paths where games and tools commonly reside
static func get_platform_search_roots() -> Array[String]:
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
			roots.append(local_appdata.path_join("Dolphin"))
			
		var user_profile: String = OS.get_environment("USERPROFILE")
		if user_profile != "":
			roots.append(user_profile.path_join("Archipelago"))
			roots.append(user_profile.path_join("AppData/Local/Programs/Archipelago"))
			roots.append(user_profile.path_join("Desktop"))
			roots.append(user_profile.path_join("Downloads"))

		roots.append("C:/Archipelago")
		roots.append("C:/BizHawk")
		roots.append("C:/Emulators/BizHawk")
		roots.append("C:/Program Files/BizHawk")
		roots.append("C:/Dolphin")
		roots.append("C:/Emulators/Dolphin")
		roots.append("C:/Program Files/Dolphin")
		roots.append("C:/Program Files (x86)/Dolphin")
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

## Substitutes {key} placeholders in a string from a dictionary context
static func interpolate_template(template_str: String, context: Dictionary) -> String:
	var result: String = template_str
	for key in context.keys():
		result = result.replace("{" + str(key) + "}", str(context[key]))
	return result

## Recursively merges and interpolates dictionary values with template replacement
static func merge_and_interpolate_json(base: Dictionary, updates: Dictionary, context: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for k in updates.keys():
		var val: Variant = updates[k]
		if val is Dictionary:
			var base_sub: Dictionary = result.get(k, {}) if result.get(k) is Dictionary else {}
			result[k] = merge_and_interpolate_json(base_sub, val, context)
		elif val is String:
			var str_val: String = interpolate_template(val, context)
			if (str(k).to_lower().ends_with("port") or val == "{server_port}") and str_val.is_valid_int():
				result[k] = str_val.to_int()
			else:
				result[k] = str_val
		else:
			result[k] = val
	return result

## Searches upward from a game directory to locate the Steam appmanifest file for a given App ID
static func find_steam_manifest(game_path_or_dir: String, appid: String) -> String:
	var manifest_name: String = "appmanifest_" + appid + ".acf"
	var current: String = game_path_or_dir
	if current.to_lower().ends_with(".exe"):
		current = current.get_base_dir()
	current = ProjectSettings.globalize_path(current).replace("\\", "/")

	# Direct relative check: steamapps/common/Game -> ../../appmanifest_<id>.acf
	var direct_steamapps: String = current.get_base_dir().get_base_dir()
	var direct_candidate: String = direct_steamapps.path_join(manifest_name)
	if FileAccess.file_exists(direct_candidate):
		return direct_candidate

	# Walk upward through parents
	var walk: String = current
	while walk != "" and walk != "/" and walk != walk.get_base_dir():
		if walk.get_file().to_lower() == "steamapps":
			var c: String = walk.path_join(manifest_name)
			if FileAccess.file_exists(c):
				return c
		var sub_apps: String = walk.path_join("steamapps")
		if DirAccess.dir_exists_absolute(sub_apps):
			var c2: String = sub_apps.path_join(manifest_name)
			if FileAccess.file_exists(c2):
				return c2
		walk = walk.get_base_dir()

	return ""

## Parses a Valve ACF / manifest file into a flat key-value dictionary
static func parse_steam_manifest(manifest_path: String) -> Dictionary:
	var parsed: Dictionary = {}
	if not FileAccess.file_exists(manifest_path):
		return parsed
	var fa: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if not fa:
		return parsed
	while not fa.eof_reached():
		var line: String = fa.get_line().strip_edges()
		if line == "" or line.begins_with("//") or line == "{" or line == "}":
			continue
		var tokens: PackedStringArray = line.split("\"")
		if tokens.size() >= 4:
			var key: String = tokens[1].strip_edges()
			var val: String = tokens[3].strip_edges()
			parsed[key] = val
	fa.close()
	return parsed

## Evaluates Steam beta branch requirements agnostically for any game preset
static func check_steam_beta_status(game_exe_or_dir: String, steam_appid: String, beta_config: Dictionary, game_name: String = "") -> Dictionary:
	var game_dir: String = game_exe_or_dir
	if game_dir.to_lower().ends_with(".exe"):
		game_dir = game_dir.get_base_dir()
	game_dir = ProjectSettings.globalize_path(game_dir).replace("\\", "/")

	var manifest_path: String = find_steam_manifest(game_dir, steam_appid)
	var is_steam: bool = (manifest_path != "")
	var is_correct_beta: bool = true
	var current_beta: String = ""

	var branch_key: String = beta_config.get("branch_key", "")
	var aliases: Array = beta_config.get("branch_aliases", [])
	var display_name: String = beta_config.get("display_name", branch_key)

	if is_steam:
		var manifest_data: Dictionary = parse_steam_manifest(manifest_path)
		if manifest_data.has("BetaKey"):
			current_beta = manifest_data["BetaKey"].strip_edges()
			if branch_key != "" and current_beta.contains(branch_key):
				is_correct_beta = true
			else:
				var alias_match: bool = false
				for a in aliases:
					if str(a) != "" and current_beta.contains(str(a)):
						alias_match = true
						break
				is_correct_beta = alias_match
		else:
			current_beta = "default (latest)"
			is_correct_beta = false

	var needs_downgrade: bool = is_steam and (not is_correct_beta)
	var guidance_text: String = ""
	if needs_downgrade:
		var g_title: String = game_name if game_name != "" else "This game"
		guidance_text += "[b][color=#f59e0b]⚠️ " + g_title + " Steam Beta Downgrade Required[/color][/b]\n\n"
		var custom_guidance: String = beta_config.get("guidance_message", "")
		if custom_guidance != "":
			guidance_text += custom_guidance.replace("{game_name}", g_title).replace("{display_name}", display_name) + "\n\n"
		else:
			guidance_text += g_title + " requires the [b]" + display_name + "[/b] Steam beta branch for mod compatibility.\n\n"
		guidance_text += "[b]How to Select in Steam Betas:[/b]\n"
		guidance_text += "1. Click [url=steam://gameproperties/" + steam_appid + "][color=#38bdf8]Open Steam Properties[/color][/url] (or use the button below).\n"
		guidance_text += "2. In Steam, click the [b]Betas[/b] tab on the left sidebar.\n"
		guidance_text += "3. In [b]Beta Participation[/b], select [b]" + display_name + "[/b].\n"
		guidance_text += "4. Wait for Steam to finish downloading the update.\n"
		guidance_text += "5. Return to Wayfinder and click [b]Launch[/b]!\n"

	return {
		"game_dir": game_dir,
		"manifest_path": manifest_path,
		"is_steam": is_steam,
		"is_correct_beta": is_correct_beta,
		"current_beta": current_beta,
		"target_beta": display_name,
		"needs_downgrade": needs_downgrade,
		"guidance_text": guidance_text
	}

## Checks whether a given file matches a specific mod marker string or hash (game-agnostic)
static func is_file_modded(file_path: String, mod_marker: String = "", mod_hash: String = "") -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	if mod_hash != "":
		var hash_str: String = FileAccess.get_sha256(file_path).to_lower()
		if hash_str == mod_hash.to_lower():
			return true
	if mod_marker != "":
		var fa: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if fa:
			var buf: PackedByteArray = fa.get_buffer(fa.get_length())
			fa.close()
			var needle: PackedByteArray = mod_marker.to_ascii_buffer()
			var n_size: int = needle.size()
			for i in range(buf.size() - n_size):
				if buf[i] == needle[0]:
					var is_match: bool = true
					for j in range(1, n_size):
						if buf[i + j] != needle[j]:
							is_match = false
							break
					if is_match:
						return true
	return false

## Inspects target file and modded/vanilla backups agnostically
static func check_mod_activation_status(game_exe_or_dir: String, activation_config: Dictionary) -> Dictionary:
	var game_dir: String = game_exe_or_dir
	if game_dir.to_lower().ends_with(".exe"):
		game_dir = game_dir.get_base_dir()
	game_dir = ProjectSettings.globalize_path(game_dir).replace("\\", "/")

	var target_rel: String = activation_config.get("target_file", "")
	var modded_rel: String = activation_config.get("modded_backup", "")
	var vanilla_rel: String = activation_config.get("vanilla_backup", "")
	var fallback_vanilla_rel: String = activation_config.get("vanilla_fallback_backup", "")

	var active_path: String = game_dir.path_join(target_rel) if target_rel != "" else ""
	var modded_path: String = game_dir.path_join(modded_rel) if modded_rel != "" else ""
	var vanilla_path: String = game_dir.path_join(vanilla_rel) if vanilla_rel != "" else ""
	var fallback_vanilla_path: String = game_dir.path_join(fallback_vanilla_rel) if fallback_vanilla_rel != "" else ""

	var mod_marker: String = activation_config.get("mod_marker", "")
	var mod_hash: String = activation_config.get("mod_hash", "")

	var is_active_modded: bool = false
	var has_modded_m: bool = false
	if mod_marker != "" or mod_hash != "":
		is_active_modded = is_file_modded(active_path, mod_marker, mod_hash)
		has_modded_m = is_file_modded(modded_path, mod_marker, mod_hash)
	else:
		has_modded_m = FileAccess.file_exists(modded_path)
	var has_vanilla_v: bool = FileAccess.file_exists(vanilla_path)
	var has_vanilla_bak: bool = FileAccess.file_exists(fallback_vanilla_path)

	var state: String = "vanilla_clean"
	if is_active_modded:
		state = "active"
	elif has_modded_m:
		state = "disabled_in_lumafly"
	elif not FileAccess.file_exists(active_path):
		state = "missing"

	return {
		"game_dir": game_dir,
		"active_file": active_path,
		"modded_backup": modded_path,
		"vanilla_backup": vanilla_path,
		"fallback_vanilla_backup": fallback_vanilla_path,
		"is_active_modded": is_active_modded,
		"has_modded_m": has_modded_m,
		"has_modded_backup": has_modded_m,
		"has_vanilla_v": has_vanilla_v,
		"has_vanilla_bak": has_vanilla_bak,
		"has_vanilla_backup": (has_vanilla_v or has_vanilla_bak),
		"state": state
	}

## Activates modded target file from backup
static func activate_mod_file(game_exe_or_dir: String, activation_config: Dictionary) -> Dictionary:
	var info: Dictionary = check_mod_activation_status(game_exe_or_dir, activation_config)
	var state: String = info.get("state", "")

	if state == "active":
		return {"success": true, "state": "already_active", "message": "Modded file is already active."}

	if state == "disabled_in_lumafly":
		var active_path: String = info.get("active_file", "")
		var modded_path: String = info.get("modded_backup", "")
		var v_path: String = info.get("vanilla_backup", "")

		if not FileAccess.file_exists(v_path) and FileAccess.file_exists(active_path):
			DirAccess.copy_absolute(active_path, v_path)

		var copy_mod_err: Error = DirAccess.copy_absolute(modded_path, active_path)
		if copy_mod_err != OK:
			return {"success": false, "state": "error", "message": "Failed to activate modded file (Error: %d)" % copy_mod_err}
		return {"success": true, "state": "activated", "message": "Activated modded file from backup."}

	return {"success": false, "state": state, "message": "Modded file not found."}

## Restores vanilla file from backup
static func restore_vanilla_file(game_exe_or_dir: String, activation_config: Dictionary) -> Dictionary:
	var info: Dictionary = check_mod_activation_status(game_exe_or_dir, activation_config)
	var active_path: String = info.get("active_file", "")
	var modded_path: String = info.get("modded_backup", "")
	var v_path: String = info.get("vanilla_backup", "")
	if not FileAccess.file_exists(v_path):
		v_path = info.get("fallback_vanilla_backup", "")

	if not FileAccess.file_exists(v_path):
		return {"success": false, "message": "No vanilla backup found."}

	if info.get("is_active_modded", false) and not FileAccess.file_exists(modded_path):
		DirAccess.copy_absolute(active_path, modded_path)

	var copy_err: Error = DirAccess.copy_absolute(v_path, active_path)
	if copy_err != OK:
		return {"success": false, "message": "Failed to restore vanilla file (Error: %d)" % copy_err}
	return {"success": true, "message": "Restored vanilla file."}

# =====================================================================
#                BACKWARD COMPATIBILITY ALIASES
# =====================================================================

static func is_dll_modded(dll_path: String) -> bool:
	return is_file_modded(dll_path, "ModHooks", "5944411bd93830369390a4b51766ee68c4ab26195b299e25a07b5e7d0e00086d")

static func check_assembly_csharp_status(game_exe_or_dir: String) -> Dictionary:
	return check_mod_activation_status(game_exe_or_dir, {
		"target_file": "hollow_knight_Data/Managed/Assembly-CSharp.dll",
		"modded_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.m",
		"vanilla_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.v",
		"vanilla_fallback_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.vanilla.bak",
		"mod_marker": "ModHooks",
		"mod_hash": "5944411bd93830369390a4b51766ee68c4ab26195b299e25a07b5e7d0e00086d"
	})

static func activate_modded_assembly(game_exe_or_dir: String) -> Dictionary:
	return activate_mod_file(game_exe_or_dir, {
		"target_file": "hollow_knight_Data/Managed/Assembly-CSharp.dll",
		"modded_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.m",
		"vanilla_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.v",
		"vanilla_fallback_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.vanilla.bak",
		"mod_marker": "ModHooks",
		"mod_hash": "5944411bd93830369390a4b51766ee68c4ab26195b299e25a07b5e7d0e00086d"
	})

static func restore_vanilla_assembly(game_exe_or_dir: String) -> Dictionary:
	return restore_vanilla_file(game_exe_or_dir, {
		"target_file": "hollow_knight_Data/Managed/Assembly-CSharp.dll",
		"modded_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.m",
		"vanilla_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.v",
		"vanilla_fallback_backup": "hollow_knight_Data/Managed/Assembly-CSharp.dll.vanilla.bak",
		"mod_marker": "ModHooks",
		"mod_hash": "5944411bd93830369390a4b51766ee68c4ab26195b299e25a07b5e7d0e00086d"
	})

static func check_hollow_knight_modding_status(game_exe_or_dir: String) -> Dictionary:
	var steam_status: Dictionary = check_steam_beta_status(game_exe_or_dir, "367520", {
		"branch_key": "1.5.78",
		"branch_aliases": ["1.5.78.11833", "1.4.3.2"],
		"display_name": "1.5.78 - 1.5.78"
	}, "Hollow Knight")
	var asm_info: Dictionary = check_assembly_csharp_status(game_exe_or_dir)
	var mmhook: String = ProjectSettings.globalize_path(game_exe_or_dir).get_base_dir().path_join("hollow_knight_Data/Managed/MMHOOK_Assembly-CSharp.dll")
	var has_mmhook: bool = FileAccess.file_exists(mmhook)
	var has_modding_api: bool = asm_info.get("is_active_modded", false) and has_mmhook
	var can_auto_activate: bool = asm_info.get("has_modded_m", false) and has_mmhook

	steam_status["assembly_status"] = asm_info
	steam_status["has_modding_api"] = has_modding_api
	steam_status["can_auto_activate"] = can_auto_activate
	steam_status["is_downgraded"] = steam_status.get("is_correct_beta", true)
	steam_status["is_ready"] = not steam_status.get("needs_downgrade", false)
	return steam_status
