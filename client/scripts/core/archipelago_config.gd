class_name ArchipelagoConfig
extends RefCounted

const USER_TOOLS_DIR: String = "user://tools"
const USER_BASE_ROMS_DIR: String = "user://base_roms"
const USER_GAMES_DIR: String = "user://games"



## Injects emulator firmware configuration into an emulator INI/config file
static func inject_emulator_firmware_config(emulator_dir: String, emu_cfg: Dictionary) -> void:
	if emu_cfg.is_empty():
		return
	var cfg_file: String = emu_cfg.get("file", "config.ini")
	var section: String = emu_cfg.get("section", "")
	var key: String = emu_cfg.get("key", "")
	var val: String = emu_cfg.get("value", "")
	if section == "" or key == "" or val == "":
		return

	var cfg_path: String = emulator_dir.path_join(cfg_file)
	if not FileAccess.file_exists(cfg_path):
		return
	var fa_in: FileAccess = FileAccess.open(cfg_path, FileAccess.READ)
	if not fa_in:
		return
	var cfg_text: String = fa_in.get_as_text()
	fa_in.close()

	var quote_key: String = "\"" + key + "\""
	if cfg_text.contains(quote_key):
		return

	var sec_open: String = "\"" + section + "\": {"
	var sec_bare: String = "\"" + section + "\":"
	if cfg_text.contains(sec_open):
		cfg_text = cfg_text.replace(
			sec_open,
			sec_open + "\n    \"" + key + "\": \"" + val + "\","
		)
	elif cfg_text.contains(sec_bare):
		cfg_text = cfg_text.replace(
			sec_bare,
			sec_bare + " {\n    \"" + key + "\": \"" + val + "\"\n  },"
		)

	var fa_out: FileAccess = FileAccess.open(cfg_path, FileAccess.WRITE)
	if fa_out:
		fa_out.store_string(cfg_text)
		fa_out.close()
		print("[ArchipelagoConfig] Updated ", cfg_file, " with [", section, "] ", key, " = ", val)

## Injects server URL into archipelago.json inside an .ap* patch archive
static func inject_server_into_ap_patch(patch_path: String, clean_url: String) -> void:
	if clean_url == "" or patch_path == "" or not FileAccess.file_exists(patch_path):
		return
	var reader: ZIPReader = ZIPReader.new()
	var err: Error = reader.open(patch_path)
	if err != OK:
		return
	var files: PackedStringArray = reader.get_files()
	if not "archipelago.json" in files:
		reader.close()
		return
		
	var arch_bytes: PackedByteArray = reader.read_file("archipelago.json")
	var parsed: Variant = JSON.parse_string(arch_bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		reader.close()
		return
		
	if str(parsed.get("server", "")) == clean_url:
		reader.close()
		return
		
	parsed["server"] = clean_url
	var updated_arch_bytes: PackedByteArray = JSON.stringify(parsed, "  ").to_utf8_buffer()
	
	var temp_dest: String = patch_path + ".tmp"
	var packer: ZIPPacker = ZIPPacker.new()
	if packer.open(temp_dest) != OK:
		reader.close()
		return
		
	for f in files:
		if f.ends_with("/"):
			continue
		packer.start_file(f)
		if f == "archipelago.json":
			packer.write_file(updated_arch_bytes)
		else:
			packer.write_file(reader.read_file(f))
		packer.close_file()
		
	reader.close()
	packer.close()
	
	DirAccess.copy_absolute(temp_dest, patch_path)
	DirAccess.remove_absolute(temp_dest)
	print("[ArchipelagoConfig] Injected server address '", clean_url, "' into patch: ", patch_path)

## Updates Archipelago _persistent_storage.yaml with the active server address
static func update_archipelago_persistent_storage(clean_url: String, tools_dir: String = USER_TOOLS_DIR) -> void:
	if clean_url == "":
		return
	var possible_paths: Array[String] = [
		tools_dir.path_join("Archipelago/_persistent_storage.yaml"),
		ProjectSettings.globalize_path(tools_dir).path_join("Archipelago/_persistent_storage.yaml")
	]
	if OS.get_name() == "Windows":
		var appdata: String = OS.get_environment("APPDATA")
		if appdata != "":
			possible_paths.append(appdata.path_join("Archipelago/_persistent_storage.yaml"))
			
	for p in possible_paths:
		var norm_p: String = ProjectSettings.globalize_path(p).replace("\\", "/")
		var dir_p: String = norm_p.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_p):
			continue
			
		var content: String = ""
		if FileAccess.file_exists(norm_p):
			var fa: FileAccess = FileAccess.open(norm_p, FileAccess.READ)
			if fa:
				content = fa.get_as_text()
				fa.close()
				
		if "client:" in content:
			var lines: PackedStringArray = content.split("\n")
			var new_lines: Array[String] = []
			var in_client: bool = false
			var updated_addr: bool = false
			for line in lines:
				var stripped: String = line.strip_edges()
				if stripped == "client:":
					in_client = true
					new_lines.append(line)
					continue
				if in_client and (stripped.begins_with("last_server_address:") or stripped.begins_with("server_address:")):
					new_lines.append("  last_server_address: " + clean_url)
					updated_addr = true
					continue
				if in_client and not line.begins_with(" ") and not line.begins_with("\t") and stripped != "":
					in_client = false
					if not updated_addr:
						new_lines.insert(new_lines.size() - 1, "  last_server_address: " + clean_url)
						updated_addr = true
				new_lines.append(line)
			if in_client and not updated_addr:
				new_lines.append("  last_server_address: " + clean_url)
			content = "\n".join(new_lines)
		else:
			content = "client:\n  last_server_address: " + clean_url + "\n" + content
			
		var out_fa: FileAccess = FileAccess.open(norm_p, FileAccess.WRITE)
		if out_fa:
			out_fa.store_string(content)
			out_fa.close()
			print("[ArchipelagoConfig] Updated Archipelago persistent storage with server address: ", clean_url)

