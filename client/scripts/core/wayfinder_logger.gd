extends Node

const LOG_DIR: String = "user://logs"
const LOG_FILE: String = "user://logs/wayfinder.log"
const MAX_LOG_SIZE: int = 2 * 1024 * 1024  # 2 MB before rotation
const MAX_ROTATED_FILES: int = 3
const MAX_BUFFER_LINES: int = 500

var _log_file: FileAccess = null
var _log_buffer: PackedStringArray = PackedStringArray()
var _last_error: String = ""

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_rotate_if_needed()
	if not FileAccess.file_exists(LOG_FILE):
		_log_file = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	else:
		_log_file = FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
		if _log_file:
			_log_file.seek_end()
	_write_header()

func _rotate_if_needed() -> void:
	if not FileAccess.file_exists(LOG_FILE):
		return
	var fa: FileAccess = FileAccess.open(LOG_FILE, FileAccess.READ)
	if fa:
		var current_size: int = fa.get_length()
		fa.close()
		if current_size > MAX_LOG_SIZE:
			for i in range(MAX_ROTATED_FILES, 1, -1):
				var old_path: String = LOG_FILE + "." + str(i - 1)
				var new_path: String = LOG_FILE + "." + str(i)
				if FileAccess.file_exists(old_path):
					DirAccess.rename_absolute(old_path, new_path)
			DirAccess.rename_absolute(LOG_FILE, LOG_FILE + ".1")

func _write_header() -> void:
	var header: String = "\n=========================================\n"
	header += "Wayfinder Client Session Started\n"
	header += "Timestamp: " + Time.get_datetime_string_from_system() + "\n"
	header += "OS: " + OS.get_name() + " (" + OS.get_distribution_name() + ")\n"
	header += "Godot Engine: " + Engine.get_version_info().string + "\n"
	header += "App Version: " + str(ProjectSettings.get_setting("application/config/version", "1.0.0")) + "\n"
	header += "UserData Path: " + ProjectSettings.globalize_path("user://") + "\n"
	header += "========================================="
	log_message("SYSTEM", header)

func log_message(source: String, message: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system()
	var clean_msg: String = message.strip_edges()
	var entry: String = "[" + timestamp + "] [" + source + "] " + clean_msg
	
	_log_buffer.append(entry)
	if _log_buffer.size() > MAX_BUFFER_LINES:
		_log_buffer = _log_buffer.slice(_log_buffer.size() - MAX_BUFFER_LINES)
		
	if source == "ERROR":
		_last_error = clean_msg
		
	if _log_file and _log_file.is_open():
		_log_file.store_line(entry)
		_log_file.flush()

func get_recent_logs(line_count: int = 100) -> String:
	var count: int = mini(line_count, _log_buffer.size())
	var start_idx: int = maxi(0, _log_buffer.size() - count)
	var slice: PackedStringArray = _log_buffer.slice(start_idx)
	return "\n".join(slice)

func get_last_error() -> String:
	return _last_error

func get_log_file_absolute_path() -> String:
	return ProjectSettings.globalize_path(LOG_FILE)

func generate_diagnostic_report(custom_context: Dictionary = {}) -> String:
	var report: String = "=========================================\n"
	report += "       WAYFINDER DIAGNOSTIC REPORT       \n"
	report += "=========================================\n"
	report += "Generated: " + Time.get_datetime_string_from_system() + "\n"
	report += "Platform:  " + OS.get_name() + " (" + OS.get_distribution_name() + ")\n"
	report += "Engine:    " + Engine.get_version_info().string + "\n"
	report += "User Data: " + ProjectSettings.globalize_path("user://") + "\n\n"
	
	if not custom_context.is_empty():
		report += "--- Context ---\n"
		for k in custom_context.keys():
			report += str(k) + ": " + str(custom_context[k]) + "\n"
		report += "\n"
		
	report += "--- Installed Tools (user://tools) ---\n"
	if DirAccess.dir_exists_absolute("user://tools"):
		var dir: DirAccess = DirAccess.open("user://tools")
		if dir:
			dir.list_dir_begin()
			var item: String = dir.get_next()
			var found_any: bool = false
			while item != "":
				if dir.current_is_dir() and item != "." and item != "..":
					found_any = true
					report += "  📁 " + item + "/\n"
					# List top-level files in subfolder
					var sub_dir: DirAccess = DirAccess.open("user://tools".path_join(item))
					if sub_dir:
						sub_dir.list_dir_begin()
						var sub_item: String = sub_dir.get_next()
						var sub_count: int = 0
						while sub_item != "" and sub_count < 10:
							if not sub_dir.current_is_dir():
								report += "      • " + sub_item + "\n"
								sub_count += 1
							sub_item = sub_dir.get_next()
				item = dir.get_next()
			if not found_any:
				report += "  (tools directory is empty)\n"
	else:
		report += "  (user://tools directory does not exist)\n"
		
	report += "\n--- Paths Configuration ---\n"
	if FileAccess.file_exists("user://paths_config.json"):
		var fa: FileAccess = FileAccess.open("user://paths_config.json", FileAccess.READ)
		if fa:
			report += fa.get_as_text() + "\n"
			fa.close()
	else:
		report += "  (no paths_config.json found)\n"
		
	report += "\n--- Recent Log Buffer (last 80 entries) ---\n"
	report += get_recent_logs(80) + "\n"
	report += "=========================================\n"
	return report

func send_logs_to_server(http_node: Node, server_base_url: String, error_summary: String = "", callback: Callable = Callable()) -> void:
	if not is_instance_valid(http_node):
		if callback.is_valid():
			callback.call(false, "Invalid node context")
		return
		
	var target_url: String = server_base_url.trim_suffix("/") + "/api/client/logs"
	var http: HTTPRequest = HTTPRequest.new()
	http.use_threads = true
	http_node.add_child(http)
	
	var payload: Dictionary = {
		"source": "client_error_report",
		"error": error_summary if error_summary != "" else _last_error,
		"platform": OS.get_name(),
		"recent_logs": get_recent_logs(120),
		"diagnostic_summary": generate_diagnostic_report({"reported_error": error_summary})
	}
	
	var json_str: String = JSON.stringify(payload)
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		var success: bool = (result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 201))
		var msg: String = "Logs sent successfully to server." if success else ("Failed to send logs: HTTP " + str(response_code))
		log_message("SYSTEM", msg)
		if callback.is_valid():
			callback.call(success, msg)
	)
	
	var err: Error = http.request(target_url, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		http.queue_free()
		log_message("ERROR", "Failed to dispatch HTTP request for log upload: " + str(err))
		if callback.is_valid():
			callback.call(false, "HTTP request dispatch error: " + str(err))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _log_file and _log_file.is_open():
			log_message("SYSTEM", "Wayfinder Client Session Ended")
			_log_file.close()
