class_name BaseGuidedSetup
extends RefCounted

signal config_updated
signal mode_toggle_requested(use_raw: bool)

var current_step: int = 1
var current_config: Dictionary = {}
var root_container: VBoxContainer
var change_callback: Callable

# --- Virtual Methods to override in subclass ---

func _get_game_title() -> String:
	return "Game"

func _get_default_config() -> Dictionary:
	return {}

func _get_steps_data() -> Array:
	# Array of Dicts: [{"num": 1, "title": "1. Goal & Pace"}, ...]
	return []

func _get_required_schema_keys() -> Array:
	# Array of String option keys required in backend schema for wizard compatibility
	return []

func _build_step_content(_step_num: int, _container: VBoxContainer) -> void:
	pass

# --- Core Setup Logic & Validation ---

func init_config(existing_config: Dictionary) -> void:
	current_config = _get_default_config().duplicate(true)
	for key in existing_config.keys():
		current_config[key] = existing_config[key]

static func validate_schema_for_keys(schema: Dictionary, required_keys: Array) -> Dictionary:
	if schema.is_empty() or not schema.has("options"):
		return {"valid": false, "reason": "Empty or invalid schema"}
		
	var schema_options = schema.get("options", [])
	var existing_names = {}
	for opt in schema_options:
		var n = opt.get("name", "")
		if n != "":
			existing_names[n] = opt
			
	for req_key in required_keys:
		if not existing_names.has(req_key):
			return {"valid": false, "reason": "Required backend option missing: " + req_key}
			
	return {"valid": true, "reason": ""}

# --- Consistent UI Builder ---

func build_wizard_ui(container: VBoxContainer, on_change_cb: Callable) -> void:
	root_container = container
	change_callback = on_change_cb
	
	for child in container.get_children():
		child.queue_free()
		
	# 1. Top Header Bar with Mode Switcher
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	
	var title_lbl = Label.new()
	title_lbl.text = _get_game_title() + " Guided Setup"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_CYAN)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_lbl)
	
	var raw_toggle_btn = Button.new()
	raw_toggle_btn.focus_mode = Control.FOCUS_NONE
	raw_toggle_btn.text = "⚡ Switch to Full Options Editor"
	raw_toggle_btn.tooltip_text = "Switch to the raw/full options view for line-by-line control"
	raw_toggle_btn.pressed.connect(func():
		mode_toggle_requested.emit(true)
	)
	top_bar.add_child(raw_toggle_btn)
	container.add_child(top_bar)
	
	var sep1 = HSeparator.new()
	container.add_child(sep1)
	
	# 2. Step Navigation Bar
	var step_nav = HBoxContainer.new()
	step_nav.add_theme_constant_override("separation", 6)
	
	var steps = _get_steps_data()
	for s in steps:
		var step_num = int(s.get("num", 1))
		var btn = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = str(s.get("title", "Step " + str(step_num)))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		
		var is_active: bool = (step_num == current_step)
		var text_color: Color = Color.WHITE if is_active else UITheme.COLOR_MUTED_TEXT
		btn.add_theme_color_override("font_color", text_color)
		
		var bg_color: Color = UITheme.COLOR_BTN_PRIMARY_BG if is_active else UITheme.COLOR_BTN_SECONDARY_BG
		UITheme.apply_button_styles(btn, bg_color, 6)
			
		btn.pressed.connect(func():
			current_step = step_num
			build_wizard_ui(container, on_change_cb)
		)
		step_nav.add_child(btn)
		
	container.add_child(step_nav)
	
	var sep2 = HSeparator.new()
	container.add_child(sep2)
	
	# 3. Content Area
	var content_panel = VBoxContainer.new()
	content_panel.add_theme_constant_override("separation", 16)
	container.add_child(content_panel)
	
	_build_step_content(current_step, content_panel)
	
	# 4. Standard Footer Navigation
	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	
	if current_step > 1:
		var prev_btn = Button.new()
		prev_btn.focus_mode = Control.FOCUS_NONE
		prev_btn.text = "◀ Back"
		prev_btn.custom_minimum_size = Vector2(100, 36)
		prev_btn.pressed.connect(func():
			current_step -= 1
			build_wizard_ui(container, on_change_cb)
		)
		footer.add_child(prev_btn)
		
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	
	if current_step < steps.size():
		var next_btn = Button.new()
		next_btn.focus_mode = Control.FOCUS_NONE
		next_btn.text = "Next Step ▶"
		next_btn.custom_minimum_size = Vector2(120, 36)
		UITheme.apply_button_styles(next_btn, UITheme.COLOR_BTN_SUCCESS_BG, 6)
		next_btn.pressed.connect(func():
			current_step += 1
			build_wizard_ui(container, on_change_cb)
		)
		footer.add_child(next_btn)
		
	container.add_child(footer)

