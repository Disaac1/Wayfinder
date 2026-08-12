extends Control

# --- DEPENDENCIES ---
const YamlBuilder = preload("res://scripts/yaml_builder.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const GameLauncher = preload("res://scripts/game_launcher.gd")
const GuidedSetupRegistry = preload("res://scripts/guided_setup_registry.gd")

# --- CONSTANTS ---
const VIEW_MODE_SETUP: String = "setup"
const VIEW_MODE_PLAY: String = "play"

# Color Palette
const COLOR_PRIMARY_BLUE: Color = Color(0.2, 0.7, 1.0)
const COLOR_HOST_PURPLE: Color = Color(0.67, 0.44, 0.98)
const COLOR_STATUS_READY: Color = Color(0.2, 0.8, 0.2)
const COLOR_STATUS_NOT_READY: Color = Color(0.8, 0.8, 0.2)
const COLOR_STATUS_OFFLINE: Color = Color(0.4, 0.4, 0.4)
const COLOR_SERVER_ACTIVE: Color = Color(0.2, 0.8, 0.4)
const COLOR_SERVER_INITIALIZING: Color = Color(0.9, 0.6, 0.15)
const COLOR_ERROR_RED: Color = Color(1.0, 0.3, 0.3)
const COLOR_MUTED_TEXT: Color = Color(0.6, 0.65, 0.7)
const COLOR_GUIDED_GREEN: Color = Color(0.3, 0.9, 0.5)

# Layout Metrics
const GAME_BADGE_SIZE: Vector2 = Vector2(42, 42)
const PLAYER_ROW_SEPARATION: int = 16
const GAME_BADGE_SEPARATION: int = 8
const DASHBOARD_CARD_MIN_SIZE: Vector2 = Vector2(280, 180)

# --- CORE NODES ---
@onready var room_label: Label = %RoomLabel
@onready var status_label: Label = %StatusLabel
@onready var server_label: Label = %ServerLabel
@onready var lock_status_label: Label = %LockStatusLabel
@onready var checkout_save_btn: Button = %CheckoutSaveBtn
@onready var checkin_save_btn: Button = %CheckinSaveBtn
@onready var force_unlock_btn: Button = %ForceUnlockBtn
@onready var launch_overlay: Control = %LaunchOverlay
@onready var launch_title: Label = %LaunchTitle
@onready var launch_close_btn: Button = %LaunchCloseBtn
@onready var launch_instructions: RichTextLabel = %LaunchInstructions
@onready var launch_path_input: LineEdit = %LaunchPathInput
@onready var launch_path_browse_btn: Button = %LaunchPathBrowseBtn
@onready var emulator_path_section: VBoxContainer = %EmulatorPathSection
@onready var launch_emulator_path_input: LineEdit = %LaunchEmulatorPathInput
@onready var launch_emulator_path_browse_btn: Button = %LaunchEmulatorPathBrowseBtn
@onready var launch_cancel_btn: Button = %LaunchCancelBtn
@onready var launch_confirm_btn: Button = %LaunchConfirmBtn
@onready var launch_file_dialog: FileDialog = %LaunchFileDialog
@onready var game_selection_section: VBoxContainer = %GameSelectionSection
@onready var game_selection_buttons: VBoxContainer = %GameSelectionButtons
@onready var path_section: VBoxContainer = %PathSection
@onready var player_list: VBoxContainer = %PlayerList
@onready var leave_btn: Button = %LeaveBtn
@onready var refresh_btn: Button = %RefreshBtn

# --- PLAY DASHBOARD NODES ---
@onready var active_seed_badge: PanelContainer = %ActiveSeedBadge
@onready var view_switcher_hbox: HBoxContainer = %ViewSwitcherHBox
@onready var play_view_btn: Button = %PlayViewBtn
@onready var setup_view_btn: Button = %SetupViewBtn
@onready var lobby_setup_view: VBoxContainer = %LobbySetupView
@onready var play_dashboard_view: VBoxContainer = %PlayDashboardView
@onready var checks_stats_label: Label = %ChecksStatsLabel
@onready var checks_progress_bar: ProgressBar = %ChecksProgressBar
@onready var server_status_value: Label = %ServerStatusValue
@onready var server_port_value: Label = %ServerPortValue
@onready var dash_view_spoiler_btn: Button = %DashViewSpoilerBtn
@onready var dash_download_seed_btn: Button = %DashDownloadSeedBtn
@onready var games_count_label: Label = %GamesCountLabel
@onready var games_grid_container: HFlowContainer = %GamesGridContainer

# --- ADD GAME OVERLAY NODES ---
@onready var add_game_overlay: Control = %AddGameOverlay
@onready var add_game_close_btn: Button = %AddGameCloseBtn
@onready var search_input: LineEdit = %SearchInput
@onready var game_popup_grid: GridContainer = %GamePopupGrid
@onready var add_game_spinner: Control = %AddGameSpinner

# --- CONFIG MODAL OVERLAY NODES ---
@onready var config_overlay: Control = %ConfigOverlay
@onready var config_title: Label = %ConfigTitle
@onready var config_close_btn: Button = %ConfigCloseBtn
@onready var config_popup_options_container: VBoxContainer = %ConfigPopupOptionsContainer
@onready var config_remove_btn: Button = %ConfigRemoveBtn
@onready var config_save_btn: Button = %ConfigSaveBtn
@onready var config_spinner: Control = %ConfigSpinner

# --- ITEM BROWSER OVERLAY NODES ---
@onready var item_browser_overlay: Control = %ItemBrowserOverlay
@onready var item_browser_title: Label = %ItemBrowserTitle
@onready var item_browser_close_btn: Button = %ItemBrowserCloseBtn
@onready var item_search_input: LineEdit = %ItemSearchInput
@onready var item_browser_list: VBoxContainer = %ItemBrowserList

# --- SEED ACTION NODES ---
@onready var start_game_btn: Button = %StartGameBtn
@onready var download_seed_btn: Button = %DownloadSeedBtn
@onready var view_spoiler_btn: Button = %ViewSpoilerBtn
@onready var generating_overlay: Control = %GeneratingOverlay
@onready var generating_status_label: Label = %GeneratingStatusLabel

# --- STATE VARIABLES ---
var all_games: Array = []
var local_selected_games: Array = []
var active_config_game: String = ""
var options_cache: Dictionary = {}
var config_states: Dictionary = {}
var use_guided_setup_mode: Dictionary = {"Pokemon Emerald": true}

var current_view_mode: String = VIEW_MODE_SETUP
var _auto_switched_to_play: bool = false

# Item / Location Browser State
var active_browser_text_edit: TextEdit = null
var active_browser_list_type: String = ""
var browser_search_query: String = ""
var browser_available_list: Array = []

# Game Launcher Module instance
var launcher: GameLauncher = GameLauncher.new()
var _active_launch_game: String = ""
var _active_launch_preset: Dictionary = {}


# =====================================================================
#                      INITIALIZATION & SIGNALS
# =====================================================================

func _ready() -> void:
	_update_room_header()
	_connect_ui_signals()
	_load_launcher_catalogs()
	_connect_network_signals()
	
	_update_players_ui(NetworkManager.players)
	_fetch_games_list()

func _update_room_header() -> void:
	room_label.text = "ROOM: " + NetworkManager.room_code

func _connect_ui_signals() -> void:
	leave_btn.pressed.connect(_on_leave_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	
	add_game_close_btn.pressed.connect(func(): add_game_overlay.visible = false)
	search_input.text_changed.connect(_on_search_text_changed)
	
	config_close_btn.pressed.connect(func(): config_overlay.visible = false)
	config_save_btn.pressed.connect(_on_config_save_pressed)
	config_remove_btn.pressed.connect(_on_config_remove_pressed)
	
	start_game_btn.pressed.connect(_on_start_game_pressed)
	download_seed_btn.pressed.connect(_on_download_seed_pressed)
	view_spoiler_btn.pressed.connect(_on_view_spoiler_pressed)
	checkout_save_btn.pressed.connect(_on_checkout_save_pressed)
	checkin_save_btn.pressed.connect(_on_checkin_save_pressed)
	force_unlock_btn.pressed.connect(_on_force_unlock_pressed)
	
	play_view_btn.pressed.connect(func(): _switch_view_mode(VIEW_MODE_PLAY))
	setup_view_btn.pressed.connect(func(): _switch_view_mode(VIEW_MODE_SETUP))
	dash_view_spoiler_btn.pressed.connect(_on_view_spoiler_pressed)
	dash_download_seed_btn.pressed.connect(_on_download_seed_pressed)
	
	launch_close_btn.pressed.connect(func(): launch_overlay.visible = false)
	launch_cancel_btn.pressed.connect(func(): launch_overlay.visible = false)
	launch_path_browse_btn.pressed.connect(func(): _open_file_browse("game"))
	launch_emulator_path_browse_btn.pressed.connect(func(): _open_file_browse("emulator"))
	launch_confirm_btn.pressed.connect(_on_launch_confirm_pressed)
	launch_file_dialog.file_selected.connect(_on_file_selected)
	
	item_browser_close_btn.pressed.connect(func(): item_browser_overlay.visible = false)
	item_search_input.text_changed.connect(_on_item_search_changed)

func _load_launcher_catalogs() -> void:
	launcher.load_launcher_config()
	launcher.load_paths_config()
	launcher.load_roms_catalog()

func _connect_network_signals() -> void:
	NetworkManager.generation_log_received.connect(_on_generation_log_received)
	NetworkManager.room_state_updated.connect(_update_players_ui)
	NetworkManager.connection_closed.connect(_on_connection_lost)


# =====================================================================
#                     LOBBY TOP BAR EVENT HANDLERS
# =====================================================================

func _on_leave_pressed() -> void:
	NetworkManager.disconnect_from_server()
	_go_to_main_menu()

func _on_refresh_pressed() -> void:
	options_cache.clear()
	var response: Dictionary = await NetworkManager.fetch_http("/api/cache/clear")
	if response.has("error"):
		print("[Lobby] Failed to clear backend cache: ", response.error)
	_fetch_games_list()

func _fetch_games_list() -> void:
	var response: Dictionary = await NetworkManager.fetch_http("/api/games")
	if response.has("error"):
		print("[Lobby] Failed to fetch games list: ", response.error)
		return
		
	all_games = response.data.get("games", [])
	all_games.sort()
	
	add_game_spinner.visible = false
	if add_game_overlay.visible:
		_populate_popup_grid(search_input.text)


# =====================================================================
#                       VIEW SWITCHER & DASHBOARD
# =====================================================================

func _switch_view_mode(mode: String) -> void:
	current_view_mode = mode
	if mode == VIEW_MODE_PLAY:
		play_view_btn.button_pressed = true
		setup_view_btn.button_pressed = false
		play_dashboard_view.visible = true
		lobby_setup_view.visible = false
		_render_play_dashboard()
	else:
		play_view_btn.button_pressed = false
		setup_view_btn.button_pressed = true
		play_dashboard_view.visible = false
		lobby_setup_view.visible = true

func _render_play_dashboard() -> void:
	for child in games_grid_container.get_children():
		child.queue_free()
		
	var assigned_games: Array = local_selected_games.duplicate()
	games_count_label.text = str(assigned_games.size()) + " Games Assigned"
	
	dash_view_spoiler_btn.visible = NetworkManager.seed_spoiler_name != ""
	dash_download_seed_btn.visible = NetworkManager.seed_zip_name != ""
	
	_update_dashboard_server_status()
		
	if assigned_games.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No games assigned to your player in this seed."
		empty_label.add_theme_color_override("font_color", COLOR_MUTED_TEXT)
		games_grid_container.add_child(empty_label)
		return
		
	for game_name in assigned_games:
		var card_panel: PanelContainer = _create_game_grid_card(game_name)
		games_grid_container.add_child(card_panel)

func _update_dashboard_server_status() -> void:
	var archipelago_server_url: String = NetworkManager.get_ap_server_url()
	if archipelago_server_url != "":
		server_status_value.text = "Central Server: Active"
		server_status_value.add_theme_color_override("font_color", COLOR_SERVER_ACTIVE)
		server_port_value.text = "URL: " + archipelago_server_url
	else:
		server_status_value.text = "Central Server: Initializing..."
		server_status_value.add_theme_color_override("font_color", COLOR_SERVER_INITIALIZING)
		server_port_value.text = "Port: 38000"

func _create_game_grid_card(game_name: String) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = DASHBOARD_CARD_MIN_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var margin_container: MarginContainer = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 16)
	margin_container.add_theme_constant_override("margin_top", 16)
	margin_container.add_theme_constant_override("margin_right", 16)
	margin_container.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin_container)
	
	var content_vbox: VBoxContainer = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	margin_container.add_child(content_vbox)
	
	var header_hbox: HBoxContainer = _create_dashboard_card_header(game_name)
	content_vbox.add_child(header_hbox)
	
	var stored_path: String = launcher.paths_config.get(game_name, "")
	var status_label_item: Label = _create_dashboard_card_status(stored_path)
	content_vbox.add_child(status_label_item)
	
	var spacer_control: Control = Control.new()
	spacer_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(spacer_control)
	
	var launch_btn_item: Button = Button.new()
	launch_btn_item.text = "LAUNCH " + game_name.to_upper()
	launch_btn_item.custom_minimum_size = Vector2(0, 38)
	launch_btn_item.add_theme_color_override("font_color", COLOR_PRIMARY_BLUE)
	launch_btn_item.pressed.connect(func(): _check_and_launch_game(game_name))
	content_vbox.add_child(launch_btn_item)
	
	var configure_btn_item: Button = Button.new()
	configure_btn_item.text = "Configure Launch Path"
	configure_btn_item.add_theme_font_size_override("font_size", 12)
	configure_btn_item.pressed.connect(func(): _show_launch_overlay_direct(game_name))
	content_vbox.add_child(configure_btn_item)
	
	return card

