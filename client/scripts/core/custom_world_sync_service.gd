class_name CustomWorldSyncService
extends RefCounted

const USER_TOOLS_DIR: String = "user://tools"

var get_destinations_callback: Callable

func _init(p_get_destinations_callback: Callable = Callable()) -> void:
	get_destinations_callback = p_get_destinations_callback

func sync_to_archipelago() -> void:
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

	var dest_dirs: Array[String] = []
	if get_destinations_callback.is_valid():
		var res = get_destinations_callback.call()
		if res is Array:
			for d in res:
				dest_dirs.append(str(d))

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
					print("[CustomWorldSyncService] Synced custom world: ", fn, " to: ", dst_path)
				else:
					print("[CustomWorldSyncService Warning] Failed to copy custom world: ", fn, " to: ", dst_path, " (Error: ", copy_err, ")")

func sync_from_server(node: Node, target_games: Array = [], callback: Callable = Callable()) -> void:
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
			print("[CustomWorldSyncService] Failed to list custom worlds from backend. Result: ", result, ", HTTP status: ", response_code)
			sync_to_archipelago()
			if callback.is_valid():
				callback.call(false)
			return
			
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if not (parsed is Dictionary) or not parsed.has("worlds"):
			print("[CustomWorldSyncService] Backend returned an invalid custom worlds list.")
			sync_to_archipelago()
			if callback.is_valid():
				callback.call(false)
			return
			
		var worlds: Array = parsed.get("worlds", [])
		if not target_games.is_empty():
			var filtered: Array = []
			var targets: Array[String] = []
			for tg in target_games:
				var n: String = str(tg).to_lower().replace(" ", "").replace("_", "").replace("-", "").replace(":", "")
				if n != "" and not targets.has(n):
					targets.append(n)
			for w in worlds:
				var w_game: String = str(w.get("game", "")).to_lower().replace(" ", "").replace("_", "").replace("-", "").replace(":", "")
				var w_fn: String = str(w.get("filename", "")).to_lower().replace(".apworld", "").replace("_", "").replace("-", "")
				var is_match: bool = false
				for t in targets:
					if (w_game != "" and (t in w_game or w_game in t)) or (w_fn != "" and (t in w_fn or w_fn in t)):
						is_match = true
						break
				if is_match:
					filtered.append(w)
			worlds = filtered
		_download_next_custom_world(node, worlds, 0, callback)
	)
	
	var list_url: String = NetworkManager.get_http_url() + "/api/custom-worlds"
	var err: Error = http.request(list_url)
	if err != OK:
		print("[CustomWorldSyncService] Failed to start custom worlds list request. Error: ", err)
		http.queue_free()
		sync_to_archipelago()
		if callback.is_valid():
			callback.call(false)

func _download_next_custom_world(node: Node, worlds: Array, index: int, finish_cb: Callable) -> void:
	if index >= worlds.size():
		sync_to_archipelago()
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
			print("[CustomWorldSyncService] Downloaded updated custom world from server: ", fn)
		else:
			print("[CustomWorldSyncService] Failed to download custom world '", fn, "'. Result: ", result, ", HTTP status: ", response_code)
		_download_next_custom_world(node, worlds, index + 1, finish_cb)
	)
	var dl_url: String = NetworkManager.get_http_url() + "/api/custom-worlds/" + fn.uri_encode()
	var err: Error = http.request(dl_url)
	if err != OK:
		print("[CustomWorldSyncService] Failed to start custom world download for '", fn, "'. Error: ", err)
		http.queue_free()
		_download_next_custom_world(node, worlds, index + 1, finish_cb)

