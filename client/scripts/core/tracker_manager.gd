class_name TrackerManager
extends RefCounted

const POPTRACKER_TOOL_KEY: String = "poptracker"
const POPTRACKER_SUBFOLDER: String = "PopTracker"
const POPTRACKER_TARGET_EXE: String = "PopTracker.exe"
const POPTRACKER_PACKS_DIR: String = "user://tools/PopTracker/packs"
const POPTRACKER_DOWNLOAD_URL: String = "https://github.com/black-sliver/PopTracker/releases/download/v0.36.0/poptracker_0-36-0_win64.zip"
const POPTRACKER_SHA256: String = "18113909ac6008386b477b7bead6d9b8cf6809aa679667e6c0fd23efb63db127"

func get_tracker_config(preset: Dictionary) -> Dictionary:
	var tracker = preset.get("tracker", {})
	return tracker if tracker is Dictionary else {}

func is_supported(preset: Dictionary) -> bool:
	var tracker := get_tracker_config(preset)
	return bool(tracker.get("supported", false)) and str(tracker.get("pack_download_url", "")).strip_edges() != ""

func ensure_poptracker(
	node: Node,
	launcher_tools: Dictionary,
	launcher,
	callback: Callable
) -> void:
	var tool: Dictionary = _get_poptracker_tool(launcher_tools)
	if not tool is Dictionary or tool.is_empty():
		callback.call(false, "PopTracker is not configured by the launcher catalog.")
		return

	var download_url := str(tool.get("download_url", "")).strip_edges()
	var target_exe := str(tool.get("executable", POPTRACKER_TARGET_EXE)).strip_edges()
	if download_url == "" or target_exe == "":
		callback.call(false, "PopTracker tool metadata is incomplete.")
		return

	var subfolder := str(tool.get("subfolder", POPTRACKER_SUBFOLDER)).strip_edges()
	var expected_sha256 := str(tool.get("sha256", "")).strip_edges()
	var install_callback := func(ok: bool, value: String):
		callback.call(ok, value)
	launcher.ensure_tool_installed_or_download(
		node,
		str(tool.get("name", "PopTracker")),
		download_url,
		subfolder,
		target_exe,
		install_callback,
		"",
		-1,
		expected_sha256,
		true
	)

func _get_poptracker_tool(launcher_tools: Dictionary) -> Dictionary:
	var configured: Variant = launcher_tools.get(POPTRACKER_TOOL_KEY, {})
	if configured is Dictionary and not configured.is_empty():
		return configured
	for key in launcher_tools.keys():
		if str(key).to_lower() == POPTRACKER_TOOL_KEY:
			var case_insensitive_tool: Variant = launcher_tools.get(key)
			if case_insensitive_tool is Dictionary:
				return case_insensitive_tool
	return {
		"name": "PopTracker",
		"version": "0.36.0",
		"executable": POPTRACKER_TARGET_EXE,
		"subfolder": POPTRACKER_SUBFOLDER,
		"download_url": POPTRACKER_DOWNLOAD_URL,
		"sha256": POPTRACKER_SHA256
	}