func _create_dashboard_card_header(game_name: String) -> HBoxContainer:
	var header_hbox: HBoxContainer = HBoxContainer.new()
	var title_label: Label = Label.new()
	title_label.text = game_name
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_label)
	
	var preset_config: Dictionary = launcher.launcher_presets.get(game_name, {})
	var launch_mode: String = preset_config.get("launch_mode", "direct")
	var mode_tag_label: Label = Label.new()
	
	if launch_mode == "ap_client":
		mode_tag_label.text = "GBA / ROM"
		mode_tag_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	elif launch_mode == "patch_rom":
		mode_tag_label.text = "SNES / ROM"
		mode_tag_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.8))
	else:
		mode_tag_label.text = "NATIVE PC"
		mode_tag_label.add_theme_color_override("font_color", COLOR_PRIMARY_BLUE)
		
	mode_tag_label.add_theme_font_size_override("font_size", 11)
	header_hbox.add_child(mode_tag_label)
	return header_hbox

func _create_dashboard_card_status(stored_path: String) -> Label:
	var status_label_item: Label = Label.new()
	status_label_item.add_theme_font_size_override("font_size", 12)
	if stored_path != "" and FileAccess.file_exists(stored_path):
		status_label_item.text = "● Executable Configured"
		status_label_item.add_theme_color_override("font_color", COLOR_STATUS_READY)
	else:
		status_label_item.text = "○ Setup / Path Required"
		status_label_item.add_theme_color_override("font_color", COLOR_SERVER_INITIALIZING)
	return status_label_item


# =====================================================================
#                        PLAYER LIST UI RENDERING
# =====================================================================

func _update_players_ui(players: Array) -> void:
	room_label.text = "ROOM: " + NetworkManager.room_code
	_update_server_address_display()
	_update_lock_status_display(players)
	
	for child in player_list.get_children():
		child.queue_free()
		
	var sorted_players: Array = _get_sorted_players(players)
	_sync_local_player_selected_games(sorted_players)

	for player_info in sorted_players:
		var player_row: HBoxContainer = _render_player_row(player_info)
		player_list.add_child(player_row)
		
	_update_seed_actions_ui(players)

func _update_server_address_display() -> void:
	server_label.visible = false
	match NetworkManager.seed_status:
		"idle":
			status_label.text = "AP SERVER: Standby"
			status_label.add_theme_color_override("font_color", COLOR_MUTED_TEXT)
		"generating":
			status_label.text = "AP SERVER: Starting..."
			status_label.add_theme_color_override("font_color", COLOR_SERVER_INITIALIZING)
		"done":
			var archipelago_server_url: String = NetworkManager.get_ap_server_url()
			if archipelago_server_url != "":
				status_label.text = "AP SERVER: Active (" + archipelago_server_url + ")"
				status_label.add_theme_color_override("font_color", COLOR_SERVER_ACTIVE)
			else:
				status_label.text = "AP SERVER: Starting..."
				status_label.add_theme_color_override("font_color", COLOR_SERVER_INITIALIZING)

func _update_lock_status_display(players: Array) -> void:
	checkout_save_btn.visible = false
	checkin_save_btn.visible = false
	force_unlock_btn.visible = false
	
	if NetworkManager.seed_status == "done":
		active_seed_badge.visible = true
		view_switcher_hbox.visible = true
		
		if not _auto_switched_to_play:
			_auto_switched_to_play = true
			_switch_view_mode(VIEW_MODE_PLAY)
		elif current_view_mode == VIEW_MODE_PLAY:
			_render_play_dashboard()
			
		if NetworkManager.locked_by == "":
			lock_status_label.text = ""
			lock_status_label.visible = false
		elif NetworkManager.locked_by == NetworkManager.user_id:
			lock_status_label.text = "SESSION LOCKED: Checked out by you"
			lock_status_label.visible = true
		else:
			var locker_name: String = "Unknown"
			for player_info in players:
				if player_info.get("userId") == NetworkManager.locked_by:
					locker_name = player_info.get("name", "Unknown")
					break
			lock_status_label.text = "SESSION LOCKED: Checked out by " + locker_name
			lock_status_label.visible = true
	else:
		active_seed_badge.visible = false
		view_switcher_hbox.visible = false
		_auto_switched_to_play = false
		_switch_view_mode(VIEW_MODE_SETUP)
		lock_status_label.text = ""
		lock_status_label.visible = false