# --- Reusable Component Helpers for Subclasses ---

func set_option_value(key: String, val) -> void:
	current_config[key] = val
	if change_callback and change_callback.is_valid():
		change_callback.call(key, val)

func refresh_ui() -> void:
	if root_container and change_callback:
		build_wizard_ui(root_container, change_callback)

func add_step_description(container: VBoxContainer, text: String) -> void:
	var desc = Label.new()
	desc.text = text
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UITheme.COLOR_WARNING_YELLOW)
	container.add_child(desc)

func add_card_grid(container: VBoxContainer, items: Array, columns: int, selected_val, on_select: Callable) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	
	var card_width = 380 if columns == 2 else 260
	
	for item in items:
		var btn = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(card_width, 75)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = str(item.get("title", item.get("name", ""))) + "\n" + str(item.get("desc", ""))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var item_id = item.get("id", item.get("name", ""))
		var item_val = item.get("val", item_id)
		var is_selected = (str(selected_val) == str(item_id) or str(selected_val) == str(item_val))
		
		var bg_col: Color = UITheme.COLOR_CARD_SELECTED_BG if is_selected else UITheme.COLOR_BG_DARK
		var border_col: Color = UITheme.COLOR_BORDER_FOCUS if is_selected else UITheme.COLOR_BORDER_DEFAULT
		var border_w: int = 2 if is_selected else 1
		UITheme.apply_button_styles(btn, bg_col, 6, border_col, border_w, UITheme.COLOR_BORDER_HOVER)
		
		btn.pressed.connect(func():
			on_select.call(item_id, item)
			refresh_ui()
		)
		grid.add_child(btn)
		
	container.add_child(grid)
	return grid

func add_slider_option(container: VBoxContainer, label_text: String, option_key: String, min_v: int, max_v: int, step_v: int = 1, unit_suffix: String = "") -> void:
	var row = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var slider = HSlider.new()
	slider.scrollable = false
	slider.custom_minimum_size = Vector2(150, 0)
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = int(current_config.get(option_key, min_v))
	
	var val_lbl = Label.new()
	val_lbl.text = str(int(slider.value)) + unit_suffix
	slider.value_changed.connect(func(v):
		val_lbl.text = str(int(v)) + unit_suffix
		set_option_value(option_key, int(v))
	)
	row.add_child(lbl)
	row.add_child(slider)
	row.add_child(val_lbl)
	container.add_child(row)

func add_toggle_option(container: VBoxContainer, label_text: String, option_key: String) -> void:
	var check = CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.text = label_text
	var current_v_str = str(current_config.get(option_key, false)).to_lower()
	check.button_pressed = (current_v_str == "true" or current_v_str == "1" or current_v_str == "completely_random")
	check.toggled.connect(func(pressed):
		set_option_value(option_key, pressed)
	)
	container.add_child(check)

func add_dropdown_option(container: VBoxContainer, label_text: String, option_key: String, choices: Array) -> void:
	var row = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var drop = OptionButton.new()
	drop.focus_mode = Control.FOCUS_NONE
	if choices.is_empty():
		return
	var current_val = str(current_config.get(option_key, choices[0].get("id", choices[0].get("name", ""))))
	var selected_idx = 0
	
	for i in range(choices.size()):
		var c = choices[i]
		var c_id = str(c.get("id", c.get("name", "")))
		var c_title = str(c.get("title", c.get("name", c_id)))
		drop.add_item(c_title, i)
		if c_id == current_val:
			selected_idx = i
			
	drop.selected = selected_idx
	drop.item_selected.connect(func(idx):
		var selected_choice = choices[idx]
		var val = selected_choice.get("id", selected_choice.get("name", ""))
		set_option_value(option_key, val)
	)
	
	row.add_child(lbl)
	row.add_child(drop)
	container.add_child(row)