func open_tracker(
	node: Node,
	preset: Dictionary,
	game_slug: String,
	launcher_tools: Dictionary,
	launcher,
	server_url: String,
	slot_name: String,
	callback: Callable
) -> void:
	var tracker := get_tracker_config(preset)
	if not is_supported(preset):
		callback.call(false, "No verified PopTracker pack is configured for this game.")
		return
	Updater.log_message("TRACKER", "Preparing PopTracker for " + game_slug + " (slot: " + slot_name + ")")

	ensure_poptracker(node, launcher_tools, launcher, func(tool_ok: bool, executable_path: String):
		if not tool_ok:
			callback.call(false, executable_path)
			return
		_install_pack(node, tracker, game_slug, launcher, func(pack_ok: bool, pack_path: String):
			if not pack_ok:
				callback.call(false, pack_path)
				return
			Updater.log_message("TRACKER", "Tracker pack ready at " + pack_path)
			var clean_server := server_url.replace("ws://", "").replace("wss://", "").trim_suffix("/")
			var package_uid := str(tracker.get("package_uid", "")).strip_edges()
			if package_uid == "":
				callback.call(false, "Tracker pack metadata is missing package_uid.")
				return
			var args: Array = [
				"--load-pack", package_uid,
				"--ap-host", clean_server,
				"--ap-slot", slot_name
			]
			var executable_global_path := ProjectSettings.globalize_path(executable_path)
			Updater.log_message("TRACKER", "Launching executable: " + executable_global_path)
			Updater.log_message("TRACKER", "Launching arguments: " + str(args))
			if not FileAccess.file_exists(executable_global_path):
				callback.call(false, "PopTracker executable was not found at " + executable_global_path)
				return
			if not FileAccess.file_exists(ProjectSettings.globalize_path(pack_path)):
				callback.call(false, "Tracker pack archive was not found at " + ProjectSettings.globalize_path(pack_path))
				return
			var process_id: int = launcher.launch_process_with_logging(node, executable_global_path, args, "PopTracker")
			if process_id <= 0:
				callback.call(false, "PopTracker was installed, but could not be started. Check the PopTracker process logs.")
				return
			Updater.log_message("TRACKER", "PopTracker started for " + game_slug + " (PID " + str(process_id) + ")")
			_verify_process_liveness(node, process_id, game_slug, callback)
		)
	)

func _install_pack(node: Node, tracker: Dictionary, game_slug: String, launcher, callback: Callable) -> void:
	var download_url := str(tracker.get("pack_download_url", "")).strip_edges()
	var expected_sha256 := str(tracker.get("pack_sha256", "")).strip_edges().to_lower()
	var pack_name := str(tracker.get("pack_name", game_slug)).strip_edges()
	var temp_path := "user://tools/temp_" + game_slug.validate_filename() + "_tracker.zip"
	var pack_path := get_pack_path(game_slug)
	if FileAccess.file_exists(pack_path):
		var validation := validate_pack_archive(pack_path, expected_sha256)
		if validation.get("valid", false):
			Updater.log_message("TRACKER", "Using cached " + pack_name + " tracker pack at " + pack_path)
			callback.call(true, pack_path)
			return
		Updater.log_message("TRACKER", "Cached " + pack_name + " tracker pack failed validation; downloading the current pack")
	Updater.log_message("TRACKER", "Downloading " + pack_name + " tracker pack from " + download_url)

	var http := HTTPRequest.new()
	http.use_threads = true
	http.download_file = temp_path
	node.add_child(http)
	var is_downloading: Array = [true]
	if launcher and launcher.has_method("track_http_download_progress"):
		launcher.track_http_download_progress(node, http, pack_name + " Tracker Pack", is_downloading)

	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		is_downloading[0] = false
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 0):
			_cleanup(temp_path)
			callback.call(false, "Failed to download " + pack_name + " tracker pack (HTTP " + str(response_code) + ").")
			return
		Updater.log_message("TRACKER", "Downloaded " + pack_name + " tracker pack; validating checksum")
		if is_instance_valid(node) and "launch_instructions" in node and is_instance_valid(node.launch_instructions):
			node.launch_instructions.text = "Validating checksum for " + pack_name + "..."
		var validation := validate_pack_archive(temp_path, expected_sha256)
		if not validation.get("valid", false):
			_cleanup(temp_path)
			callback.call(false, str(validation.get("error", "Tracker pack validation failed.")))
			return
		_cleanup(pack_path)
		var replace_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(pack_path)
		)
		if replace_error != OK:
			_cleanup(temp_path)
			callback.call(false, "Could not cache " + pack_name + " tracker pack at " + pack_path + " (Error: " + str(replace_error) + ").")
			return
		callback.call(true, pack_path)
	)
	var request_error := http.request(download_url)
	if request_error != OK:
		is_downloading[0] = false
		http.queue_free()
		callback.call(false, "Failed to start tracker pack download: " + str(request_error))

