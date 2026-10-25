class_name PackageInstaller
extends RefCounted

var track_progress_callback: Callable
var progress_bar_callback: Callable

func _init(p_track_progress_callback: Callable, p_progress_bar_callback: Callable) -> void:
	track_progress_callback = p_track_progress_callback
	progress_bar_callback = p_progress_bar_callback

func _progress_bar(value: int) -> String:
	return str(progress_bar_callback.call(value))

func _set_progress(node: Node, text: String) -> void:
	if is_instance_valid(node) and "launch_instructions" in node and is_instance_valid(node.launch_instructions):
		node.launch_instructions.text = text

func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func install(
	node: Node,
	download_url: String,
	target_dir: String,
	display_name: String,
	callback: Callable,
	backup_files: Array = []
) -> void:
	DirAccess.make_dir_recursive_absolute(target_dir)

	var temp_filename: String = "user://temp_" + display_name.validate_filename() + ".zip"
	_cleanup(temp_filename)

	var http: HTTPRequest = HTTPRequest.new()
	http.use_threads = true
	http.download_chunk_size = 1048576
	http.download_file = temp_filename
	node.add_child(http)

	var is_downloading: Array = [true]
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		is_downloading[0] = false
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 0):
			_cleanup(temp_filename)
			callback.call(false, "Failed to download " + display_name + " (HTTP " + str(response_code) + ")")
			return

		_set_progress(node, "Installing " + display_name + "...\n\nExtracting files into game folder...\n" + _progress_bar(95))
		if is_instance_valid(node) and node.get_tree():
			await node.get_tree().process_frame

		var zip_reader: ZIPReader = ZIPReader.new()
		var open_error: Error = zip_reader.open(temp_filename)
		if open_error != OK:
			_cleanup(temp_filename)
			callback.call(false, "Failed to open ZIP archive for " + display_name)
			return

		_backup_files(target_dir, backup_files)
		var archive_files: PackedStringArray = zip_reader.get_files()
		var total_files: int = archive_files.size()
		var processed_files: int = 0
		for file_path_entry in archive_files:
			processed_files += 1
			var output_path: String = target_dir.path_join(file_path_entry)
			if file_path_entry.ends_with("/"):
				DirAccess.make_dir_recursive_absolute(output_path)
			else:
				DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
				var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
				if output_file:
					output_file.store_buffer(zip_reader.read_file(file_path_entry))
					output_file.close()

			if processed_files % 10 == 0 or processed_files == total_files:
				var extraction_pct: int = int((float(processed_files) / float(max(total_files, 1))) * 100.0)
				_set_progress(node, "Installing " + display_name + "...\n\nExtracting (" + str(processed_files) + " / " + str(total_files) + ")...\n" + _progress_bar(extraction_pct))
				if is_instance_valid(node) and node.get_tree():
					await node.get_tree().process_frame

		zip_reader.close()
		_cleanup(temp_filename)
		callback.call(true, target_dir)
	)

	track_progress_callback.call(node, http, display_name, is_downloading)
	var request_error: Error = http.request(download_url)
	if request_error != OK:
		is_downloading[0] = false
		http.queue_free()
		callback.call(false, "Failed to start HTTP request for " + display_name)

func _backup_files(target_dir: String, backup_files: Array) -> void:
	for backup_item in backup_files:
		var item_path: String = str(backup_item).strip_edges()
		if item_path == "":
			continue
		var original_path: String = target_dir.path_join(item_path)
		var backup_path: String = target_dir.path_join(item_path + ".vanilla.bak")
		if FileAccess.file_exists(original_path) and not FileAccess.file_exists(backup_path):
			DirAccess.copy_absolute(original_path, backup_path)
			print("[Launcher] Backed up vanilla ", item_path, " to: ", backup_path)
