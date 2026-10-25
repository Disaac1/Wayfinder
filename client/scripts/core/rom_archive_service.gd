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