func _get_sorted_players(players: Array) -> Array:
	var sorted_players: Array = players.duplicate()
	sorted_players.sort_custom(func(player_a: Dictionary, player_b: Dictionary) -> bool:
		var is_a_local_user: bool = player_a.get("userId") == NetworkManager.user_id
		var is_b_local_user: bool = player_b.get("userId") == NetworkManager.user_id
		if is_a_local_user and not is_b_local_user:
			return true
		elif not is_a_local_user and is_b_local_user:
			return false
			
		var is_a_host: bool = player_a.get("isHost", false)
		var is_b_host: bool = player_b.get("isHost", false)
		if is_a_host and not is_b_host:
			return true
		elif not is_a_host and is_b_host:
			return false
			
		return player_a.get("name", "").casecmp_to(player_b.get("name", "")) < 0
	)
	return sorted_players

func _sync_local_player_selected_games(sorted_players: Array) -> void:
	for player_info in sorted_players:
		if player_info.get("userId") == NetworkManager.user_id:
			local_selected_games = player_info.get("games", []).duplicate()
			break

func _render_player_row(player_info: Dictionary) -> HBoxContainer:
	var player_row: HBoxContainer = HBoxContainer.new()
	player_row.add_theme_constant_override("separation", PLAYER_ROW_SEPARATION)
	
	var name_label_item: Label = _create_player_name_label(player_info)
	player_row.add_child(name_label_item)
	
	var status_label_item: Label = _create_player_status_label(player_info)
	player_row.add_child(status_label_item)
	
	var games_hbox: HBoxContainer = HBoxContainer.new()
	games_hbox.add_theme_constant_override("separation", GAME_BADGE_SEPARATION)
	player_row.add_child(games_hbox)
	
	var player_games: Array = player_info.get("games", [])
	var is_local_player: bool = player_info.get("userId") == NetworkManager.user_id
	
	for game_title in player_games:
		var badge_button: Button = _create_game_badge(game_title, is_local_player)
		games_hbox.add_child(badge_button)
		
	if is_local_player:
		var add_game_btn_item: Button = _create_add_game_button()
		games_hbox.add_child(add_game_btn_item)
		
	return player_row

func _create_player_name_label(player_info: Dictionary) -> Label:
	var name_label_item: Label = Label.new()
	name_label_item.text = player_info.get("name", "Unknown")
	name_label_item.custom_minimum_size = Vector2(160, 0)
	
	if player_info.get("userId") == NetworkManager.user_id:
		name_label_item.text += " (You)"
		name_label_item.add_theme_color_override("font_color", COLOR_PRIMARY_BLUE)
	if player_info.get("isHost", false):
		name_label_item.text += " (Host)"
		if player_info.get("userId") != NetworkManager.user_id:
			name_label_item.add_theme_color_override("font_color", COLOR_HOST_PURPLE)
			
	return name_label_item

func _create_player_status_label(player_info: Dictionary) -> Label:
	var status_label_item: Label = Label.new()
	status_label_item.custom_minimum_size = Vector2(100, 0)
	
	var is_connected_state: bool = player_info.get("isConnected", true)
	var player_games: Array = player_info.get("games", [])
	
	if not is_connected_state:
		status_label_item.text = "OFFLINE"
		status_label_item.add_theme_color_override("font_color", COLOR_STATUS_OFFLINE)
	elif player_games.size() > 0:
		status_label_item.text = "CONFIGURED"
		status_label_item.add_theme_color_override("font_color", COLOR_STATUS_READY)
	else:
		status_label_item.text = "SELECT GAME"
		status_label_item.add_theme_color_override("font_color", COLOR_STATUS_NOT_READY)
		
	return status_label_item

func _create_game_badge(game_name: String, is_local_player: bool) -> Button:
	var badge_button: Button = Button.new()
	badge_button.custom_minimum_size = GAME_BADGE_SIZE
	badge_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	badge_button.size_flags_vertical = SIZE_SHRINK_CENTER
	
	var words: PackedStringArray = game_name.split(" ")
	var abbreviation_str: String = ""
	for word in words:
		if word.length() > 0:
			var first_char: String = word[0].to_upper()
			var char_code: int = first_char.unicode_at(0)
			if (char_code >= 48 and char_code <= 57) or (char_code >= 65 and char_code <= 90):
				abbreviation_str += first_char
				
	abbreviation_str = game_name.left(2).to_upper() if abbreviation_str == "" else abbreviation_str.left(3)
		
	badge_button.text = abbreviation_str
	badge_button.tooltip_text = game_name + " (Click to configure)" if is_local_player else game_name
	
	var name_hash_code: int = game_name.hash()
	var red_val: float = float((name_hash_code & 0xFF0000) >> 16) / 255.0
	var green_val: float = float((name_hash_code & 0x00FF00) >> 8) / 255.0
	var blue_val: float = float(name_hash_code & 0x0000FF) / 255.0
	var badge_color: Color = Color(red_val, green_val, blue_val).lerp(Color(0.2, 0.2, 0.2), 0.5)
	
	var style_flat: StyleBoxFlat = StyleBoxFlat.new()
	style_flat.bg_color = badge_color
	style_flat.corner_radius_top_left = 6
	style_flat.corner_radius_top_right = 6
	style_flat.corner_radius_bottom_left = 6
	style_flat.corner_radius_bottom_right = 6
	
	badge_button.add_theme_stylebox_override("normal", style_flat)
	badge_button.add_theme_stylebox_override("hover", style_flat.duplicate())
	badge_button.add_theme_stylebox_override("pressed", style_flat.duplicate())
	badge_button.get_theme_stylebox("hover").bg_color = badge_color.lightened(0.2)
	badge_button.get_theme_stylebox("pressed").bg_color = badge_color.darkened(0.2)
	
	if is_local_player:
		badge_button.pressed.connect(func():
			if NetworkManager.seed_status == "done":
				return
			_open_config_popup(game_name)
		)
	return badge_button

func _create_add_game_button() -> Button:
	var add_button: Button = Button.new()
	add_button.custom_minimum_size = GAME_BADGE_SIZE
	add_button.text = "+"
	add_button.tooltip_text = "Add Game"
	
	var style_flat: StyleBoxFlat = StyleBoxFlat.new()
	style_flat.bg_color = Color(0.15, 0.16, 0.22)
	style_flat.border_width_left = 1
	style_flat.border_width_top = 1
	style_flat.border_width_right = 1
	style_flat.border_width_bottom = 1
	style_flat.border_color = Color(0.3, 0.35, 0.45)
	style_flat.corner_radius_top_left = 6
	style_flat.corner_radius_top_right = 6
	style_flat.corner_radius_bottom_left = 6
	style_flat.corner_radius_bottom_right = 6
	
	add_button.add_theme_stylebox_override("normal", style_flat)
	add_button.add_theme_stylebox_override("hover", style_flat.duplicate())
	add_button.add_theme_stylebox_override("pressed", style_flat.duplicate())
	add_button.get_theme_stylebox("hover").bg_color = Color(0.25, 0.26, 0.32)
	add_button.get_theme_stylebox("pressed").bg_color = Color(0.1, 0.11, 0.15)
	add_button.pressed.connect(_on_plus_pressed)
	return add_button


# =====================================================================
#                        ADD GAME MODAL OVERLAY
# =====================================================================

func _on_plus_pressed() -> void:
	if NetworkManager.seed_status == "done":
		return
	search_input.text = ""
	add_game_overlay.visible = true
	if all_games.is_empty():
		add_game_spinner.visible = true
	else:
		add_game_spinner.visible = false
		_populate_popup_grid("")
	search_input.grab_focus()

func _on_search_text_changed(new_text: String) -> void:
	_populate_popup_grid(new_text)

func _populate_popup_grid(filter_text: String) -> void:
	for child in game_popup_grid.get_children():
		child.queue_free()
		
	var search_query_str: String = filter_text.strip_edges().to_lower()
	for game_name in all_games:
		if game_name in local_selected_games:
			continue
		if search_query_str != "" and not search_query_str in game_name.to_lower():
			continue
			
		var game_card_button: Button = Button.new()
		game_card_button.text = game_name
		game_card_button.size_flags_horizontal = SIZE_EXPAND_FILL
		game_card_button.custom_minimum_size = Vector2(130, 40)
		game_card_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		game_card_button.add_theme_font_size_override("font_size", 11)
		
		game_card_button.pressed.connect(func():
			local_selected_games.append(game_name)
			add_game_overlay.visible = false
			await _prepopulate_default_options(game_name)
			_sync_state_to_server()
		)
		game_popup_grid.add_child(game_card_button)