func _verify_process_liveness(node: Node, process_id: int, game_slug: String, callback: Callable) -> void:
	if not is_instance_valid(node) or not node.get_tree():
		callback.call(true, str(process_id))
		return
	await node.get_tree().create_timer(1.0).timeout
	if OS.is_process_running(process_id):
		Updater.log_message("TRACKER", "PopTracker process is still running (PID " + str(process_id) + ")")
		callback.call(true, str(process_id))
		return
	Updater.log_message("ERROR", "PopTracker exited immediately after launch for " + game_slug + " (PID " + str(process_id) + "). Check [PopTracker Output] and [PopTracker Error Log] entries above.")
	callback.call(false, "PopTracker exited immediately after launch. Check the process output logs for the startup error.")

func _extract_pack(archive_path: String, target_dir: String, pack_name: String) -> Dictionary:
	var archive := ZIPReader.new()
	var open_error := archive.open(archive_path)
	if open_error != OK:
		return {"valid": false, "error": "Failed to open " + pack_name + " tracker pack."}
	var files := archive.get_files()
	var root_prefix := _get_common_root(files)
	var extracted_manifest := ""
	for archive_path_entry in files:
		var relative_path := archive_path_entry.replace("\\", "/")
		if root_prefix != "" and relative_path.begins_with(root_prefix):
			relative_path = relative_path.substr(root_prefix.length())
		if relative_path == "":
			continue
		if relative_path.begins_with("/") or relative_path.begins_with("../") or relative_path.contains("/../"):
			archive.close()
			return {"valid": false, "error": "Tracker pack contains an unsafe archive path."}
		var output_path := target_dir.path_join(relative_path)
		if archive_path_entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(output_path)
		else:
			DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
			var output_file := FileAccess.open(output_path, FileAccess.WRITE)
			if not output_file:
				archive.close()
				return {"valid": false, "error": "Could not write tracker pack file: " + relative_path}
			output_file.store_buffer(archive.read_file(archive_path_entry))
			output_file.close()
			if relative_path.get_file().to_lower() == "manifest.json":
				extracted_manifest = output_path
	archive.close()
	if extracted_manifest == "":
		return {"valid": false, "error": "Tracker pack does not contain manifest.json."}
	return {"valid": true, "path": target_dir}

func _get_common_root(files: PackedStringArray) -> String:
	var root := ""
	for file_path_entry in files:
		var slash_index := file_path_entry.find("/")
		if slash_index <= 0:
			return ""
		var candidate := file_path_entry.substr(0, slash_index + 1)
		if root == "":
			root = candidate
		elif root != candidate:
			return ""
	return root

func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func get_pack_path(game_slug: String) -> String:
	var directory := POPTRACKER_PACKS_DIR
	DirAccess.make_dir_recursive_absolute(directory)
	return directory.path_join(game_slug.validate_filename() + ".zip")

func get_pack_download_url(preset: Dictionary) -> String:
	return str(get_tracker_config(preset).get("pack_download_url", "")).strip_edges()

func get_pack_checksum(preset: Dictionary) -> String:
	return str(get_tracker_config(preset).get("pack_sha256", "")).strip_edges().to_lower()

func validate_pack_archive(file_path: String, expected_sha256: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"valid": false, "error": "Tracker pack archive was not downloaded."}

	var actual_sha256 := FileAccess.get_sha256(file_path).to_lower()
	if expected_sha256 != "" and actual_sha256 != expected_sha256.to_lower():
		return {
			"valid": false,
			"error": "Tracker pack checksum mismatch. Expected " + expected_sha256 + ", got " + actual_sha256 + "."
		}

	var archive := ZIPReader.new()
	var open_error := archive.open(file_path)
	if open_error != OK:
		return {"valid": false, "error": "Tracker pack is not a readable ZIP archive."}
	var files := archive.get_files()
	var has_manifest := false
	for file_path_entry in files:
		if file_path_entry.get_file().to_lower() == "manifest.json":
			has_manifest = true
			break
	archive.close()
	if not has_manifest:
		return {"valid": false, "error": "Tracker pack does not contain manifest.json."}
	return {"valid": true, "sha256": actual_sha256}
