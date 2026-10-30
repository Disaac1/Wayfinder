class_name HostYamlEditor
extends RefCounted

## HostYamlEditor
##
## A line-aware YAML document editor designed specifically for modifying
## Archipelago's `host.yaml` configuration files cleanly and reliably.
##
## Key Capabilities:
## 1. Comment & Whitespace Preservation: Untouched sections, inline comments,
##    and block comments are kept 100% intact.
## 2. Arbitrary Depth: Supports setting keys at root level, section level, or
##    nested subkeys N levels deep (e.g. `luigismansion_options.dolphin_settings.path`).
## 3. Data-Driven: Can apply full nested dictionaries or dot-separated paths
##    directly from `launch.json`.
## 4. Native Formatting: Cleanly formats booleans (`true`/`false`), nulls,
##    numbers, strings, arrays, and dictionaries.

## Internal representation of a single line within the YAML document
class LineEntry extends RefCounted:
	var raw: String = ""
	var is_blank: bool = false
	var is_comment: bool = false
	var indent: int = 0
	var key: String = ""
	var val: String = ""
	var comment: String = ""

var _lines: Array[LineEntry] = []

func _init(content: String = "") -> void:
	if content != "":
		load_from_string(content)

## Parses a raw YAML string into structured LineEntry items
func load_from_string(content: String) -> void:
	_lines.clear()
	var raw_lines: PackedStringArray = content.split("\n")
	for raw_line in raw_lines:
		_lines.append(_parse_line(raw_line))

## Serializes the internal LineEntry items back into a single YAML string
func to_string_content() -> String:
	var result_lines: PackedStringArray = []
	for entry in _lines:
		result_lines.append(entry.raw)
	return "\n".join(result_lines)

## Sets a value at a dot-separated path (e.g. "section.sub_section.key")
func set_value_at_path(dot_path: String, value: Variant) -> void:
	var keys: Array[String] = []
	for part in dot_path.split("."):
		var trimmed: String = part.strip_edges()
		if trimmed != "":
			keys.append(trimmed)
	set_value(keys, value)

## Sets a value given an array of hierarchical keys (e.g. ["section", "sub_key"])
func set_value(key_path: Array, value: Variant) -> void:
	var clean_path: Array[String] = []
	for item in key_path:
		var k_str: String = str(item).strip_edges()
		if k_str != "":
			clean_path.append(k_str)

	if clean_path.is_empty():
		return

	var formatted_val: String = format_yaml_value(value)
	_set_recursive(0, _lines.size() - 1, -1, clean_path, formatted_val)

## Recursively applies a nested Dictionary of patches to the YAML document.
## Supports both nested dictionaries and dot-notation keys in dictionary keys.
func apply_dictionary(dict: Dictionary, prefix: Array[String] = []) -> void:
	for raw_key in dict.keys():
		var key_str: String = str(raw_key).strip_edges()
		var key_parts: PackedStringArray = key_str.split(".")
		
		var current_path: Array[String] = prefix.duplicate()
		for part in key_parts:
			if part.strip_edges() != "":
				current_path.append(part.strip_edges())

		var val: Variant = dict[raw_key]
		# If the value is a nested Dictionary, recurse deeper into the hierarchy
		if typeof(val) == TYPE_DICTIONARY and not (val as Dictionary).is_empty():
			apply_dictionary(val as Dictionary, current_path)
		else:
			set_value(current_path, val)

## Formats any Variant into valid YAML syntax
static func format_yaml_value(val: Variant) -> String:
	if typeof(val) == TYPE_NIL:
		return "null"
	if typeof(val) == TYPE_BOOL:
		return "true" if val else "false"
	if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
		return str(val)
	if typeof(val) == TYPE_ARRAY:
		var arr: Array = val as Array
		if arr.is_empty():
			return "[]"
		return JSON.stringify(arr)
	if typeof(val) == TYPE_DICTIONARY:
		var d: Dictionary = val as Dictionary
		if d.is_empty():
			return "{}"
		return JSON.stringify(d)
	
	var s: String = str(val)
	if s == "true" or s == "false" or s == "null":
		return s
	if s.is_valid_int() or s.is_valid_float():
		return s
	# Enclose strings in quotes, escaping internal quotes
	var escaped: String = s.replace("\"", "\\\"")
	return "\"" + escaped + "\""

# =====================================================================
#                      INTERNAL PARSING & TRAVERSAL
# =====================================================================