# =====================================================================
#                   CONFIGURE GAME OPTIONS MODAL OVERLAY
# =====================================================================

func _open_config_popup(game_name: String) -> void:
	active_config_game = game_name
	config_title.text = "Configure " + game_name
	config_overlay.visible = true
	config_spinner.visible = true
	for child in config_popup_options_container.get_children():
		child.queue_free()
	_build_options_popup_ui(game_name)

func _build_options_popup_ui(game_name: String) -> void:
	for child in config_popup_options_container.get_children():
		child.queue_free()
		
	status_label.text = "Loading options..."
	var schema_dict: Dictionary = await _get_options_schema(game_name)
	config_spinner.visible = false
	if schema_dict.is_empty() or schema_dict.has("error"):
		status_label.text = "Error"
		var error_label_item: Label = Label.new()
		error_label_item.text = "Failed to load or parse options definitions from backend."
		error_label_item.add_theme_color_override("font_color", COLOR_ERROR_RED)
		config_popup_options_container.add_child(error_label_item)
		return
		
	status_label.text = "Connected"
	if not config_states.has(game_name):
		config_states[game_name] = {}
		
	# Check if a Guided Setup Wizard is active for this game
	var has_guided_wizard: bool = GuidedSetupRegistry.has_guided_setup(game_name)
	if has_guided_wizard and use_guided_setup_mode.get(game_name, true):
		var setup_result: Dictionary = GuidedSetupRegistry.validate_and_create(game_name, schema_dict)
		if not setup_result.get("valid", false):
			print("[GuidedSetup] Fallback to raw options editor for ", game_name, ": ", setup_result.get("reason", "Unknown schema mismatch"))
			use_guided_setup_mode[game_name] = false
		else:
			var wizard_instance: RefCounted = setup_result.get("wizard")
			wizard_instance.init_config(config_states[game_name])
			if wizard_instance.has_signal("mode_toggle_requested"):
				wizard_instance.mode_toggle_requested.connect(func(use_raw_editor: bool):
					use_guided_setup_mode[game_name] = not use_raw_editor
					_build_options_popup_ui(game_name)
				)
			wizard_instance.build_wizard_ui(config_popup_options_container, func(opt_key: String, opt_val: Variant):
				config_states[game_name][opt_key] = opt_val
			)
			return

	if has_guided_wizard and not use_guided_setup_mode.get(game_name, true):
		var guided_switch_btn: Button = Button.new()
		guided_switch_btn.text = "🪄 Switch to Guided Setup Wizard"
		guided_switch_btn.add_theme_color_override("font_color", COLOR_GUIDED_GREEN)
		guided_switch_btn.pressed.connect(func():
			use_guided_setup_mode[game_name] = true
			_build_options_popup_ui(game_name)
		)
		config_popup_options_container.add_child(guided_switch_btn)
		var separator_item: HSeparator = HSeparator.new()
		config_popup_options_container.add_child(separator_item)
		
	var options_list: Array = schema_dict.get("options", [])
	if options_list.is_empty():
		var empty_options_label: Label = Label.new()
		empty_options_label.text = "No configurable options available for " + game_name + "."
		empty_options_label.add_theme_color_override("font_color", COLOR_MUTED_TEXT)
		config_popup_options_container.add_child(empty_options_label)
		return
		
	var option_categories: Dictionary = _categorize_options(options_list)
	_render_option_categories(game_name, schema_dict, option_categories)

func _categorize_options(options_list: Array) -> Dictionary:
	var categories: Dictionary = {
		"Lobby & Core Settings": [],
		"Item & Location Pools": [],
		"Traps Settings": [],
		"Game Settings": []
	}
	
	for option_def in options_list:
		var opt_name: String = option_def.get("name", "")
		var opt_name_lower: String = opt_name.to_lower()
		if opt_name in ["progression_balancing", "accessibility", "death_link", "energy_link"]:
			categories["Lobby & Core Settings"].append(option_def)
		elif opt_name in ["local_items", "non_local_items", "start_inventory", "start_hints", "start_location_hints", "exclude_locations", "priority_locations", "item_links", "start_inventory_from_pool", "plando_items"]:
			categories["Item & Location Pools"].append(option_def)
		elif "trap" in opt_name_lower:
			categories["Traps Settings"].append(option_def)
		else:
			categories["Game Settings"].append(option_def)
			
	return categories

func _render_option_categories(game_name: String, schema_dict: Dictionary, option_categories: Dictionary) -> void:
	for category_title in option_categories.keys():
		var category_options: Array = option_categories[category_title]
		if category_options.is_empty():
			continue
			
		var category_label: Label = Label.new()
		category_label.text = category_title if category_title != "Game Settings" else (game_name + " Gameplay Settings")
		category_label.add_theme_color_override("font_color", COLOR_HOST_PURPLE)
		category_label.add_theme_font_size_override("font_size", 14)
		config_popup_options_container.add_child(category_label)
		
		var category_separator: HSeparator = HSeparator.new()
		config_popup_options_container.add_child(category_separator)
		
		for option_def in category_options:
			var option_row: VBoxContainer = _create_option_row_control(game_name, schema_dict, option_def)
			config_popup_options_container.add_child(option_row)

func _create_option_row_control(game_name: String, schema_dict: Dictionary, option_def: Dictionary) -> VBoxContainer:
	var opt_name: String = option_def.get("name", "")
	var opt_display: String = option_def.get("display_name", opt_name)
	var opt_desc: String = option_def.get("description", "")
	var opt_type: String = option_def.get("type", "toggle")
	var default_val: Variant = option_def.get("default")
	
	if not config_states[game_name].has(opt_name):
		config_states[game_name][opt_name] = default_val
		
	var current_val: Variant = config_states[game_name][opt_name]
	var row_vbox: VBoxContainer = VBoxContainer.new()
	row_vbox.add_theme_constant_override("separation", 4)
	
	var label_item: Label = Label.new()
	label_item.text = opt_display
	label_item.tooltip_text = opt_desc
	label_item.add_theme_font_size_override("font_size", 13)
	row_vbox.add_child(label_item)
	
	match opt_type:
		"toggle":
			var check_btn: CheckButton = CheckButton.new()
			check_btn.button_pressed = bool(current_val)
			check_btn.toggled.connect(func(pressed: bool): config_states[game_name][opt_name] = pressed)
			row_vbox.add_child(check_btn)
			
		"range":
			var range_control: HBoxContainer = _create_range_control(game_name, opt_name, current_val, option_def)
			row_vbox.add_child(range_control)
			
		"choice":
			var dropdown_control: OptionButton = _create_choice_control(game_name, opt_name, current_val, option_def)
			row_vbox.add_child(dropdown_control)
			
		"list":
			var list_control: HBoxContainer = _create_list_control(game_name, opt_name, current_val, schema_dict)
			row_vbox.add_child(list_control)
			
		"dict":
			var dict_control: HBoxContainer = _create_dict_control(game_name, opt_name, current_val, schema_dict)
			row_vbox.add_child(dict_control)
			
	return row_vbox

func _create_range_control(game_name: String, opt_name: String, current_val: Variant, option_def: Dictionary) -> HBoxContainer:
	var min_val: int = int(option_def.get("min", 0))
	var max_val: int = int(option_def.get("max", 100))
	var hbox_container: HBoxContainer = HBoxContainer.new()
	hbox_container.add_theme_constant_override("separation", 12)
	
	var slider_item: HSlider = HSlider.new()
	slider_item.size_flags_horizontal = SIZE_EXPAND_FILL
	slider_item.min_value = min_val
	slider_item.max_value = max_val
	slider_item.value = int(current_val)
	
	var val_label_item: Label = Label.new()
	val_label_item.text = str(current_val)
	val_label_item.custom_minimum_size = Vector2(30, 0)
	
	slider_item.value_changed.connect(func(val: float):
		val_label_item.text = str(int(val))
		config_states[game_name][opt_name] = int(val)
	)
	hbox_container.add_child(slider_item)
	hbox_container.add_child(val_label_item)
	return hbox_container

func _create_choice_control(game_name: String, opt_name: String, current_val: Variant, option_def: Dictionary) -> OptionButton:
	var dropdown_item: OptionButton = OptionButton.new()
	dropdown_item.size_flags_horizontal = SIZE_EXPAND_FILL
	var choices_list: Array = option_def.get("choices", [])
	var select_idx: int = -1
	
	for idx in range(choices_list.size()):
		var choice_item: String = choices_list[idx]
		dropdown_item.add_item(choice_item)
		if choice_item == str(current_val):
			select_idx = idx
			
	if select_idx != -1:
		dropdown_item.selected = select_idx
		
	dropdown_item.item_selected.connect(func(idx: int):
		config_states[game_name][opt_name] = dropdown_item.get_item_text(idx)
	)
	return dropdown_item

