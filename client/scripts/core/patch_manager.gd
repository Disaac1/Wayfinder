class_name PatchManager
extends RefCounted

var presets: Dictionary
var get_preset_callback: Callable
var saves_dir: String

func _init(p_presets: Dictionary, p_get_preset_callback: Callable, p_saves_dir: String) -> void:
	presets = p_presets
	get_preset_callback = p_get_preset_callback
	saves_dir = p_saves_dir

func is_matching_file(filename: String, patch_extension: String, game_name: String = "") -> bool:
	var filename_lower: String = filename.to_lower()
	var extension_lower: String = patch_extension.to_lower()
	if extension_lower != "" and filename_lower.ends_with(extension_lower):
		return true
	if game_name != "":
		var preset: Dictionary = get_preset_callback.call(game_name)
		var main_extension: String = str(preset.get("patch_extension", "")).to_lower()
		if main_extension != "" and filename_lower.ends_with(main_extension):
			return true
		for alias in preset.get("patch_extension_aliases", []):
			var alias_extension: String = str(alias).to_lower()
			if alias_extension != "" and filename_lower.ends_with(alias_extension):
				return true
		return false
	for preset_value in presets.values():
		var preset: Dictionary = preset_value
		var extensions: Array[String] = []
		var main_extension: String = str(preset.get("patch_extension", "")).to_lower()
		if main_extension != "":
			extensions.append(main_extension)
		for alias in preset.get("patch_extension_aliases", []):
			var alias_extension: String = str(alias).to_lower()
			if not extensions.has(alias_extension):
				extensions.append(alias_extension)
		for candidate in extensions:
			if extension_lower == candidate and filename_lower.ends_with(candidate):
				return true
	return false

func ensure(node: Node, active_game: String, patch_extension: String, callback: Callable) -> void:
	var download_dir: String = saves_dir.path_join(NetworkManager.room_code)
	DirAccess.make_dir_recursive_absolute(download_dir)
	var player_name: String = ""
	for player_info in NetworkManager.players:
		if player_info.get("userId") == NetworkManager.user_id:
			player_name = player_info.get("name", "")
			break
	var directory: DirAccess = DirAccess.open(download_dir)
	if directory:
		directory.list_dir_begin()
		var file_name: String = directory.get_next()
		while file_name != "":
			if is_matching_file(file_name, patch_extension, active_game) and (player_name == "" or file_name.to_lower().contains(player_name.to_lower())):
				callback.call(true, download_dir.path_join(file_name))
				return
			file_name = directory.get_next()

	var request: HTTPRequest = HTTPRequest.new()
	node.add_child(request)
	var request_url: String = NetworkManager.get_http_url() + "/api/seeds/" + NetworkManager.room_code + "/player-patch?playerName=" + player_name.uri_encode() + "&gameName=" + active_game.uri_encode() + "&patchExtension=" + patch_extension.uri_encode() + "&userId=" + NetworkManager.user_id.uri_encode()
	request.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		request.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 0):
			var filename: String = _filename_from_headers(headers, patch_extension, player_name)
			var output_path: String = download_dir.path_join(filename)
			var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
			if output:
				output.store_buffer(body)
				output.close()
				callback.call(true, output_path)
				return
		fallback(node, active_game, patch_extension, callback)
	)
	var request_error: Error = request.request(request_url)
	if request_error != OK:
		request.queue_free()
		fallback(node, active_game, patch_extension, callback)

func fallback(node: Node, active_game: String, patch_extension: String, callback: Callable) -> void:
	var download_dir: String = saves_dir.path_join(NetworkManager.room_code)
	DirAccess.make_dir_recursive_absolute(download_dir)
	var request: HTTPRequest = HTTPRequest.new()
	node.add_child(request)
	var temp_zip: String = download_dir.path_join("seed_temp.zip")
	request.download_file = temp_zip
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if FileAccess.file_exists(temp_zip):
				DirAccess.remove_absolute(temp_zip)
			callback.call(false, "Failed to download seed ZIP from server. Status: " + str(response_code))
			return
		var reader: ZIPReader = ZIPReader.new()
		if reader.open(temp_zip) != OK:
			DirAccess.remove_absolute(temp_zip)
			callback.call(false, "Failed to open downloaded seed ZIP.")
			return
		for entry in reader.get_files():
			var output: FileAccess = FileAccess.open(download_dir.path_join(entry), FileAccess.WRITE)
			if output:
				output.store_buffer(reader.read_file(entry))
				output.close()
		reader.close()
		DirAccess.remove_absolute(temp_zip)
		var directory: DirAccess = DirAccess.open(download_dir)
		if directory:
			directory.list_dir_begin()
			var file_name: String = directory.get_next()
			while file_name != "":
				if is_matching_file(file_name, patch_extension, active_game):
					callback.call(true, download_dir.path_join(file_name))
					return
				file_name = directory.get_next()
		callback.call(false, "Downloaded ZIP successfully but could not find a patch file matching " + patch_extension)
	)
	request.request(NetworkManager.get_http_url() + "/api/seeds/" + NetworkManager.room_code + "/outputs/" + NetworkManager.seed_zip_name.uri_encode())

func _filename_from_headers(headers: PackedStringArray, extension: String, player_name: String) -> String:
	for header in headers:
		if header.to_lower().begins_with("content-disposition:") and header.contains("filename="):
			var parts: PackedStringArray = header.split("filename=")
			if parts.size() > 1:
				return parts[1].replace("\"", "").replace("'", "").strip_edges()
	return "AP_" + NetworkManager.room_code + "_" + (player_name if player_name != "" else "Player") + extension
