extends Control

signal closed()
signal catalog_updated(info: Dictionary)

const RomCatalogManager = preload("res://scripts/core/rom_catalog_manager.gd")

@onready var close_btn: Button = %CloseBtn
@onready var done_btn: Button = %DoneBtn
@onready var url_input: LineEdit = %UrlInput
@onready var download_btn: Button = %DownloadBtn
@onready var feedback_label: Label = %FeedbackLabel
@onready var load_local_btn: Button = %LoadLocalBtn
@onready var open_folder_btn: Button = %OpenFolderBtn
@onready var status_badge: Label = %StatusBadge
@onready var search_input: LineEdit = %SearchInput
@onready var refresh_btn: Button = %RefreshBtn
@onready var entries_container: VBoxContainer = %EntriesContainer
@onready var summary_label: Label = %SummaryLabel
@onready var path_label: Label = %PathLabel
@onready var local_file_dialog: FileDialog = %LocalFileDialog

var _all_entries: Dictionary = {}

func _ready() -> void:
	visible = false
	close_btn.pressed.connect(close)
	done_btn.pressed.connect(close)
	download_btn.pressed.connect(_on_download_pressed)
	load_local_btn.pressed.connect(func(): local_file_dialog.popup_centered(Vector2(650, 450)))
	open_folder_btn.pressed.connect(_on_open_folder_pressed)
	refresh_btn.pressed.connect(_refresh_entries)
	search_input.text_changed.connect(func(_t): _render_filtered_entries())
	local_file_dialog.file_selected.connect(_on_local_file_selected)

func open(initial_url: String = "") -> void:
	visible = true
	feedback_label.text = ""
	
	if initial_url.strip_edges() != "":
		url_input.text = initial_url.strip_edges()
	elif url_input.text.strip_edges() == "":
		var net_url: String = ""
		if Engine.has_singleton("NetworkManager"):
			pass
		url_input.text = RomCatalogManager.get_default_catalog_url()
		
	path_label.text = "Location: " + ProjectSettings.globalize_path("user://rom.json")
	_refresh_entries()

func close() -> void:
	visible = false
	closed.emit()

func _on_download_pressed() -> void:
	var target_url: String = url_input.text.strip_edges()
	if target_url == "":
		feedback_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		feedback_label.text = "Please enter a valid URL."
		return
		
	download_btn.disabled = true
	download_btn.text = "Downloading..."
	feedback_label.remove_theme_color_override("font_color")
	feedback_label.text = "Fetching rom.json from server..."
	
	RomCatalogManager.download_catalog_from_url(self, target_url, func(success: bool, msg: String, _count: int, _data: Dictionary):
		download_btn.disabled = false
		download_btn.text = "Download & Update"
		
		if success:
			feedback_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
			feedback_label.text = "✅ " + msg
			_refresh_entries()
			catalog_updated.emit(RomCatalogManager.get_catalog_info())
		else:
			feedback_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			feedback_label.text = "❌ " + msg
	)

func _on_local_file_selected(path: String) -> void:
	var res = RomCatalogManager.load_from_local_file(path)
	if res.get("success", false):
		feedback_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		feedback_label.text = "✅ Successfully imported %d entries from %s" % [res.get("configured_count", 0), path.get_file()]
		_refresh_entries()
		catalog_updated.emit(RomCatalogManager.get_catalog_info())
	else:
		feedback_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		feedback_label.text = "❌ " + res.get("error", "Failed to load local file.")

func _on_open_folder_pressed() -> void:
	var global_path: String = ProjectSettings.globalize_path("user://")
	OS.shell_open(global_path)

func _refresh_entries() -> void:
	var info: Dictionary = RomCatalogManager.get_catalog_info()
	_all_entries = info.get("entries", {})
	
	var total: int = info.get("total_count", 0)
	var configured: int = info.get("configured_count", 0)
	
	if not info.get("exists", false) or total == 0:
		status_badge.text = "⚪ No ROMs configured"
		status_badge.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	else:
		status_badge.text = "🟢 %d of %d ROMs have download links" % [configured, total]
		status_badge.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		
	summary_label.text = "Total Entries: %d | Configured: %d" % [total, configured]
	_render_filtered_entries()

func _render_filtered_entries() -> void:
	for child in entries_container.get_children():
		child.queue_free()
		
	var query: String = search_input.text.strip_edges().to_lower()
	var sorted_keys: Array = _all_entries.keys()
	sorted_keys.sort()
	
	var rendered_count: int = 0
	for k in sorted_keys:
		var key_str: String = str(k)
		if query != "" and not key_str.to_lower().contains(query):
			continue
			
		rendered_count += 1
		var val = _all_entries[k]
		var url_str: String = ""
		var is_enc: bool = false
		if val is String:
			url_str = val.strip_edges()
		elif val is Dictionary:
			url_str = str(val.get("url", "")).strip_edges()
			is_enc = val.get("encrypted", false) or str(val.get("key", "")).strip_edges() != ""
			
		var row: PanelContainer = PanelContainer.new()
		var row_margin: MarginContainer = MarginContainer.new()
		row_margin.add_theme_constant_override("margin_left", 8)
		row_margin.add_theme_constant_override("margin_top", 6)
		row_margin.add_theme_constant_override("margin_right", 8)
		row_margin.add_theme_constant_override("margin_bottom", 6)
		
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		
		var icon_lbl: Label = Label.new()
		icon_lbl.text = "🎮" if url_str != "" else "⚪"
		hbox.add_child(icon_lbl)
		
		var text_vbox: VBoxContainer = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl: Label = Label.new()
		name_lbl.text = key_str
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
		text_vbox.add_child(name_lbl)
		
		var url_lbl: Label = Label.new()
		if url_str != "":
			url_lbl.text = ("🔒 [Encrypted] " if is_enc else "🔗 ") + url_str
			url_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.6))
		else:
			url_lbl.text = "(No download link specified)"
			url_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		url_lbl.add_theme_font_size_override("font_size", 11)
		url_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_vbox.add_child(url_lbl)
		
		hbox.add_child(text_vbox)
		row_margin.add_child(hbox)
		row.add_child(row_margin)
		entries_container.add_child(row)
		
	if rendered_count == 0:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "No ROM entries match the filter." if _all_entries.size() > 0 else "No entries currently in rom.json."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		entries_container.add_child(empty_lbl)