func _create_list_control(game_name: String, opt_name: String, current_val: Variant, schema_dict: Dictionary) -> HBoxContainer:
	var container: HBoxContainer = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	
	var text_edit: TextEdit = TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, 80)
	text_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	text_edit.placeholder_text = "Enter entries (one per line)..."
	var array_val: Array = current_val if typeof(current_val) == TYPE_ARRAY else []
	text_edit.text = "\n".join(array_val)
	
	text_edit.text_changed.connect(func():
		var lines: PackedStringArray = text_edit.text.split("\n")
		var clean_lines: Array = []
		for line in lines:
			var cleaned_line: String = line.strip_edges()
			if cleaned_line != "":
				clean_lines.append(cleaned_line)
		config_states[game_name][opt_name] = clean_lines
	)
	container.add_child(text_edit)
	
	var opt_name_lower: String = opt_name.to_lower()
	var is_location_pool: bool = "location" in opt_name_lower
	var is_item_pool: bool = "item" in opt_name_lower or "inventory" in opt_name_lower or "hints" in opt_name_lower or "pool" in opt_name_lower
	
	if is_location_pool or is_item_pool:
		var browse_button: Button = Button.new()
		browse_button.text = "Browse..."
		browse_button.custom_minimum_size = Vector2(80, 0)
		browse_button.pressed.connect(func():
			var title_str: String = "Select Locations" if is_location_pool else "Select Items"
			var available_pool: Array = schema_dict.get("location_names", []) if is_location_pool else schema_dict.get("item_names", [])
			_open_item_browser(title_str, text_edit, is_location_pool, available_pool)
		)
		container.add_child(browse_button)
		
	return container

func _create_dict_control(game_name: String, opt_name: String, current_val: Variant, schema_dict: Dictionary) -> HBoxContainer:
	var container: HBoxContainer = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	
	var text_edit: TextEdit = TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, 80)
	text_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	text_edit.placeholder_text = "Key: Count (one per line)\nExample:\nItemName: 1"
	
	var dict_val: Dictionary = current_val if typeof(current_val) == TYPE_DICTIONARY else {}
	var dict_lines: Array = []
	for dict_key in dict_val.keys():
		dict_lines.append(str(dict_key) + ": " + str(dict_val[dict_key]))
		
	text_edit.text = "\n".join(dict_lines)
	text_edit.text_changed.connect(func():
		var parsed_dict: Dictionary = {}
		var lines: PackedStringArray = text_edit.text.split("\n")
		for line in lines:
			var parts: PackedStringArray = line.split(":")
			if parts.size() == 2:
				var parsed_key: String = parts[0].strip_edges()
				var val_str: String = parts[1].strip_edges()
				if parsed_key != "" and val_str != "":
					if val_str.is_valid_int():
						parsed_dict[parsed_key] = val_str.to_int()
					else:
						parsed_dict[parsed_key] = val_str
		config_states[game_name][opt_name] = parsed_dict
	)
	container.add_child(text_edit)
	
	var opt_name_lower: String = opt_name.to_lower()
	var is_location_pool: bool = "location" in opt_name_lower
	var is_item_pool: bool = "item" in opt_name_lower or "inventory" in opt_name_lower or "hints" in opt_name_lower or "pool" in opt_name_lower
	
	if is_location_pool or is_item_pool:
		var browse_button: Button = Button.new()
		browse_button.text = "Browse..."
		browse_button.custom_minimum_size = Vector2(80, 0)
		browse_button.pressed.connect(func():
			var title_str: String = "Select Locations" if is_location_pool else "Select Items"
			var available_pool: Array = schema_dict.get("location_names", []) if is_location_pool else schema_dict.get("item_names", [])
			_open_item_browser(title_str, text_edit, is_location_pool, available_pool)
		)
		container.add_child(browse_button)
		
	return container

func _prepopulate_default_options(game_name: String) -> void:
	if not config_states.has(game_name):
		config_states[game_name] = {}
	var schema_dict: Dictionary = await _get_options_schema(game_name)
	if schema_dict.is_empty() or schema_dict.has("error"):
		return
	var options_list: Array = schema_dict.get("options", [])
	for option_def in options_list:
		var opt_name: String = option_def.get("name", "")
		var default_val: Variant = option_def.get("default")
		if not config_states[game_name].has(opt_name):
			config_states[game_name][opt_name] = default_val

func _get_options_schema(game_name: String) -> Dictionary:
	if options_cache.has(game_name):
		return options_cache[game_name]
	var response: Dictionary = await NetworkManager.fetch_http("/api/options/" + game_name.uri_encode())
	if response.has("error"):
		print("[Lobby] Error loading options schema: ", response.error)
		return {}
	options_cache[game_name] = response.data
	return response.data

func _on_config_save_pressed() -> void:
	config_overlay.visible = false
	_sync_state_to_server()

func _on_config_remove_pressed() -> void:
	if active_config_game != "":
		local_selected_games.erase(active_config_game)
		config_states.erase(active_config_game)
	config_overlay.visible = false
	_sync_state_to_server()

func _sync_state_to_server() -> void:
	var is_ready_state: bool = local_selected_games.size() > 0
	var compiled_yaml_str: String = YamlBuilder.compile_yaml(
		local_selected_games, 
		active_config_game, 
		NetworkManager.player_name, 
		NetworkManager.room_code, 
		config_states
	)
	NetworkManager.update_player_state(local_selected_games, is_ready_state, compiled_yaml_str)


# =====================================================================
#                     ITEM / LOCATION BROWSER OVERLAY
# =====================================================================

func _on_connection_lost() -> void:
	status_label.text = "Connection Lost!"
	status_label.add_theme_color_override("font_color", COLOR_ERROR_RED)
	await get_tree().create_timer(2.0).timeout
	_go_to_main_menu()

func _go_to_main_menu() -> void:
	NetworkManager.room_state_updated.disconnect(_update_players_ui)
	NetworkManager.connection_closed.disconnect(_on_connection_lost)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _open_item_browser(title_text: String, target_text_edit: TextEdit, is_location: bool, available_list: Array) -> void:
	active_browser_text_edit = target_text_edit
	active_browser_list_type = "locations" if is_location else "items"
	browser_search_query = ""
	item_search_input.text = ""
	browser_available_list = available_list
	item_browser_title.text = title_text
	item_browser_overlay.visible = true
	_update_item_browser_ui()

func _on_item_search_changed(new_text: String) -> void:
	browser_search_query = new_text.to_lower().strip_edges()
	_update_item_browser_ui()

func _update_item_browser_ui() -> void:
	for child in item_browser_list.get_children():
		child.queue_free()
	if active_browser_text_edit == null:
		return
		
	var current_selections: Array = []
	var raw_lines: PackedStringArray = active_browser_text_edit.text.split("\n")
	for line in raw_lines:
		var cleaned_line: String = line.strip_edges()
		if cleaned_line != "":
			if ":" in cleaned_line:
				cleaned_line = cleaned_line.split(":")[0].strip_edges()
			current_selections.append(cleaned_line)
			
	for item_entry in browser_available_list:
		var item_str: String = str(item_entry)
		if browser_search_query != "" and not browser_search_query in item_str.to_lower():
			continue
		var is_selected_state: bool = item_str in current_selections
		var item_button: Button = Button.new()
		item_button.text = ("[x] " if is_selected_state else "[ ] ") + item_str
		item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if is_selected_state:
			item_button.add_theme_color_override("font_color", COLOR_HOST_PURPLE)
		item_button.pressed.connect(func(): _toggle_item_in_browser(item_str, is_selected_state))
		item_browser_list.add_child(item_button)

func _toggle_item_in_browser(item_name: String, currently_selected: bool) -> void:
	if active_browser_text_edit == null:
		return
	var raw_lines: PackedStringArray = active_browser_text_edit.text.split("\n")
	var new_lines: Array = []
	var found_item: bool = false
	
	for line in raw_lines:
		var cleaned_line: String = line.strip_edges()
		if cleaned_line == "":
			continue
		var key_name: String = cleaned_line
		if ":" in cleaned_line:
			key_name = cleaned_line.split(":")[0].strip_edges()
		if key_name == item_name:
			found_item = true
			if currently_selected:
				continue
			else:
				new_lines.append(cleaned_line)
		else:
			new_lines.append(cleaned_line)
			
	if not found_item and not currently_selected:
		if ":" in active_browser_text_edit.placeholder_text:
			new_lines.append(item_name + ": 1")
		else:
			new_lines.append(item_name)
			
	active_browser_text_edit.text = "\n".join(new_lines)
	active_browser_text_edit.text_changed.emit()
	_update_item_browser_ui()


# =====================================================================
#                     SEED ACTIONS & GENERATION LOGS
# =====================================================================

