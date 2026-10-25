class_name ConfigWriterService
extends RefCounted

var interpolate_callback: Callable
var merge_json_callback: Callable

func _init(p_interpolate_callback: Callable, p_merge_json_callback: Callable) -> void:
	interpolate_callback = p_interpolate_callback
	merge_json_callback = p_merge_json_callback

func apply(preset_config: Dictionary, context: Dictionary) -> bool:
	if not preset_config.has("config_writer") or not (preset_config["config_writer"] is Dictionary):
		return true
	var writer_config: Dictionary = preset_config["config_writer"]
	var file_template: String = str(writer_config.get("file_path", ""))
	if file_template == "":
		return false
	var target_path: String = str(interpolate_callback.call(file_template, context))
	DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())
	var backup_path: String = target_path + ".wayfinder.bak"
	if FileAccess.file_exists(target_path) and not FileAccess.file_exists(backup_path):
		DirAccess.copy_absolute(target_path, backup_path)
		print("[Launcher] Created config backup at: ", backup_path)

	var content: String
	if writer_config.get("format", "template") == "json":
		var json_object: Dictionary = {}
		if FileAccess.file_exists(target_path):
			var existing_file: FileAccess = FileAccess.open(target_path, FileAccess.READ)
			if existing_file:
				var parsed = JSON.parse_string(existing_file.get_as_text())
				if parsed is Dictionary:
					json_object = parsed
				existing_file.close()
		json_object = merge_json_callback.call(json_object, writer_config.get("json_template", {}), context)
		content = JSON.stringify(json_object, "  ")
	else:
		content = str(interpolate_callback.call(str(writer_config.get("template", "")), context))

	var output_file: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if not output_file:
		print("[Launcher Error] Failed to write config file to: ", target_path)
		return false
	output_file.store_string(content)
	output_file.close()
	print("[Launcher] Wrote dynamic mod configuration to: ", target_path)
	return true
