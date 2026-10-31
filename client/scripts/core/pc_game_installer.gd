class_name PcGameInstaller
extends RefCounted

var resolve_url_callback: Callable
var decrypt_callback: Callable
var set_overlay_callback: Callable
var track_progress_callback: Callable
var update_progress_callback: Callable

func _init(
	p_resolve_url_callback: Callable,
	p_decrypt_callback: Callable,
	p_set_overlay_callback: Callable,
	p_track_progress_callback: Callable,
	p_update_progress_callback: Callable = Callable()
) -> void:
	resolve_url_callback = p_resolve_url_callback
	decrypt_callback = p_decrypt_callback
	set_overlay_callback = p_set_overlay_callback
	track_progress_callback = p_track_progress_callback
	update_progress_callback = p_update_progress_callback

func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func install(
	node: Node,
	download_url: String,
	extract_dir: String,
	game_name: String,
	decryption_key: String,
	callback: Callable,
	redirect_depth: int = 0
) -> void:
	if redirect_depth > 5:
		callback.call(false, "Exceeded maximum HTTP redirect depth (5).")
		return

	var resolved_url: String = str(resolve_url_callback.call(download_url))
	set_overlay_callback.call(node)
	DirAccess.make_dir_recursive_absolute(extract_dir)

	var encrypted: bool = resolved_url.to_lower().contains(".enc") or decryption_key != ""
	var temp_download_path: String = extract_dir.path_join("temp_game_download" + (".enc" if encrypted else ".zip"))
	var http_request: HTTPRequest = HTTPRequest.new()
	http_request.use_threads = true
	http_request.download_chunk_size = 1048576
	http_request.download_file = temp_download_path
	node.add_child(http_request)

	var is_downloading: Array = [true]
	http_request.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, _body: PackedByteArray):
		is_downloading[0] = false
		http_request.queue_free()

		if response_code in [301, 302, 303, 307, 308]:
			var redirect_location: String = _get_redirect_location(headers)
			if redirect_location != "":
				print("[Launcher] Following HTTP redirect (", response_code, ") to: ", redirect_location)
				_cleanup(temp_download_path)
				install(node, redirect_location, extract_dir, game_name, decryption_key, callback, redirect_depth + 1)
				return

		if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 0):
			_cleanup(temp_download_path)
			callback.call(false, "Failed to download game archive. Response code: " + str(response_code))
			return

		var working_zip: String = temp_download_path
		if decryption_key != "" or working_zip.ends_with(".enc"):
			var decrypted_path: String = extract_dir.path_join("decrypted_game.zip")
			var dec_cb: Callable = func(pct: int, done_bytes: int, total_bytes: int):
				_update_decrypt_progress(node, game_name, pct, done_bytes, total_bytes)
			_update_decrypt_progress(node, game_name, 0, 0, 1)
			var decrypted_ok: bool = bool(decrypt_callback.call(working_zip, decrypted_path, decryption_key, dec_cb))
			_cleanup(working_zip)
			if not decrypted_ok:
				callback.call(false, "Failed to decrypt game archive.")
				return
			working_zip = decrypted_path

		var zip_reader: ZIPReader = ZIPReader.new()
		var open_error: Error = zip_reader.open(working_zip)
		if open_error != OK:
			_cleanup(working_zip)
			callback.call(false, "Downloaded file is not a valid ZIP archive (Error: " + str(open_error) + ").")
			return

		for archive_path in zip_reader.get_files():
			if archive_path.ends_with("/"):
				DirAccess.make_dir_recursive_absolute(extract_dir.path_join(archive_path))
				continue
			var output_path: String = extract_dir.path_join(archive_path)
			DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
			var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
			if output_file:
				output_file.store_buffer(zip_reader.read_file(archive_path))
				output_file.close()

		zip_reader.close()
		_cleanup(working_zip)
		print("[Launcher] Successfully unpacked game files for ", game_name, " to: ", extract_dir)
		callback.call(true, "Unpacked successfully")
	)

	track_progress_callback.call(node, http_request, game_name + " Game Files", is_downloading)
	var request_error: Error = http_request.request(resolved_url)
	if request_error != OK:
		is_downloading[0] = false
		http_request.queue_free()
		callback.call(false, "Failed to start game download HTTP request.")

func _get_redirect_location(headers: PackedStringArray) -> String:
	for header in headers:
		if header.to_lower().begins_with("location:"):
			return header.substr(9).strip_edges()
	return ""

func _update_decrypt_progress(node: Node, game_name: String, pct: int, done_bytes: int, total_bytes: int) -> void:
	if update_progress_callback.is_valid():
		update_progress_callback.call(node, "Decrypting " + game_name, pct, done_bytes, total_bytes, 0.0)