func _update_seed_actions_ui(players: Array) -> void:
	var is_host_player: bool = false
	for player_info in players:
		if player_info.get("userId") == NetworkManager.user_id:
			is_host_player = player_info.get("isHost", false)
			break
			
	var all_players_has_games: bool = not players.is_empty()
	for player_info in players:
		var p_games: Array = player_info.get("games", [])
		if p_games.is_empty():
			all_players_has_games = false
			break
			
	match NetworkManager.seed_status:
		"idle":
			generating_overlay.visible = false
			download_seed_btn.visible = false
			view_spoiler_btn.visible = false
			start_game_btn.visible = is_host_player
			start_game_btn.disabled = not all_players_has_games or NetworkManager.locked_by != ""
		"generating":
			generating_overlay.visible = true
			download_seed_btn.visible = false
			view_spoiler_btn.visible = false
			start_game_btn.visible = false
		"done":
			generating_overlay.visible = false
			download_seed_btn.visible = false
			view_spoiler_btn.visible = NetworkManager.seed_spoiler_name != ""
			start_game_btn.visible = false

func _on_start_game_pressed() -> void:
	generating_status_label.text = "Preparing generation..."
	_sync_state_to_server()
	NetworkManager.generate_seed()

func _on_download_seed_pressed() -> void:
	if NetworkManager.seed_zip_name != "":
		var seed_download_url: String = NetworkManager.get_http_url() + "/api/seeds/" + NetworkManager.room_code + "/outputs/" + NetworkManager.seed_zip_name.uri_encode()
		OS.shell_open(seed_download_url)

func _on_view_spoiler_pressed() -> void:
	if NetworkManager.seed_spoiler_name != "":
		var spoiler_download_url: String = NetworkManager.get_http_url() + "/api/seeds/" + NetworkManager.room_code + "/outputs/" + NetworkManager.seed_spoiler_name.uri_encode()
		OS.shell_open(spoiler_download_url)

func _on_generation_log_received(line: String) -> void:
	generating_status_label.text = line


# =====================================================================
#                     CLOUD SAVES DELEGATION
# =====================================================================

func _on_checkout_save_pressed() -> void:
	SaveManager.checkout_save(self, NetworkManager.room_code, NetworkManager.user_id, checkout_save_btn, func(msg: String): status_label.text = msg)

func _on_checkin_save_pressed() -> void:
	SaveManager.checkin_save(self, NetworkManager.room_code, NetworkManager.user_id, checkin_save_btn, func(msg: String): status_label.text = msg)

func _on_force_unlock_pressed() -> void:
	SaveManager.force_unlock_session(self, NetworkManager.room_code, NetworkManager.user_id, force_unlock_btn, func(msg: String): status_label.text = msg)


# =====================================================================
#                     GAME LAUNCHER DELEGATION & OVERLAY
# =====================================================================

func _on_launch_game_pressed() -> void:
	var player_configured_games: Array = []
	for player_info in NetworkManager.players:
		if player_info.get("userId") == NetworkManager.user_id:
			player_configured_games = player_info.get("games", [])
			break
			
	if player_configured_games.is_empty():
		return
	if player_configured_games.size() == 1:
		_check_and_launch_game(player_configured_games[0])
	else:
		_show_multi_game_selector(player_configured_games)

func _check_and_launch_game(game_name: String) -> void:
	var preset_config: Dictionary = launcher.launcher_presets.get(game_name, {})
	if preset_config.is_empty():
		_show_launch_overlay_direct(game_name, "No preset found. Please configure the game path manually.")
		return
		
	var exec_name: String = preset_config.get("client_executable", preset_config.get("executable_name", ""))
	var sub_folders: Array = preset_config.get("sub_folders", [])
	
	if preset_config.get("support_tier", 0) == 1:
		_execute_tier1_launch(game_name, preset_config)
		return
		
	var stored_path: String = launcher.paths_config.get(game_name, "")
	if stored_path != "" and FileAccess.file_exists(stored_path):
		launcher.execute_preset_launch(self, game_name, preset_config, stored_path, game_name)
		return
		
	if exec_name != "":
		var discovered_path: String = launcher.find_game_executable(exec_name, sub_folders)
		if discovered_path != "":
			launcher.paths_config[game_name] = discovered_path
			launcher.save_paths_config()
			launcher.execute_preset_launch(self, game_name, preset_config, discovered_path, game_name)
			return
			
	_show_launch_overlay_direct(game_name, preset_config.get("install_instructions", ""))

func _execute_tier1_launch(game_name: String, preset_config: Dictionary) -> void:
	var client_tool_key: String = preset_config.get("client_tool", "")
	var client_tool: Dictionary = launcher.launcher_tools.get(client_tool_key, {})
	var client_exe: String = client_tool.get("executable", preset_config.get("client_executable", "ArchipelagoLauncher.exe"))
	var client_aliases: Array = client_tool.get("executable_aliases", [client_exe])
	if not client_aliases.has(client_exe):
		client_aliases.push_front(client_exe)
	var client_url: String = client_tool.get("download_url", preset_config.get("client_download_url", ""))
	var client_subs: Array = client_tool.get("sub_folders", ["Archipelago"])
	var client_name: String = client_tool.get("name", "Archipelago Client")
	
	var emu_tool_key: String = preset_config.get("emulator_tool", "")
	var emu_tool: Dictionary = launcher.launcher_tools.get(emu_tool_key, {})
	var emu_exe: String = emu_tool.get("executable", preset_config.get("emulator_executable", "EmuHawk.exe"))
	var emu_url: String = emu_tool.get("download_url", preset_config.get("emulator_download_url", ""))
	var emu_subs: Array = emu_tool.get("sub_folders", preset_config.get("emulator_sub_folders", ["BizHawk"]))
	var emu_name: String = emu_tool.get("name", "BizHawk Emulator")
	var required_rom: String = preset_config.get("required_rom", "")
	
	launcher.ensure_rom_exists_or_download(self, required_rom, func(rom_success: bool, rom_path_or_err: String):
		if not rom_success:
			_show_launch_overlay_direct(game_name, "ROM Error: " + rom_path_or_err)
			return
		var rom_path: String = rom_path_or_err
		var ap_client_path: String = launcher.paths_config.get(game_name, "")
		if ap_client_path != "":
			var file_basename: String = ap_client_path.get_file().to_lower()
			var is_valid_alias: bool = false
			for alias in client_aliases:
				if file_basename == alias.to_lower():
					is_valid_alias = true
					break
			if not is_valid_alias:
				print("[Launcher] Discarding invalid cached path for ", game_name, ": ", ap_client_path)
				ap_client_path = ""
			
		if ap_client_path == "" or not FileAccess.file_exists(ap_client_path):
			var specific_clients: Array = [client_exe]
			for alias in client_aliases:
				if not specific_clients.has(alias):
					specific_clients.append(alias)
			for candidate_exe in specific_clients:
				ap_client_path = launcher.find_executable_recursive("user://tools", candidate_exe)
				if ap_client_path == "":
					ap_client_path = launcher.find_game_executable(candidate_exe, client_subs)
				if ap_client_path != "":
					break
			
		if ap_client_path != "":
			launcher.paths_config[game_name] = ap_client_path
			launcher.save_paths_config()
			_continue_tier1_launch_step3(game_name, preset_config, rom_path, ap_client_path, emu_exe, emu_subs, emu_url, emu_name)
		else:
			_prompt_tool_installation(client_name, client_url, client_subs[0] if not client_subs.is_empty() else "SM64EX", client_exe, func(client_success: bool, client_installed_path: String):
				if not client_success:
					_show_launch_overlay_direct(game_name, preset_config.get("install_instructions", ""))
					return
				launcher.paths_config[game_name] = client_installed_path
				launcher.save_paths_config()
				_continue_tier1_launch_step3(game_name, preset_config, rom_path, client_installed_path, emu_exe, emu_subs, emu_url, emu_name)
			)
	)

func _continue_tier1_launch_step3(game_name: String, preset_config: Dictionary, rom_path: String, ap_client_path: String, emu_exe: String, emu_subs: Array, emu_url: String, emu_name: String = "BizHawk Emulator") -> void:
	if emu_exe == "":
		_finish_tier1_launch(game_name, preset_config, rom_path, ap_client_path, "")
		return

	if OS.get_name() == "Windows":
		var sys32_dll: String = "C:/Windows/System32/msvcp100.dll"
		var syswow_dll: String = "C:/Windows/SysWOW64/msvcp100.dll"
		if not FileAccess.file_exists(sys32_dll) and not FileAccess.file_exists(syswow_dll):
			var prereq_tool: Dictionary = launcher.launcher_tools.get("bizhawk_prereqs", {})
			var prereq_url: String = prereq_tool.get("download_url", "https://github.com/TASEmulators/BizHawk-Prereqs/releases/download/2.4.8_1/bizhawk_prereqs_v2.4.8_1.zip")
			_prompt_tool_installation("BizHawk Prerequisites", prereq_url, "BizHawkPrereqs", "msvcp100.dll", func(prereq_success: bool, _path: String):
				_continue_tier1_launch_step4(game_name, preset_config, rom_path, ap_client_path, emu_exe, emu_subs, emu_url, emu_name)
			)
			return

	_continue_tier1_launch_step4(game_name, preset_config, rom_path, ap_client_path, emu_exe, emu_subs, emu_url, emu_name)

