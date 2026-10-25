extends Control

signal game_selected(game_name: String)
signal closed()

@onready var search_input: LineEdit = %SearchInput
@onready var show_all_worlds_checkbox: CheckBox = %ShowAllWorldsCheckBox
@onready var add_game_spinner: Control = %AddGameSpinner
@onready var game_popup_grid: GridContainer = %GamePopupGrid
@onready var close_btn: Button = %AddGameCloseBtn
@onready var count_label: Label = %CountLabel

var _all_games: Array = []
var _is_game_supported_fn: Callable = Callable()
var _selected_games: Array = []
var _cards_built: bool = false
var _card_buttons: Dictionary = {}

func _ready() -> void:
	close_btn.pressed.connect(close)
	search_input.text_changed.connect(_on_search_changed)
	show_all_worlds_checkbox.toggled.connect(_on_show_all_toggled)

func open(games: Array, supported_fn: Callable, selected: Array) -> void:
	_all_games = games
	_is_game_supported_fn = supported_fn
	_selected_games = selected
	show_all_worlds_checkbox.set_pressed_no_signal(false)
	visible = true
	search_input.text = ""
	_rebuild_cards()
	search_input.grab_focus()

func close() -> void:
	visible = false
	closed.emit()

func set_loading(is_loading: bool) -> void:
	if is_instance_valid(add_game_spinner):
		add_game_spinner.visible = is_loading

func _rebuild_cards() -> void:
	# Clear existing children
	for child in game_popup_grid.get_children():
		child.queue_free()
	_card_buttons.clear()

	var show_all = show_all_worlds_checkbox.button_pressed
	var visible_count: int = 0

	for g_item in _all_games:
		var g_name: String = str(g_item)
		var is_supported: bool = _is_game_supported_fn.call(g_name) if _is_game_supported_fn.is_valid() else true
		
		var card_btn: Button = Button.new()
		card_btn.text = g_name
		card_btn.custom_minimum_size = Vector2(210, 48)
		card_btn.focus_mode = Control.FOCUS_NONE
		card_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		
		if not is_supported:
			card_btn.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		else:
			card_btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
			
		card_btn.pressed.connect(_on_card_button_pressed.bind(g_name))
		
		game_popup_grid.add_child(card_btn)
		_card_buttons[g_name] = card_btn
		
		var should_show = show_all or is_supported
		card_btn.visible = should_show
		if should_show:
			visible_count += 1

	_cards_built = true
	_update_count_label(visible_count)

func _on_card_button_pressed(selected_game: String) -> void:
	print("[AddGameModal] Game selected: '", selected_game, "'")
	game_selected.emit(selected_game)
	close()

func _on_search_changed(query: String) -> void:
	var q = query.strip_edges().to_lower()
	var show_all = show_all_worlds_checkbox.button_pressed
	var visible_count: int = 0

	for g_item in _all_games:
		var g_name: String = str(g_item)
		if not _card_buttons.has(g_name):
			continue
		var btn: Button = _card_buttons[g_name]
		var is_supported: bool = _is_game_supported_fn.call(g_name) if _is_game_supported_fn.is_valid() else true
		
		var matches_search = (q == "" or g_name.to_lower().contains(q))
		var matches_filter = show_all or is_supported
		var show = matches_search and matches_filter
		btn.visible = show
		if show:
			visible_count += 1

	_update_count_label(visible_count)

func _on_show_all_toggled(_toggled: bool) -> void:
	_on_search_changed(search_input.text)

func _update_count_label(count: int) -> void:
	if is_instance_valid(count_label):
		count_label.text = str(count) + " Games"
