class_name YamlBuilder
extends RefCounted

# --- CONSTANTS ---
const DEFAULT_OPTION_INDENT: int = 4
const SUB_OPTION_INDENT_STEP: int = 2

const YAML_EMPTY_DICT: String = "{}"
const YAML_EMPTY_ARRAY: String = "[]"
const YAML_NULL_VALUE: String = "null"
const YAML_TRUE_VALUE: String = "true"
const YAML_FALSE_VALUE: String = "false"

const YAML_SPECIAL_CHARACTERS: Array[String] = [":", "{", "}", "[", "]", "#", "-", "?"]


# =====================================================================
#                     YAML COMPILATION PIPELINE
# =====================================================================

static func compile_yaml(selected_games: Array, active_config_game: String, player_name: String, _room_code: String, config_states: Dictionary) -> String:
	if selected_games.is_empty():
		return ""
		
	var active_game_title: String = _determine_primary_active_game(selected_games, active_config_game)
	var yaml_output_string: String = _build_yaml_header(player_name, active_game_title)
	
	for game_title in selected_games:
		var game_options: Dictionary = config_states.get(game_title, {})
		yaml_output_string += _build_game_options_block(game_title, game_options)
				
	return yaml_output_string

static func _determine_primary_active_game(selected_games: Array, active_config_game: String) -> String:
	if selected_games.is_empty():
		return ""
	if active_config_game != "" and active_config_game in selected_games:
		return active_config_game
	return str(selected_games[0])

static func _build_yaml_header(player_name: String, active_game_title: String) -> String:
	var header_lines: String = ""
	header_lines += "description: Compiled options for " + player_name + " via Wayfinder\n"
	header_lines += "name: " + player_name + "\n"
	header_lines += "game: " + active_game_title + "\n"
	return header_lines

static func _build_game_options_block(game_title: String, game_options: Dictionary) -> String:
	var block_output: String = game_title + ":\n"
	if game_options.is_empty():
		block_output += "  " + YAML_EMPTY_DICT + "\n"
		return block_output
		
	for option_name in game_options.keys():
		var raw_option_value: Variant = game_options[option_name]
		block_output += "  " + str(option_name) + ": " + format_yaml_value(raw_option_value, DEFAULT_OPTION_INDENT) + "\n"
		
	return block_output


# =====================================================================
#                     YAML VALUE FORMATTING HELPERS
# =====================================================================

static func format_yaml_value(raw_value: Variant, indent_level: int) -> String:
	if raw_value == null:
		return YAML_NULL_VALUE
		
	var value_type: int = typeof(raw_value)
	match value_type:
		TYPE_BOOL:
			return YAML_TRUE_VALUE if raw_value else YAML_FALSE_VALUE
			
		TYPE_INT, TYPE_FLOAT:
			if value_type == TYPE_FLOAT and raw_value == float(int(raw_value)):
				return str(int(raw_value))
			return str(raw_value)
			
		TYPE_STRING:
			return _format_string_value(str(raw_value))
			
		TYPE_ARRAY:
			return _format_array_value(raw_value, indent_level)
			
		TYPE_DICTIONARY:
			return _format_dictionary_value(raw_value, indent_level)
			
		_:
			return str(raw_value)

static func _format_string_value(text_value: String) -> String:
	if text_value == "":
		return "\"\""
		
	var requires_quotes: bool = false
	for special_char in YAML_SPECIAL_CHARACTERS:
		if special_char in text_value:
			requires_quotes = true
			break
			
	if not requires_quotes and (text_value.begins_with("-") or text_value.begins_with("?")):
		requires_quotes = true
		
	if requires_quotes:
		return "\"" + text_value.replace("\"", "\\\"") + "\""
	return text_value

static func _format_array_value(array_value: Array, indent_level: int) -> String:
	if array_value.is_empty():
		return YAML_EMPTY_ARRAY
		
	var indentation_spaces: String = " ".repeat(indent_level)
	var formatted_result: String = ""
	for item_entry in array_value:
		formatted_result += "\n" + indentation_spaces + "- " + format_yaml_value(item_entry, indent_level + SUB_OPTION_INDENT_STEP)
	return formatted_result

static func _format_dictionary_value(dict_value: Dictionary, indent_level: int) -> String:
	if dict_value.is_empty():
		return YAML_EMPTY_DICT
		
	var indentation_spaces: String = " ".repeat(indent_level)
	var formatted_result: String = ""
	for dict_key in dict_value.keys():
		var entry_val: Variant = dict_value[dict_key]
		formatted_result += "\n" + indentation_spaces + str(dict_key) + ": " + format_yaml_value(entry_val, indent_level + SUB_OPTION_INDENT_STEP)
	return formatted_result