func _continue_tier1_launch_step4(game_name: String, preset_config: Dictionary, rom_path: String, ap_client_path: String, emu_exe: String, emu_subs: Array, emu_url: String, emu_name: String = "BizHawk Emulator") -> void:
	var emu_path: String = launcher.paths_config.get("bizhawk_emulator", "")
	if emu_path == "" or not FileAccess.file_exists(emu_path):
		emu_path = launcher.find_executable_recursive("user://tools", emu_exe)
		if emu_path == "":
			emu_path = launcher.find_game_executable(emu_exe, emu_subs)
		
	if emu_path != "":
		launcher.paths_config["bizhawk_emulator"] = emu_path
		launcher.save_paths_config()
		_finish_tier1_launch(game_name, preset_config, rom_path, ap_client_path, emu_path)
	else:
		_prompt_tool_installation(emu_name, emu_url, emu_subs[0] if not emu_subs.is_empty() else "BizHawk", emu_exe, func(emu_success: bool, emu_installed_path: String):
			if not emu_success:
				_finish_tier1_launch(game_name, preset_config, rom_path, ap_client_path, "")
			else:
				launcher.paths_config["bizhawk_emulator"] = emu_installed_path
				launcher.save_paths_config()
				_finish_tier1_launch(game_name, preset_config, rom_path, ap_client_path, emu_installed_path)
		)

func _finish_tier1_launch(game_name: String, preset_config: Dictionary, rom_path: String, ap_client_path: String, emu_path: String) -> void:
	launcher.sync_archipelago_host_yaml(rom_path, emu_path)
	launcher.execute_preset_launch(self, game_name, preset_config, ap_client_path, game_name)

func _prompt_tool_installation(tool_name: String, download_url: String, subfolder: String, target_exe: String, callback: Callable) -> void:
	var dest_dir: String = ProjectSettings.globalize_path("user://tools").path_join(subfolder)
	launch_title.text = "Installing " + tool_name
	launch_instructions.text = "Wayfinder is automatically setting up " + tool_name + "...\nDestination: " + dest_dir
	path_section.visible = false
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = false
	launch_overlay.visible = true
	
	_ensure_tool_installed_or_download(tool_name, download_url, subfolder, target_exe, callback)

func _get_progress_bar_str(pct: int) -> String:
	var filled_count: int = int(clamp(pct, 0, 100) / 5)
	var empty_count: int = 20 - filled_count
	var bar_str: String = ""
	for idx in range(filled_count):
		bar_str += "█"
	for idx in range(empty_count):
		bar_str += "░"
	return "[" + bar_str + "] " + str(pct) + "%"

func _update_launch_progress_ui(task_title: String, pct: int, downloaded_bytes: int, total_bytes: int) -> void:
	var bar_str: String = _get_progress_bar_str(pct)
	var display_text: String = "Installing " + task_title + "...\n\n"
	if total_bytes > 0:
		var dl_mb: float = float(downloaded_bytes) / (1024.0 * 1024.0)
		var total_mb: float = float(total_bytes) / (1024.0 * 1024.0)
		display_text += "Progress: " + bar_str + "\n"
		display_text += "Downloaded: " + String.num(dl_mb, 1) + " MB / " + String.num(total_mb, 1) + " MB"
	else:
		var dl_mb: float = float(downloaded_bytes) / (1024.0 * 1024.0)
		display_text += "Progress: " + bar_str + "\n"
		display_text += "Downloaded: " + String.num(dl_mb, 1) + " MB"
		
	if is_instance_valid(launch_instructions):
		launch_instructions.text = display_text

func _track_http_download_progress(http: HTTPRequest, task_title: String, is_active: Array) -> void:
	while is_active[0] and is_instance_valid(http):
		var dl_bytes: int = http.get_downloaded_bytes()
		var total_bytes: int = http.get_body_size()
		var pct: int = int((float(dl_bytes) / float(total_bytes)) * 100.0) if total_bytes > 0 else 0
		_update_launch_progress_ui(task_title, pct, dl_bytes, total_bytes)
		await get_tree().create_timer(0.15).timeout

func _ensure_tool_installed_or_download(tool_name: String, download_url: String, subfolder: String, target_exe: String, callback: Callable) -> void:
	var tools_dir: String = "user://tools".path_join(subfolder)
	DirAccess.make_dir_recursive_absolute(tools_dir)
	var discovered_path: String = launcher.find_game_executable(target_exe, [subfolder])
	if discovered_path != "":
		callback.call(true, discovered_path)
		return
		
	var resolved_url: String = download_url
	if resolved_url.contains("releases/latest"):
		resolved_url = "https://github.com/ArchipelagoMW/Archipelago/releases/download/0.6.7/Setup.Archipelago.0.6.7.exe"

	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	var is_exe_file: bool = resolved_url.get_file().strip_edges().to_lower().ends_with(".exe") or resolved_url.contains(".exe")
	var temp_filename: String = "user://tools/temp_" + tool_name.validate_filename() + (".exe" if is_exe_file else ".zip")
	http.download_file = temp_filename
	
	var is_downloading_flag: Array = [true]
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		is_downloading_flag[0] = false
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 0):
			if FileAccess.file_exists(temp_filename):
				DirAccess.remove_absolute(temp_filename)
			callback.call(false, "Failed to download " + tool_name)
			return
			
		if is_exe_file:
			if is_instance_valid(launch_instructions):
				launch_instructions.text = "Installing " + tool_name + "...\n\nRunning setup installer...\n" + _get_progress_bar_str(90)
			var abs_installer: String = ProjectSettings.globalize_path(temp_filename).replace("/", "\\")
			var abs_dest: String = ProjectSettings.globalize_path(tools_dir).replace("/", "\\")
			var process_id: int = OS.create_process(abs_installer, ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=" + abs_dest])
			if process_id <= 0:
				process_id = OS.create_process(abs_installer, [])
			var attempts_left: int = 30
			while attempts_left > 0:
				await get_tree().create_timer(1.0).timeout
				var check_exe: String = launcher.find_executable_recursive("user://tools", target_exe)
				if check_exe == "":
					check_exe = launcher.find_game_executable(target_exe, [subfolder])
				if check_exe != "":
					DirAccess.remove_absolute(temp_filename)
					for countdown_idx in range(5, 0, -1):
						if is_instance_valid(launch_instructions):
							launch_instructions.text = "Installation Complete for " + tool_name + "!\n" + _get_progress_bar_str(100) + "\n\nContinuing automatically in " + str(countdown_idx) + " seconds..."
						await get_tree().create_timer(1.0).timeout
					callback.call(true, check_exe)
					return
				attempts_left -= 1
			callback.call(false, "Installer launched but executable not found.")
		else:
			if is_instance_valid(launch_instructions):
				launch_instructions.text = "Installing " + tool_name + "...\n\nPreparing archive extraction...\n" + _get_progress_bar_str(95)
			await get_tree().process_frame
			
			var zip_reader: ZIPReader = ZIPReader.new()
			var open_err: Error = zip_reader.open(temp_filename)
			if open_err != OK:
				DirAccess.remove_absolute(temp_filename)
				callback.call(false, "Failed to open ZIP for " + tool_name)
				return
				
			var archive_files: PackedStringArray = zip_reader.get_files()
			var total_files: int = archive_files.size()
			var processed_files: int = 0
			
			for file_path_entry in archive_files:
				processed_files += 1
				if file_path_entry.ends_with("/"):
					DirAccess.make_dir_recursive_absolute(tools_dir.path_join(file_path_entry))
				else:
					var file_dir: String = tools_dir.path_join(file_path_entry).get_base_dir()
					DirAccess.make_dir_recursive_absolute(file_dir)
					var file_data: PackedByteArray = zip_reader.read_file(file_path_entry)
					var out_file: FileAccess = FileAccess.open(tools_dir.path_join(file_path_entry), FileAccess.WRITE)
					if out_file:
						out_file.store_buffer(file_data)
						out_file.close()
						
				if processed_files % 10 == 0 or processed_files == total_files:
					var ext_pct: int = int((float(processed_files) / float(max(total_files, 1))) * 100.0)
					if is_instance_valid(launch_instructions):
						launch_instructions.text = "Installing " + tool_name + "...\n\nExtracting files (" + str(processed_files) + " / " + str(total_files) + ")...\n" + _get_progress_bar_str(ext_pct)
					await get_tree().process_frame
					
			zip_reader.close()
			DirAccess.remove_absolute(temp_filename)
			var final_exe_path: String = launcher.find_executable_recursive("user://tools", target_exe)
			if final_exe_path == "":
				final_exe_path = launcher.find_game_executable(target_exe, [subfolder])
			if final_exe_path != "":
				for countdown_idx in range(5, 0, -1):
					if is_instance_valid(launch_instructions):
						launch_instructions.text = "Installation Complete for " + tool_name + "!\n" + _get_progress_bar_str(100) + "\n\nContinuing automatically in " + str(countdown_idx) + " seconds..."
					await get_tree().create_timer(1.0).timeout
				callback.call(true, final_exe_path)
			else:
				callback.call(false, "Extracted archive but executable missing.")
	)
	
	_track_http_download_progress(http, tool_name, is_downloading_flag)
	var request_err: Error = http.request(resolved_url)
	if request_err != OK:
		is_downloading_flag[0] = false
		http.queue_free()
		callback.call(false, "Failed to initiate download HTTP request for " + tool_name)

