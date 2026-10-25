class_name ExecutableLocator
extends RefCounted

const LauncherUtils = preload("res://scripts/core/launcher_utils.gd")

var games_dir: String
var tools_dir: String

func _init(p_games_dir: String, p_tools_dir: String) -> void:
	games_dir = p_games_dir
	tools_dir = p_tools_dir

func find_recursive(dir_path: String, executable_name: String, current_depth: int = 0, max_depth: int = 4) -> String:
	return LauncherUtils.find_executable_recursive(dir_path, executable_name, current_depth, max_depth)

func find(executable_name: String, sub_folders: Array, executable_aliases: Array = [], allow_deep_search: bool = true) -> String:
	return LauncherUtils.find_game_executable(
		executable_name,
		sub_folders,
		executable_aliases,
		games_dir,
		tools_dir,
		allow_deep_search
	)

func find_in_directory(search_dir: String, executable_name: String, aliases: Array) -> String:
	var directory: DirAccess = DirAccess.open(search_dir)
	if not directory:
		return ""
	directory.list_dir_begin()
	var item: String = directory.get_next()
	var subdirectories: Array[String] = []
	while item != "":
		if not item.begins_with("."):
			var full_path: String = search_dir.path_join(item)
			if directory.current_is_dir():
				subdirectories.append(full_path)
			elif _matches(item, executable_name, aliases):
				return full_path
		item = directory.get_next()
	directory.list_dir_end()

	for subdirectory in subdirectories:
		var found_path: String = find_in_directory(subdirectory, executable_name, aliases)
		if found_path != "":
			return found_path
	return ""

func _matches(file_name: String, executable_name: String, aliases: Array) -> bool:
	if executable_name != "" and file_name.nocasecmp_to(executable_name) == 0:
		return true
	for alias in aliases:
		if file_name.nocasecmp_to(str(alias)) == 0:
			return true
	return false