## Parses a single line string into a LineEntry struct
func _parse_line(raw_line: String) -> LineEntry:
	var entry := LineEntry.new()
	# Strip carriage returns if present
	var clean: String = raw_line.trim_suffix("\r")
	entry.raw = clean

	var stripped: String = clean.strip_edges()
	if stripped == "":
		entry.is_blank = true
		entry.indent = 0
		return entry

	# Count leading spaces for indentation level
	var leading_spaces: int = 0
	while leading_spaces < clean.length() and clean[leading_spaces] == " ":
		leading_spaces += 1
	entry.indent = leading_spaces

	# Detect comment lines
	if stripped.begins_with("#"):
		entry.is_comment = true
		entry.comment = stripped
		return entry

	# Detect `key: value` or `key:` line
	var colon_idx: int = clean.find(":")
	if colon_idx != -1:
		var potential_key: String = clean.substr(0, colon_idx).strip_edges()
		# Valid YAML key cannot contain whitespace
		if not potential_key.contains(" ") and not potential_key.contains("\t"):
			entry.key = potential_key
			var rest: String = clean.substr(colon_idx + 1).strip_edges()
			
			# Check for inline comments (e.g. `value # comment`)
			var hash_pos: int = rest.find(" #")
			if hash_pos != -1:
				entry.val = rest.substr(0, hash_pos).strip_edges()
				entry.comment = rest.substr(hash_pos)
			elif rest.begins_with("#"):
				entry.val = ""
				entry.comment = rest
			else:
				entry.val = rest
			return entry

	# Fallback for unrecognized line format
	entry.val = stripped
	return entry

## Recursively finds or inserts keys in the YAML line range [start_idx, end_idx]
func _set_recursive(start_idx: int, end_idx: int, parent_indent: int, path: Array[String], formatted_val: String) -> void:
	if path.is_empty():
		return

	var target_key: String = path[0]
	var is_leaf: bool = (path.size() == 1)

	var child_indent: int = -1
	var key_line_idx: int = -1

	# 1. Search for target_key within the current parent's line boundaries
	var i: int = start_idx
	while i <= end_idx and i < _lines.size():
		var line_info: LineEntry = _lines[i]
		if line_info.is_blank or line_info.is_comment:
			i += 1
			continue

		# If we hit a line with indentation less than or equal to the parent, we left scope
		if parent_indent >= 0 and line_info.indent <= parent_indent:
			break

		if child_indent == -1:
			child_indent = line_info.indent

		if line_info.indent == child_indent:
			if line_info.key == target_key:
				key_line_idx = i
				break
		i += 1

	# Determine default indentation if no children were found
	if child_indent == -1:
		child_indent = 0 if parent_indent < 0 else parent_indent + 2

	# 2. Key exists: update it or traverse deeper
	if key_line_idx != -1:
		if is_leaf:
			# Update existing scalar line, preserving its original indent and inline comment
			var old_info: LineEntry = _lines[key_line_idx]
			var indent_str: String = " ".repeat(old_info.indent)
			var new_raw: String = indent_str + target_key + ": " + formatted_val + old_info.comment
			_lines[key_line_idx] = _parse_line(new_raw)
		else:
			# Traverse into child's block boundaries [child_start, child_end]
			var child_start: int = key_line_idx + 1
			var child_end: int = key_line_idx
			var j: int = key_line_idx + 1
			while j <= end_idx and j < _lines.size():
				var l: LineEntry = _lines[j]
				if not l.is_blank and not l.is_comment and l.indent <= child_indent:
					break
				child_end = j
				j += 1
			
			var remaining_path: Array[String] = path.slice(1)
			_set_recursive(child_start, child_end, child_indent, remaining_path, formatted_val)
	else:
		# 3. Key does not exist: insert it and any missing nested subkeys
		var insert_pos: int = clampi(end_idx + 1, 0, _lines.size())
		var cur_indent: int = child_indent
		
		var lines_to_insert: Array[LineEntry] = []
		for idx in range(path.size()):
			var k: String = path[idx]
			var indent_str: String = " ".repeat(cur_indent)
			var new_line_str: String = ""
			if idx == path.size() - 1:
				new_line_str = indent_str + k + ": " + formatted_val
			else:
				new_line_str = indent_str + k + ":"
				cur_indent += 2
			lines_to_insert.append(_parse_line(new_line_str))

		# Insert newly constructed lines into _lines array
		for offset in range(lines_to_insert.size()):
			_lines.insert(insert_pos + offset, lines_to_insert[offset])
