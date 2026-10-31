class_name RomArchiveService
extends RefCounted

var game_slug_callback: Callable
var game_dir_callback: Callable
var supported_extensions_callback: Callable

func _init(p_game_slug_callback: Callable, p_game_dir_callback: Callable, p_supported_extensions_callback: Callable) -> void:
	game_slug_callback = p_game_slug_callback
	game_dir_callback = p_game_dir_callback
	supported_extensions_callback = p_supported_extensions_callback

func unpack(zip_file_path: String, rom_name: String, callback: Callable) -> void:
	var zip_reader: ZIPReader = ZIPReader.new()
	var open_error: Error = zip_reader.open(zip_file_path)
	if open_error != OK:
		callback.call(false, "Failed to open ROM zip archive: " + zip_file_path)
		return
	var archive_files: PackedStringArray = zip_reader.get_files()
	var game_slug: String = str(game_slug_callback.call(rom_name))
	var destination_dir: String = str(game_dir_callback.call(game_slug))
	DirAccess.make_dir_recursive_absolute(destination_dir)
	var target_path: String = destination_dir.path_join(rom_name)
	var extracted_target: bool = false
	for archive_path in archive_files:
		if archive_path.ends_with("/"):
			continue
		var data: PackedByteArray = zip_reader.read_file(archive_path)
		if data.is_empty():
			continue
		var output_name: String = archive_path.get_file()
		var output_path: String = destination_dir.path_join(output_name)
		var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if output:
			output.store_buffer(data)
			output.close()
		if output_name == rom_name:
			extracted_target = true
	if not extracted_target:
		var target_extension: String = rom_name.get_extension().to_lower()
		var supported_extensions: Array[String] = supported_extensions_callback.call()
		var selected_data: PackedByteArray
		var selected_name: String = ""
		for archive_path in archive_files:
			var extension: String = archive_path.get_extension().to_lower()
			if (target_extension != "" and extension == target_extension) or (target_extension == "" and supported_extensions.has(extension)):
				selected_data = zip_reader.read_file(archive_path)
				selected_name = archive_path
				break
		if selected_data.is_empty():
			for archive_path in archive_files:
				if supported_extensions.has(archive_path.get_extension().to_lower()):
					selected_data = zip_reader.read_file(archive_path)
					selected_name = archive_path
					break
		if selected_data.is_empty():
			for archive_path in archive_files:
				if not archive_path.ends_with("/"):
					selected_data = zip_reader.read_file(archive_path)
					selected_name = archive_path
					break
		if not selected_data.is_empty():
			var output: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
			if output:
				output.store_buffer(selected_data)
				output.close()
				extracted_target = true
				print("[Launcher] Extracted base ROM (", selected_data.size(), " bytes) from ", selected_name, " to: ", target_path)
	zip_reader.close()
	if zip_file_path != target_path and FileAccess.file_exists(zip_file_path):
		DirAccess.remove_absolute(zip_file_path)
	if extracted_target or FileAccess.file_exists(target_path):
		callback.call(true, target_path)
	else:
		callback.call(false, "No valid ROM file found inside downloaded ZIP archive.")

var find_exec_callback: Callable

func set_find_executable_callback(p_find_exec_callback: Callable) -> void:
	find_exec_callback = p_find_exec_callback

func find_dolphin_tool_path(dolphin_exe_path: String) -> String:
	if dolphin_exe_path != "":
		var dolphin_dir: String = dolphin_exe_path.get_base_dir()
		var tool_candidate: String = dolphin_dir.path_join("DolphinTool.exe")
		if FileAccess.file_exists(tool_candidate):
			return tool_candidate
			
	if find_exec_callback.is_valid():
		var discovered: String = str(find_exec_callback.call("DolphinTool.exe", ["Dolphin", "Dolphin-x64", "dolphin-master"], [], true))
		if discovered != "" and FileAccess.file_exists(discovered):
			return discovered
	return ""

func convert_rvz_to_iso(rvz_path: String, output_iso_path: String, dolphin_tool_path: String, delete_source: bool = false) -> Dictionary:
	if dolphin_tool_path == "" or not FileAccess.file_exists(dolphin_tool_path):
		return {"success": false, "error": "DolphinTool.exe not found for RVZ conversion."}
	if not FileAccess.file_exists(rvz_path):
		return {"success": false, "error": "Input RVZ file not found: " + rvz_path}
		
	var abs_rvz: String = ProjectSettings.globalize_path(rvz_path)
	var abs_iso: String = ProjectSettings.globalize_path(output_iso_path)
	
	DirAccess.make_dir_recursive_absolute(output_iso_path.get_base_dir())
	print("[RomArchiveService] Converting RVZ to uncompressed ISO via DolphinTool...")
	print("[RomArchiveService] Command: ", dolphin_tool_path, " convert -i ", abs_rvz, " -o ", abs_iso, " -f iso")
	
	var args: Array = ["convert", "-i", abs_rvz, "-o", abs_iso, "-f", "iso"]
	var pipe_data: Dictionary = OS.execute_with_pipe(dolphin_tool_path, args)
	if not pipe_data.has("pid") or pipe_data["pid"] <= 0:
		var output: Array = []
		var exit_code: int = OS.execute(dolphin_tool_path, args, output, true)
		if exit_code != 0:
			var err_msg: String = " ".join(output)
			return {"success": false, "error": "DolphinTool conversion failed: " + err_msg}
	else:
		var pid: int = pipe_data["pid"]
		while OS.is_process_running(pid):
			OS.delay_msec(100)
		var stdout_pipe: FileAccess = pipe_data.get("stdout")
		if stdout_pipe and stdout_pipe.is_open():
			stdout_pipe.close()
		var stderr_pipe: FileAccess = pipe_data.get("stderr")
		if stderr_pipe and stderr_pipe.is_open():
			stderr_pipe.close()
		
	if not FileAccess.file_exists(output_iso_path):
		return {"success": false, "error": "DolphinTool finished with 0 but ISO was not generated."}
		
	print("[RomArchiveService] RVZ converted to ISO successfully: ", output_iso_path)
	if delete_source:
		var global_user_dir: String = ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
		var global_rvz: String = ProjectSettings.globalize_path(rvz_path).replace("\\", "/")
		if rvz_path.begins_with("user://") or global_rvz.begins_with(global_user_dir):
			DirAccess.remove_absolute(rvz_path)
			print("[RomArchiveService] Deleted source RVZ after successful conversion: ", rvz_path)
	return {"success": true, "path": output_iso_path}