## Returns destinations for Archipelago custom worlds
static func get_custom_world_destinations(tools_dir: String = USER_TOOLS_DIR) -> Array[String]:
	var dests: Array[String] = [
		tools_dir.path_join("Archipelago/custom_worlds")
	]
	if OS.get_name() == "Windows":
		var local_appdata: String = OS.get_environment("LOCALAPPDATA")
		if local_appdata != "":
			var local_dest: String = local_appdata.path_join("Archipelago/custom_worlds")
			if not dests.has(local_dest):
				dests.append(local_dest)
	elif OS.get_environment("HOME") != "":
		var home_dest: String = OS.get_environment("HOME").path_join("Archipelago/custom_worlds")
		if not dests.has(home_dest):
			dests.append(home_dest)
	return dests

## Updates an individual key in a YAML section cleanly
static func update_yaml_section_key(yaml_content: String, section_key: String, option_key: String, option_val: String, extra_lines: Array[String] = []) -> String:
	var section_header: String = section_key + ":"
	var is_bool: bool = (option_val == "true" or option_val == "false")
	var formatted_val: String = option_val if is_bool else "\"" + option_val + "\""
	if section_header in yaml_content:
		var lines: PackedStringArray = yaml_content.split("\n")
		var new_lines: Array[String] = []
		var in_section: bool = false
		var option_set: bool = false
		for line in lines:
			var stripped: String = line.strip_edges()
			if stripped.begins_with(section_header):
				in_section = true
				new_lines.append(line)
				continue
			if in_section and stripped.begins_with(option_key + ":"):
				new_lines.append("  " + option_key + ": " + formatted_val)
				option_set = true
				in_section = false
				continue
			if in_section and not line.begins_with(" ") and stripped != "":
				if not option_set:
					new_lines.append("  " + option_key + ": " + formatted_val)
					option_set = true
				in_section = false
			new_lines.append(line)
		if in_section and not option_set:
			new_lines.append("  " + option_key + ": " + formatted_val)
		return "\n".join(new_lines)
	else:
		var appended: String = yaml_content + "\n" + section_header + "\n  " + option_key + ": " + formatted_val + "\n"
		for extra in extra_lines:
			appended += "  " + extra + "\n"
		return appended

## Updates bizhawkclient_options block in host.yaml
static func update_yaml_bizhawk_block(yaml_content: String, absolute_bizhawk_path: String) -> String:
	yaml_content = update_yaml_section_key(yaml_content, "bizhawkclient_options", "emuhawk_path", absolute_bizhawk_path, ["rom_start: true"])
	yaml_content = update_yaml_section_key(yaml_content, "bizhawkclient_options", "rom_start", "true")
	return yaml_content