func _show_multi_game_selector(games_list: Array) -> void:
	launch_title.text = "Select Game to Launch"
	launch_instructions.text = "Select game to launch:"
	path_section.visible = false
	emulator_path_section.visible = false
	launch_confirm_btn.visible = false
	
	for child in game_selection_buttons.get_children():
		child.queue_free()
	for game_name in games_list:
		var selection_btn: Button = Button.new()
		selection_btn.text = game_name
		selection_btn.custom_minimum_size = Vector2(180, 40)
		selection_btn.pressed.connect(func(): _select_game_from_list(game_name))
		game_selection_buttons.add_child(selection_btn)
		
	game_selection_section.visible = true
	launch_overlay.visible = true

func _select_game_from_list(game_name: String) -> void:
	game_selection_section.visible = false
	path_section.visible = true
	launch_confirm_btn.visible = true
	_setup_game_details_in_overlay(game_name)

func _show_launch_overlay_direct(game_name: String, instructions_text: String = "") -> void:
	game_selection_section.visible = false
	path_section.visible = true
	launch_confirm_btn.visible = true
	_setup_game_details_in_overlay(game_name, instructions_text)

func _setup_game_details_in_overlay(game_name: String, instructions_override: String = "") -> void:
	_active_launch_game = game_name
	_active_launch_preset = launcher.launcher_presets.get(game_name, {})
	var support_tier_level: int = _active_launch_preset.get("support_tier", 2)
	launch_title.text = "Launch Setup: " + game_name + " [Tier " + str(support_tier_level) + "]"
	launch_instructions.text = instructions_override if instructions_override != "" else _active_launch_preset.get("install_instructions", "")
	
	var stored_path: String = launcher.paths_config.get(game_name, "")
	var launch_mode: String = _active_launch_preset.get("launch_mode", "")
	var client_tool_key: String = _active_launch_preset.get("client_tool", "")
	var client_tool: Dictionary = launcher.launcher_tools.get(client_tool_key, {})
	var client_executable: String = client_tool.get("executable", _active_launch_preset.get("client_executable", ""))
	
	if launch_mode == "ap_client":
		%PathLabel.text = "Archipelago Client Path (" + client_executable + ")"
		launch_path_input.placeholder_text = "Select path to " + client_executable + "..."
		if stored_path == "":
			var sub_folders: Array = client_tool.get("sub_folders", ["Archipelago"])
			stored_path = launcher.find_game_executable(client_executable, sub_folders)
			if stored_path != "":
				launcher.paths_config[game_name] = stored_path
				launcher.save_paths_config()
	elif launch_mode == "patch_rom":
		%PathLabel.text = "Clean Base ROM Path"
		launch_path_input.placeholder_text = "Select path to clean base ROM..."
	else:
		%PathLabel.text = "Game Executable Path"
		launch_path_input.placeholder_text = "Select path to game executable..."
		
	launch_path_input.text = stored_path
	emulator_path_section.visible = (launch_mode == "patch_rom")
	if launch_mode == "patch_rom":
		launch_emulator_path_input.text = launcher.paths_config.get("snes_emulator", "")
	launch_overlay.visible = true

func _open_file_browse(field_identifier: String) -> void:
	launcher._active_browse_field = field_identifier
	launch_file_dialog.popup_centered()

func _on_file_selected(selected_path_str: String) -> void:
	if launcher._active_browse_field == "game":
		launch_path_input.text = selected_path_str
	elif launcher._active_browse_field == "emulator":
		launch_emulator_path_input.text = selected_path_str

func _on_launch_confirm_pressed() -> void:
	var game_path_str: String = launch_path_input.text.strip_edges()
	if game_path_str == "":
		return
	var required_rom: String = _active_launch_preset.get("required_rom", "")
	if required_rom != "":
		launcher.ensure_rom_exists_or_download(self, required_rom, func(success: bool, _error_or_path: String):
			if not success:
				return
			_continue_launch_confirm(game_path_str)
		)
	else:
		_continue_launch_confirm(game_path_str)

func _continue_launch_confirm(game_path_str: String) -> void:
	launcher.paths_config[_active_launch_game] = game_path_str
	if _active_launch_preset.get("launch_mode", "") == "patch_rom":
		var emulator_path_str: String = launch_emulator_path_input.text.strip_edges()
		if emulator_path_str == "":
			return
		launcher.paths_config["snes_emulator"] = emulator_path_str
		
	launcher.save_paths_config()
	launch_overlay.visible = false
	launcher.execute_preset_launch(self, _active_launch_game, _active_launch_preset, game_path_str, _active_launch_game)


# =====================================================================
#         P2P HOSTING PLACEHOLDER METHODS (FOR FUTURE RESUMPTION)
# =====================================================================

var _p2p_placeholder_server_pid: int = -1
var _p2p_placeholder_tunnel_process: Dictionary = {}
var _p2p_placeholder_tunnel_thread: Thread = Thread.new()
var _p2p_placeholder_tunnel_stop: bool = false

func _p2p_placeholder_download_seed_zip() -> void:
	var download_dir: String = "user://temp_seeds/".path_join(NetworkManager.room_code)
	DirAccess.make_dir_recursive_absolute(download_dir)
	var zip_path: String = download_dir.path_join("seed.zip")
	var downloader: HTTPRequest = HTTPRequest.new()
	add_child(downloader)
	downloader.download_file = zip_path
	downloader.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		downloader.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			_p2p_placeholder_unzip_seed(zip_path, download_dir.path_join("extracted"))
	)
	downloader.request(NetworkManager.get_http_url() + "/api/seeds/" + NetworkManager.room_code + "/outputs/" + NetworkManager.seed_zip_name.uri_encode())

func _p2p_placeholder_unzip_seed(zip_path: String, dest_dir: String) -> Error:
	var zip_reader: ZIPReader = ZIPReader.new()
	var open_err: Error = zip_reader.open(zip_path)
	if open_err != OK:
		return open_err
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var files: PackedStringArray = zip_reader.get_files()
	for file_entry in files:
		if file_entry.ends_with("/"):
			continue
		var file_bytes: PackedByteArray = zip_reader.read_file(file_entry)
		var out_file: FileAccess = FileAccess.open(dest_dir.path_join(file_entry), FileAccess.WRITE)
		if out_file:
			out_file.store_buffer(file_bytes)
			out_file.close()
	zip_reader.close()
	var multidata_path: String = _p2p_placeholder_find_multidata(dest_dir)
	if multidata_path != "":
		_p2p_placeholder_start_local_server(multidata_path)
	return OK

func _p2p_placeholder_find_multidata(dir_path: String) -> String:
	var dir_access: DirAccess = DirAccess.open(dir_path)
	if dir_access:
		dir_access.list_dir_begin()
		var file_name: String = dir_access.get_next()
		while file_name != "":
			if not dir_access.current_is_dir() and file_name.ends_with(".multidata"):
				return dir_path.path_join(file_name)
			file_name = dir_access.get_next()
	return ""

func _p2p_placeholder_start_local_server(multidata_path: String) -> void:
	var script_path: String = ProjectSettings.globalize_path("res://../backend/archipelago_core/MultiServer.py")
	_p2p_placeholder_server_pid = OS.create_process("python", [script_path, multidata_path])

func _p2p_placeholder_start_tunnel() -> void:
	var exe_path: String = ProjectSettings.globalize_path("user://bin/cloudflared.exe")
	_p2p_placeholder_tunnel_process = OS.execute_with_pipe(exe_path, ["tunnel", "--url", "http://localhost:38281"])

func _p2p_placeholder_cleanup_processes() -> void:
	if _p2p_placeholder_server_pid > 0:
		OS.kill(_p2p_placeholder_server_pid)
		_p2p_placeholder_server_pid = -1
	if _p2p_placeholder_tunnel_process.has("pid") and _p2p_placeholder_tunnel_process["pid"] > 0:
		OS.kill(_p2p_placeholder_tunnel_process["pid"])
		_p2p_placeholder_tunnel_process = {}
