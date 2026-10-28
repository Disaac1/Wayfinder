extends Control

# --- DEPENDENCIES ---
const YamlBuilder = preload("res://scripts/core/yaml_builder.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const GameLauncher = preload("res://scripts/core/game_launcher.gd")
const GuidedSetupRegistry = preload("res://scripts/guided_setup/guided_setup_registry.gd")
const PlayerCardScene = preload("res://scenes/components/player_card.tscn")
const DashboardGameCardScene = preload("res://scenes/components/dashboard_game_card.tscn")

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

# --- CORE HEADER & VIEW NODES ---
@onready var room_label: Label = %RoomLabel
@onready var status_label: Label = %StatusLabel
@onready var server_label: Label = %ServerLabel
@onready var lock_status_label: Label = %LockStatusLabel
@onready var active_seed_badge: PanelContainer = %ActiveSeedBadge
@onready var badge_label: Label = %BadgeLabel
@onready var view_switcher_hbox: HBoxContainer = %ViewSwitcherHBox
@onready var play_view_btn: Button = %PlayViewBtn
@onready var setup_view_btn: Button = %SetupViewBtn

# --- SETUP VIEW NODES ---
@onready var lobby_setup_view: VBoxContainer = %LobbySetupView
@onready var player_list: VBoxContainer = %PlayerList

@onready var connection_badge: PanelContainer = %ConnectionBadge
@onready var connection_dot: Label = %ConnectionDot
@onready var server_port_value: Label = %ServerPortValue
@onready var copy_server_address_btn: Button = %CopyServerAddressBtn

# --- PLAY DASHBOARD VIEW NODES ---
@onready var play_dashboard_view: VBoxContainer = %PlayDashboardView
@onready var checks_stats_label: Label = %ChecksStatsLabel
@onready var checks_progress_bar: ProgressBar = %ChecksProgressBar
@onready var server_status_value: Label = %ServerStatusValue
@onready var dash_view_spoiler_btn: Button = get_node_or_null("%DashViewSpoilerBtn")
@onready var dash_download_seed_btn: Button = get_node_or_null("%DashDownloadSeedBtn")
@onready var filter_my_games_btn: Button = %FilterMyGamesBtn
@onready var games_count_label: Label = %GamesCountLabel
@onready var games_grid_container: HFlowContainer = %GamesGridContainer

# --- LOBBY SETUP VIEW NODES ---
@onready var seed_ready_card: PanelContainer = get_node_or_null("%SeedReadyCard")
@onready var setup_download_seed_btn: Button = get_node_or_null("%SetupDownloadSeedBtn")
@onready var setup_view_spoiler_btn: Button = get_node_or_null("%SetupViewSpoilerBtn")

# --- FOOTER BUTTONS ---
@onready var leave_btn: Button = %LeaveBtn
@onready var close_room_btn: Button = %CloseRoomBtn
@onready var refresh_btn: Button = get_node_or_null("%RefreshBtn")
@onready var start_game_btn: Button = %StartGameBtn
@onready var hosting_mode_option: OptionButton = %HostingModeOption
@onready var download_seed_btn: Button = %DownloadSeedBtn
@onready var view_spoiler_btn: Button = %ViewSpoilerBtn
@onready var checkout_save_btn: Button = %CheckoutSaveBtn
@onready var checkin_save_btn: Button = %CheckinSaveBtn
@onready var force_unlock_btn: Button = %ForceUnlockBtn

# --- MODAL SUB-SCENES ---
@onready var add_game_modal: Control = %AddGameModal
@onready var config_modal: Control = %ConfigModal
@onready var item_browser_modal: Control = %ItemBrowserModal
@onready var generating_overlay: Control = %GeneratingOverlay
@onready var launch_overlay: Control = %LaunchOverlay
@onready var host_tools_modal: Control = %HostToolsModal
@onready var host_tools_btn: Button = get_node_or_null("%HostToolsBtn")

# --- LAUNCH OVERLAY NODE ALIASES ---
@onready var launch_title: Label = launch_overlay.launch_title
@onready var launch_close_btn: Button = launch_overlay.launch_close_btn
@onready var launch_instructions: RichTextLabel = launch_overlay.launch_instructions
@onready var launch_progress_bar: ProgressBar = launch_overlay.launch_progress_bar
@onready var launch_path_input: LineEdit = launch_overlay.launch_path_input
@onready var launch_path_browse_btn: Button = launch_overlay.launch_path_browse_btn
@onready var launch_download_btn: Button = launch_overlay.launch_download_btn
@onready var emulator_path_section: VBoxContainer = launch_overlay.emulator_path_section
@onready var emulator_path_label: Label = launch_overlay.emulator_path_label
@onready var launch_emulator_path_input: LineEdit = launch_overlay.launch_emulator_path_input
@onready var launch_emulator_path_browse_btn: Button = launch_overlay.launch_emulator_path_browse_btn
@onready var launch_cancel_btn: Button = launch_overlay.launch_cancel_btn
@onready var launch_confirm_btn: Button = launch_overlay.launch_confirm_btn
@onready var launch_file_dialog: FileDialog = launch_overlay.launch_file_dialog
@onready var game_selection_section: VBoxContainer = launch_overlay.game_selection_section
@onready var game_selection_buttons: VBoxContainer = launch_overlay.game_selection_buttons
@onready var path_section: VBoxContainer = launch_overlay.path_section
@onready var path_label: Label = launch_overlay.path_label

# Backward compatibility aliases for tests
var add_game_overlay: Control:
	get:
		return add_game_modal
var config_overlay: Control:
	get:
		return config_modal
var item_browser_overlay: Control:
	get:
		return item_browser_modal

func _get_preset_packages(preset_config: Dictionary) -> Array:
	return launcher._get_preset_packages(preset_config)

# --- STATE VARIABLES ---
const GAMES_CACHE_PATH: String = "user://cache/games_list.json"
var all_games: Array = []
var local_selected_games: Array = []
var active_config_game: String = ""
var options_cache: Dictionary = {}
var config_states: Dictionary = {}
var use_guided_setup_mode: Dictionary = {}

var current_view_mode: String = VIEW_MODE_SETUP
var _auto_switched_to_play: bool = false

# Game Launcher Module instance
var launcher: GameLauncher = GameLauncher.new()
var _active_launch_game: String = ""
var _active_launch_preset: Dictionary = {}
var _active_prompt_callback: Callable = Callable()
var _tracker_operation_active: bool = false

# =====================================================================
#                      INITIALIZATION & SIGNALS
# =====================================================================

func _ready() -> void:
	print("[Lobby] Initializing Lobby scene for Room: '%s' (User: %s)" % [NetworkManager.room_code, NetworkManager.user_id])
	_connect_ui_signals()
	_load_launcher_catalogs()
	_connect_network_signals()
	hosting_mode_option.item_selected.connect(_on_hosting_mode_selected)
	_load_hosting_mode()
	_update_hosting_mode_ui()
	_sync_needed_custom_worlds()
	_load_cached_games_list()

	_update_room_header()
	_update_players_ui()

func _sync_needed_custom_worlds() -> void:
	var needed_games: Array = []
	for p in NetworkManager.players:
		for g in p.get("games", []):
			if not needed_games.has(g):
				needed_games.append(g)
	for g in local_selected_games:
		if not needed_games.has(g):
			needed_games.append(g)
	if not needed_games.is_empty():
		launcher.sync_custom_worlds_from_server(self, needed_games)

func _update_room_header() -> void:
	room_label.text = "ROOM: " + NetworkManager.room_code

func _connect_ui_signals() -> void:
	leave_btn.pressed.connect(_on_leave_pressed)
	if is_instance_valid(close_room_btn):
		close_room_btn.pressed.connect(_on_close_room_pressed)
	if is_instance_valid(refresh_btn):
		refresh_btn.pressed.connect(_on_refresh_pressed)
	
	# Modal sub-scene connections
	add_game_modal.game_selected.connect(_on_game_card_selected)
	config_modal.saved.connect(_on_config_modal_saved)
	config_modal.removed.connect(_on_config_modal_removed)
	config_modal.browse_items_requested.connect(func(t, te, is_loc, pool):
		item_browser_modal.open(t, te, is_loc, pool)
	)
	
	# Launch overlay modal signals
	launch_overlay.closed.connect(func(): _render_play_dashboard())
	launch_overlay.cancellation_requested.connect(_on_launch_overlay_cancellation_requested)
	launch_overlay.confirmed.connect(func(g_name, g_path, emu_path):
		_continue_launch_confirm(g_path)
	)
	launch_overlay.download_auto_pressed.connect(_on_launch_download_pressed)
	launch_overlay.game_selected.connect(_select_game_from_list)
	if launch_overlay.has_signal("steam_btn_pressed"):
		launch_overlay.steam_btn_pressed.connect(_on_launch_steam_pressed)
	if launch_overlay.has_signal("recheck_btn_pressed"):
		launch_overlay.recheck_btn_pressed.connect(_on_launch_recheck_pressed)
	
	# Seed actions
	start_game_btn.pressed.connect(_on_start_game_pressed)
	download_seed_btn.pressed.connect(_on_download_seed_pressed)
	view_spoiler_btn.pressed.connect(_on_view_spoiler_pressed)
	if is_instance_valid(setup_download_seed_btn):
		setup_download_seed_btn.pressed.connect(_on_download_seed_pressed)
	if is_instance_valid(setup_view_spoiler_btn):
		setup_view_spoiler_btn.pressed.connect(_on_view_spoiler_pressed)
	checkout_save_btn.pressed.connect(_on_checkout_save_pressed)
	checkin_save_btn.pressed.connect(_on_checkin_save_pressed)
	force_unlock_btn.pressed.connect(_on_force_unlock_pressed)
	
	# View switcher
	play_view_btn.pressed.connect(func(): _switch_view_mode(VIEW_MODE_PLAY))
	setup_view_btn.pressed.connect(func(): _switch_view_mode(VIEW_MODE_SETUP))
	if is_instance_valid(dash_view_spoiler_btn):
		dash_view_spoiler_btn.pressed.connect(_on_view_spoiler_pressed)
	if is_instance_valid(dash_download_seed_btn):
		dash_download_seed_btn.pressed.connect(_on_download_seed_pressed)
	if is_instance_valid(filter_my_games_btn):
		filter_my_games_btn.toggled.connect(func(_p): _render_play_dashboard())
	if is_instance_valid(copy_server_address_btn):
		copy_server_address_btn.pressed.connect(_on_copy_server_address_pressed)
	if is_instance_valid(host_tools_btn):
		host_tools_btn.pressed.connect(_on_host_tools_pressed)
	
	# GameLauncher module signals
	launcher.launch_status_updated.connect(_on_launcher_status_updated)
	launcher.prompt_file_selection.connect(_on_launcher_prompt_file_selection)
	launcher.prompt_tool_installation.connect(_on_launcher_prompt_tool_installation)
	launcher.launch_completed.connect(_on_launcher_completed)
	launcher.launch_failed.connect(_on_launcher_failed)
	launcher.config_loaded.connect(_on_launcher_config_loaded)

func _on_launcher_config_loaded() -> void:
	print("[Lobby] Launcher config updated from backend. Refreshing game statuses...")
	for child in games_grid_container.get_children():
		if child.has_method("update_launch_status") and "current_game_name" in child:
			var g_name: String = child.current_game_name
			var status_info: Dictionary = launcher.get_game_launch_status(g_name)
			child.update_launch_status(status_info)
			child.update_tracker_support(launcher.get_preset(g_name))

func _on_launch_overlay_cancellation_requested() -> void:
	if not _tracker_operation_active:
		launcher.cancel_tool_installation()

func _load_launcher_catalogs() -> void:
	launcher.load_paths_config()
	launcher.load_roms_catalog()
	launcher.load_launcher_config()

func _connect_network_signals() -> void:
	NetworkManager.room_state_updated.connect(_update_players_ui)
	NetworkManager.checks_updated.connect(_on_checks_updated)
	NetworkManager.generation_log_received.connect(_on_generation_log_received)
	NetworkManager.kicked_from_room.connect(_on_kicked_from_room)
	NetworkManager.room_closed.connect(_on_room_closed)
	NetworkManager.connection_closed.connect(_on_connection_lost)

func _on_leave_pressed() -> void:
	NetworkManager.leave_room()
	_go_to_main_menu()

func _on_close_room_pressed() -> void:
	var confirm_dialog: ConfirmationDialog = ConfirmationDialog.new()
	confirm_dialog.title = "Close Room"
	confirm_dialog.dialog_text = "Are you sure you want to completely close and delete room " + NetworkManager.room_code + "? All players will be disconnected."
	confirm_dialog.ok_button_text = "Close Room"
	confirm_dialog.cancel_button_text = "Cancel"
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()
	
	confirm_dialog.confirmed.connect(func():
		NetworkManager.close_room()
		confirm_dialog.queue_free()
	)
	confirm_dialog.canceled.connect(func():
		confirm_dialog.queue_free()
	)

func _on_kicked_from_room(message: String) -> void:
	var info_dialog: AcceptDialog = AcceptDialog.new()
	info_dialog.title = "Kicked from Room"
	info_dialog.dialog_text = message
	add_child(info_dialog)
	info_dialog.popup_centered()
	info_dialog.confirmed.connect(func():
		info_dialog.queue_free()
		_go_to_main_menu()
	)

func _on_room_closed(message: String) -> void:
	var info_dialog: AcceptDialog = AcceptDialog.new()
	info_dialog.title = "Room Closed"
	info_dialog.dialog_text = message
	add_child(info_dialog)
	info_dialog.popup_centered()
	info_dialog.confirmed.connect(func():
		info_dialog.queue_free()
		_go_to_main_menu()
	)

func _is_local_player_host() -> bool:
	for player_info in NetworkManager.players:
		if player_info.get("userId") == NetworkManager.user_id:
			return player_info.get("isHost", false)
	return false

func _show_kick_confirm_dialog(target_id: String, target_name: String) -> void:
	var confirm_dialog: ConfirmationDialog = ConfirmationDialog.new()
	confirm_dialog.title = "Kick Player"
	confirm_dialog.dialog_text = "Are you sure you want to kick " + target_name + " from the room?"
	confirm_dialog.ok_button_text = "Kick"
	confirm_dialog.cancel_button_text = "Cancel"
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()
	
	confirm_dialog.confirmed.connect(func():
		NetworkManager.kick_player(target_id)
		confirm_dialog.queue_free()
	)
	confirm_dialog.canceled.connect(func():
		confirm_dialog.queue_free()
	)

func _on_refresh_pressed() -> void:
	if FileAccess.file_exists(GAMES_CACHE_PATH):
		DirAccess.remove_absolute(GAMES_CACHE_PATH)
	options_cache.clear()
	_fetch_games_list()

func _load_cached_games_list() -> void:
	if FileAccess.file_exists(GAMES_CACHE_PATH):
		var file: FileAccess = FileAccess.open(GAMES_CACHE_PATH, FileAccess.READ)
		var json_string: String = file.get_as_text()
		file.close()
		var json: JSON = JSON.new()
		if json.parse(json_string) == OK:
			if json.data is Array:
				all_games = json.data
			elif json.data is Dictionary and json.data.has("games") and json.data["games"] is Array:
				all_games = json.data["games"]
			elif json.data is Dictionary and json.data.has("list") and json.data["list"] is Array:
				all_games = json.data["list"]
	_fetch_games_list()

func _fetch_games_list() -> void:
	add_game_modal.set_loading(true)
	var response: Dictionary = await NetworkManager.fetch_http("/api/games")
	add_game_modal.set_loading(false)
	if not response.has("error"):
		var raw_data = response.get("data")
		var extracted: Array = []
		if raw_data is Array:
			extracted = raw_data
		elif raw_data is Dictionary:
			if raw_data.has("games") and raw_data["games"] is Array:
				extracted = raw_data["games"]
			elif raw_data.has("list") and raw_data["list"] is Array:
				extracted = raw_data["list"]
		
		if not extracted.is_empty():
			all_games = extracted
			DirAccess.make_dir_recursive_absolute("user://cache")
			var file: FileAccess = FileAccess.open(GAMES_CACHE_PATH, FileAccess.WRITE)
			if file:
				file.store_string(JSON.stringify(all_games))
				file.close()
			print("[Lobby] Successfully loaded %d games from backend /api/games" % all_games.size())


# =====================================================================
#                      VIEW SWITCHING & DASHBOARD
# =====================================================================

func _switch_view_mode(mode: String) -> void:
	print("[Lobby] View mode switched to: '%s'" % mode)
	current_view_mode = mode
	if mode == VIEW_MODE_PLAY:
		play_view_btn.button_pressed = true
		setup_view_btn.button_pressed = false
		play_dashboard_view.visible = true
		lobby_setup_view.visible = false
		download_seed_btn.visible = false
		view_spoiler_btn.visible = false
		_render_play_dashboard()
		if NetworkManager.checks.is_empty() and NetworkManager.seed_status == "done" and NetworkManager.room_code != "":
			_fetch_initial_checks()
	else:
		play_view_btn.button_pressed = false
		setup_view_btn.button_pressed = true
		play_dashboard_view.visible = false
		lobby_setup_view.visible = true
		if NetworkManager.seed_status == "done":
			var has_seed: bool = (NetworkManager.seed_zip_name != "")
			var has_spoiler: bool = (NetworkManager.seed_spoiler_name != "")
			download_seed_btn.visible = has_seed
			view_spoiler_btn.visible = has_spoiler

func _render_play_dashboard() -> void:
	for child in games_grid_container.get_children():
		child.queue_free()
		
	if local_selected_games.is_empty():
		for p in NetworkManager.players:
			if p.get("userId") == NetworkManager.user_id:
				local_selected_games = p.get("games", []).duplicate()
				break

	# 1. Collect all games across all players in the multiworld room
	var local_game_entries: Array = []
	var other_game_entries: Array = []

	var players_to_scan: Array = NetworkManager.players
	if players_to_scan.is_empty():
		for g_name in local_selected_games:
			local_game_entries.append({
				"game_name": g_name,
				"player_name": NetworkManager.player_name,
				"is_local": true,
				"user_id": NetworkManager.user_id
			})
	else:
		for p in players_to_scan:
			var p_id: String = p.get("userId", "")
			var p_name: String = p.get("name", "Player")
			var p_games: Array = p.get("games", [])
			var is_local: bool = (p_id == NetworkManager.user_id)
			for g_name in p_games:
				var entry = {
					"game_name": g_name,
					"player_name": p_name,
					"is_local": is_local,
					"user_id": p_id
				}
				if is_local:
					local_game_entries.append(entry)
				else:
					other_game_entries.append(entry)

	# Fallback if local_game_entries is empty
	if local_game_entries.is_empty():
		for g_name in local_selected_games:
			local_game_entries.append({
				"game_name": g_name,
				"player_name": NetworkManager.player_name,
				"is_local": true,
				"user_id": NetworkManager.user_id
			})

	# 2. Sort local player's games first, then other players' games
	var all_player_game_entries: Array = []
	all_player_game_entries.append_array(local_game_entries)
	all_player_game_entries.append_array(other_game_entries)

	# 3. Filter check: "Show Only My Games"
	var show_only_mine: bool = is_instance_valid(filter_my_games_btn) and filter_my_games_btn.button_pressed
	var display_entries: Array = []
	if show_only_mine:
		display_entries = local_game_entries
		games_count_label.text = str(display_entries.size()) + " Games (Mine)"
	else:
		display_entries = all_player_game_entries
		games_count_label.text = str(display_entries.size()) + " Multiworld Games"

	if is_instance_valid(dash_view_spoiler_btn):
		dash_view_spoiler_btn.visible = NetworkManager.seed_spoiler_name != ""
	if is_instance_valid(dash_download_seed_btn):
		dash_download_seed_btn.visible = NetworkManager.seed_zip_name != ""
	
	_update_dashboard_server_status()
	_update_checks_progress_ui()
		
	print("[Lobby] Rendering Play Dashboard: displaying %d cards (show_only_mine=%s, total_in_room=%d)" % [display_entries.size(), str(show_only_mine), all_player_game_entries.size()])
	if display_entries.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No games assigned in this multiworld session."
		empty_label.add_theme_color_override("font_color", COLOR_MUTED_TEXT)
		games_grid_container.add_child(empty_label)
		return
		
	for entry in display_entries:
		var card: PanelContainer = _create_game_grid_card(entry.game_name, entry.player_name, entry.is_local)
		games_grid_container.add_child(card)

func _get_formatted_ap_address() -> String:
	var url: String = NetworkManager.get_ap_server_url()
	if url.begins_with("wss://"):
		return url
	elif url.begins_with("ws://"):
		if "/ap/" in url:
			return url
		return url.replace("ws://", "")
	return url

func _update_dashboard_server_status() -> void:
	var archipelago_server_url: String = NetworkManager.get_ap_server_url()
	if archipelago_server_url != "":
		server_status_value.text = "Central Server: Active"
		var clean_address: String = _get_formatted_ap_address()
		server_port_value.text = clean_address
		if is_instance_valid(connection_dot):
			connection_dot.text = "●"
			connection_dot.add_theme_color_override("font_color", COLOR_SERVER_ACTIVE)
		if is_instance_valid(connection_badge):
			connection_badge.visible = true
		if is_instance_valid(copy_server_address_btn):
			copy_server_address_btn.visible = true
	else:
		server_status_value.text = "MultiServer: Initializing..."
		server_port_value.text = "Connecting..."
		if is_instance_valid(connection_dot):
			connection_dot.text = "○"
			connection_dot.add_theme_color_override("font_color", COLOR_SERVER_INITIALIZING)
		if is_instance_valid(copy_server_address_btn):
			copy_server_address_btn.visible = false

func _on_copy_server_address_pressed() -> void:
	var archipelago_server_url: String = NetworkManager.get_ap_server_url()
	var clean_address: String = _get_formatted_ap_address()
	if clean_address == "":
		clean_address = server_port_value.text
	if clean_address != "":
		DisplayServer.clipboard_set(clean_address)
		copy_server_address_btn.text = "Copied!"
		var tree = get_tree()
		if tree:
			await tree.create_timer(1.2).timeout
			if is_instance_valid(copy_server_address_btn):
				copy_server_address_btn.text = "Copy"

func _fetch_initial_checks() -> void:
	if NetworkManager.seed_status == "done" and NetworkManager.room_code != "":
		var res: Dictionary = await NetworkManager.fetch_http("/api/checks/" + NetworkManager.room_code)
		if not res.has("error") and res.get("data") is Dictionary:
			NetworkManager.checks = res.data
			_on_checks_updated(NetworkManager.checks)

func _on_checks_updated(checks_data: Dictionary) -> void:
	_update_checks_progress_ui()
	var games_checks: Dictionary = checks_data.get("games", {})
	for child in games_grid_container.get_children():
		if child.has_method("update_checks_progress") and "current_game_name" in child:
			var g_name: String = child.current_game_name
			var g_checks: Dictionary = games_checks.get(g_name, {})
			child.update_checks_progress(g_checks)

func _update_checks_progress_ui() -> void:
	var checks_data: Dictionary = NetworkManager.checks
	if checks_data.is_empty():
		checks_stats_label.text = "Checks: 0 / 0 (0%)"
		checks_progress_bar.value = 0
		return
		
	var total_checked: int = int(checks_data.get("totalChecked", 0))
	var total_locations: int = int(checks_data.get("totalLocations", 0))
	
	if total_locations > 0:
		var pct: float = (float(total_checked) / float(total_locations)) * 100.0
		checks_stats_label.text = "Checks: %d / %d (%.1f%%)" % [total_checked, total_locations, pct]
		checks_progress_bar.max_value = total_locations
		checks_progress_bar.value = total_checked
	else:
		checks_stats_label.text = "Checks: %d Completed" % total_checked
		checks_progress_bar.value = 0

func _create_game_grid_card(game_name: String, owner_name: String = "", is_local: bool = true) -> PanelContainer:
	var card = DashboardGameCardScene.instantiate()
	var total_games_count: int = local_selected_games.size() if not local_selected_games.is_empty() else 1
	var custom_tag_slot: String = launcher.get_preset(game_name).get("short_tag", "")
	var p_name: String = owner_name if owner_name != "" else NetworkManager.player_name
	var slot_name_str: String = YamlBuilder.get_slot_name(p_name, game_name, total_games_count, custom_tag_slot)
	var preset = launcher.get_preset(game_name)
	var status_info = launcher.get_game_launch_status(game_name)
	var checks_info = NetworkManager.checks.get("games", {}).get(game_name, {})
	
	print("[Lobby] Creating grid card for '%s' (Owner: '%s', Local: %s)" % [game_name, p_name, str(is_local)])
	card.setup(game_name, slot_name_str, preset, status_info, checks_info, p_name, is_local)
	if is_local:
		card.launch_pressed.connect(func(g_name: String):
			print("[Lobby] Grid card launch_pressed received for: '", g_name, "'")
			_check_and_launch_game(g_name)
		)
		card.change_path_pressed.connect(func(g_name: String):
			print("[Lobby] Grid card change_path_pressed received for: '", g_name, "'")
			_show_launch_overlay_direct(g_name)
		)
		card.tracker_pressed.connect(_on_poptracker_pressed)
	return card


# =====================================================================
#                      PLAYERS UI RENDERING
# =====================================================================

func _update_players_ui(players: Array = []) -> void:
	if players.is_empty():
		players = NetworkManager.players
		
	for child in player_list.get_children():
		child.queue_free()
		
	var sorted_players: Array = _get_sorted_players(players)
	_sync_local_player_selected_games(sorted_players)
	
	for player_info in sorted_players:
		var player_row: Control = _render_player_row(player_info)
		player_list.add_child(player_row)
		
	_update_seed_actions_ui(players)
	_update_server_address_display()
	_update_lock_status_display(players)
	_update_hosting_mode_ui()
	_sync_needed_custom_worlds()
	
	if NetworkManager.seed_status == "done":
		if is_instance_valid(status_label):
			status_label.visible = false
		active_seed_badge.visible = true
		view_switcher_hbox.visible = true
		if not _auto_switched_to_play:
			_auto_switched_to_play = true
			_switch_view_mode(VIEW_MODE_PLAY)
	else:
		if is_instance_valid(status_label):
			status_label.visible = true
		active_seed_badge.visible = false
		view_switcher_hbox.visible = false
		_auto_switched_to_play = false

func _update_server_address_display() -> void:
	var archipelago_server_url: String = NetworkManager.get_ap_server_url()
	if archipelago_server_url != "":
		server_label.text = "Server: " + archipelago_server_url
		server_label.add_theme_color_override("font_color", COLOR_SERVER_ACTIVE)
	elif NetworkManager.seed_status == "done":
		server_label.text = "Server: Initializing..."
		server_label.add_theme_color_override("font_color", COLOR_SERVER_INITIALIZING)
	else:
		server_label.text = ""

func _update_lock_status_display(players: Array) -> void:
	var is_room_host: bool = false
	for p in players:
		if p.get("userId") == NetworkManager.user_id:
			is_room_host = p.get("isHost", false)
			break
			
	if NetworkManager.locked_by != "":
		lock_status_label.text = "Session active: Locked by " + NetworkManager.locked_by
		lock_status_label.visible = true
		force_unlock_btn.visible = is_room_host
		if is_instance_valid(close_room_btn):
			close_room_btn.visible = false
	else:
		lock_status_label.visible = false
		force_unlock_btn.visible = false
		if is_instance_valid(close_room_btn):
			close_room_btn.visible = is_room_host

	if is_instance_valid(host_tools_btn):
		host_tools_btn.visible = is_room_host and NetworkManager.seed_status == "done"

func _on_host_tools_pressed() -> void:
	host_tools_modal.open()

func _update_hosting_mode_ui() -> void:
	if not is_instance_valid(hosting_mode_option):
		return
	var is_host := _is_local_player_host()
	hosting_mode_option.visible = is_host and NetworkManager.seed_status != "done"
	hosting_mode_option.disabled = not is_host or NetworkManager.seed_status != "idle"
	if NetworkManager.hosting_mode == "archipelago_gg":
		hosting_mode_option.select(1)
	else:
		hosting_mode_option.select(0)

func _load_hosting_mode() -> void:
	if NetworkManager.room_code == "":
		return
	var response: Dictionary = await NetworkManager.fetch_http("/api/rooms/" + NetworkManager.room_code.uri_encode() + "/hosting")
	var data = response.get("data")
	if data is Dictionary:
		var hosting_mode_value = data.get("hosting_mode")
		NetworkManager.hosting_mode = hosting_mode_value if hosting_mode_value is String else "wayfinder_backend"
		var hosting_status_value = data.get("hosting_status")
		NetworkManager.hosting_status = hosting_status_value if hosting_status_value is String else ""
		var hosting_room_url_value = data.get("hosting_room_url")
		NetworkManager.hosting_room_url = hosting_room_url_value if hosting_room_url_value is String else ""
		_update_hosting_mode_ui()

func _on_hosting_mode_selected(index: int) -> void:
	var mode := "archipelago_gg" if index == 1 else "wayfinder_backend"
	hosting_mode_option.disabled = true
	var result: Dictionary = await NetworkManager.set_hosting_mode(mode)
	if result.has("error"):
		_update_hosting_mode_ui()
		status_label.text = "Hosting selection failed: " + str(result.error)
		return
	NetworkManager.hosting_mode = mode

func _get_sorted_players(players: Array) -> Array:
	var sorted_players: Array = []
	var other_players: Array = []
	for player in players:
		if player.get("userId") == NetworkManager.user_id:
			sorted_players.append(player)
		else:
			other_players.append(player)
	sorted_players.append_array(other_players)
	return sorted_players

func _sync_local_player_selected_games(sorted_players: Array) -> void:
	for player in sorted_players:
		if player.get("userId") == NetworkManager.user_id:
			var remote_games: Array = player.get("games", [])
			if local_selected_games != remote_games:
				local_selected_games = remote_games.duplicate()
				for game_name in local_selected_games:
					_prepopulate_default_options(game_name)
			break

func _render_player_row(player_info: Dictionary) -> Control:
	var card = PlayerCardScene.instantiate()
	card.setup(player_info, NetworkManager.user_id, _is_local_player_host())
	card.game_clicked.connect(func(g_name):
		if NetworkManager.seed_status == "done":
			return
		_open_config_popup(g_name)
	)
	card.add_game_clicked.connect(_on_plus_pressed)
	card.kick_clicked.connect(_show_kick_confirm_dialog)
	return card


# =====================================================================
#                      ADD GAME & OPTIONS MODALS
# =====================================================================

func _on_plus_pressed() -> void:
	var games_list: Array = all_games
	if games_list.is_empty() and not launcher.launcher_presets.is_empty():
		games_list = launcher.launcher_presets.keys()
	add_game_modal.open(games_list, _is_game_supported, local_selected_games)

func _is_game_supported(game_name: String) -> bool:
	if GuidedSetupRegistry.has_guided_setup(game_name):
		return true
	var slug: String = GuidedSetupRegistry.get_game_slug(game_name)
	if FileAccess.file_exists("user://cache/games/" + slug + "/guided_setup.json"):
		return true
	if launcher.has_curated_preset(game_name):
		return true
	return false

func _on_game_card_selected(game_name: String) -> void:
	if not local_selected_games.has(game_name):
		local_selected_games.append(game_name)
		await _prepopulate_default_options(game_name)
		_sync_state_to_server()
	_open_config_popup(game_name)

func _open_config_popup(game_name: String) -> void:
	active_config_game = game_name
	config_modal.set_loading(true)
	config_modal.open(game_name, {}, config_states.get(game_name, {}), use_guided_setup_mode.get(game_name, true))
	await _ensure_remote_guided_setup(game_name)
	var schema_dict: Dictionary = await _get_options_schema(game_name)
	config_modal.set_loading(false)
	config_modal.open(game_name, schema_dict, config_states.get(game_name, {}), use_guided_setup_mode.get(game_name, true))

func _ensure_remote_guided_setup(game_name: String) -> void:
	if GuidedSetupRegistry.has_guided_setup(game_name):
		return
	var slug: String = GuidedSetupRegistry.get_game_slug(game_name)
	var cache_dir: String = "user://cache/games/" + slug
	var cache_path: String = cache_dir + "/guided_setup.json"
	
	var res: Dictionary = await NetworkManager.fetch_http("/api/games/" + slug + "/guided-setup")
	if not res.has("error") and res.get("data") is Dictionary:
		DirAccess.make_dir_recursive_absolute(cache_dir)
		var fa: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
		if fa:
			fa.store_string(JSON.stringify(res.data, "  "))
			fa.close()
			print("[Lobby] Cached remote guided setup for: ", game_name)

func _prepopulate_default_options(game_name: String) -> void:
	if not config_states.has(game_name):
		config_states[game_name] = {}
	var schema_dict: Dictionary = await _get_options_schema(game_name)
	var options_list: Array = schema_dict.get("options", [])
	for option_def in options_list:
		var opt_name: String = option_def.get("name", "")
		if not config_states[game_name].has(opt_name):
			config_states[game_name][opt_name] = option_def.get("default")

func _get_options_schema(game_name: String) -> Dictionary:
	if options_cache.has(game_name):
		return options_cache[game_name]
	var endpoint: String = "/api/options/" + game_name.uri_encode()
	var response: Dictionary = await NetworkManager.fetch_http(endpoint)
	if not response.has("error") and response.data is Dictionary:
		options_cache[game_name] = response.data
		return response.data
	return {}

func _on_config_modal_saved(game_name: String, config: Dictionary) -> void:
	config_states[game_name] = config
	_sync_state_to_server()

func _on_config_modal_removed(game_name: String) -> void:
	if game_name != "":
		local_selected_games.erase(game_name)
		config_states.erase(game_name)
	_sync_state_to_server()

func _on_config_save_pressed() -> void:
	config_modal.close()
	_sync_state_to_server()

func _on_config_remove_pressed() -> void:
	if active_config_game != "":
		local_selected_games.erase(active_config_game)
		config_states.erase(active_config_game)
	config_modal.close()
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
#                      NETWORK TEARDOWN & CLEANUP
# =====================================================================

func _on_connection_lost() -> void:
	status_label.text = "Connection Lost!"
	status_label.add_theme_color_override("font_color", COLOR_ERROR_RED)
	await get_tree().create_timer(2.0).timeout
	_go_to_main_menu()

func _disconnect_network_signals() -> void:
	if NetworkManager.generation_log_received.is_connected(_on_generation_log_received):
		NetworkManager.generation_log_received.disconnect(_on_generation_log_received)
	if NetworkManager.room_state_updated.is_connected(_update_players_ui):
		NetworkManager.room_state_updated.disconnect(_update_players_ui)
	if NetworkManager.checks_updated.is_connected(_on_checks_updated):
		NetworkManager.checks_updated.disconnect(_on_checks_updated)
	if NetworkManager.connection_closed.is_connected(_on_connection_lost):
		NetworkManager.connection_closed.disconnect(_on_connection_lost)

func _exit_tree() -> void:
	_disconnect_network_signals()

func _go_to_main_menu() -> void:
	_disconnect_network_signals()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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
			generating_overlay.close()
			download_seed_btn.visible = false
			view_spoiler_btn.visible = false
			start_game_btn.visible = is_host_player
			start_game_btn.disabled = not all_players_has_games or NetworkManager.locked_by != ""
		"generating":
			generating_overlay.open("Generating Archipelago Multiworld...")
			download_seed_btn.visible = false
			view_spoiler_btn.visible = false
			start_game_btn.visible = false
		"done":
			generating_overlay.close()
			start_game_btn.visible = false
			var has_seed: bool = (NetworkManager.seed_zip_name != "")
			var has_spoiler: bool = (NetworkManager.seed_spoiler_name != "")
			if is_instance_valid(seed_ready_card):
				seed_ready_card.visible = has_seed
			if is_instance_valid(setup_download_seed_btn):
				setup_download_seed_btn.visible = has_seed
			if is_instance_valid(setup_view_spoiler_btn):
				setup_view_spoiler_btn.visible = has_spoiler
			if current_view_mode == VIEW_MODE_SETUP:
				download_seed_btn.visible = has_seed
				view_spoiler_btn.visible = has_spoiler
			else:
				download_seed_btn.visible = false
				view_spoiler_btn.visible = false

func _on_start_game_pressed() -> void:
	generating_overlay.open("Generating Archipelago Multiworld...")
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

func _on_poptracker_pressed(game_name: String) -> void:
	if game_name == "":
		return
	var server_url := NetworkManager.get_ap_server_url()
	if server_url == "":
		status_label.text = "The Archipelago server address is not ready yet."
		return
	var total_games: int = maxi(local_selected_games.size(), 1)
	var preset := launcher.get_preset(game_name)
	var slot_name := YamlBuilder.get_slot_name(
		NetworkManager.player_name,
		game_name,
		total_games,
		str(preset.get("short_tag", ""))
	)
	launch_title.text = "Opening PopTracker"
	launch_instructions.text = "Installing and preparing the Metroid Fusion tracker pack..."
	_tracker_operation_active = true
	path_section.visible = false
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = false
	launch_download_btn.visible = false
	launch_cancel_btn.visible = true
	launch_overlay.show_download_card("Preparing PopTracker")
	launch_overlay.open()
	launcher.open_poptracker(self, game_name, server_url, slot_name, func(ok: bool, value: String):
		if ok:
			launch_overlay.close()
			_tracker_operation_active = false
			status_label.text = "PopTracker opened for " + game_name + "."
		else:
			_tracker_operation_active = false
			launch_title.text = "PopTracker unavailable"
			launch_instructions.text = "[color=#f87171]" + value + "[/color]"
			launch_overlay.open()
	)

func _on_generation_log_received(line: String) -> void:
	generating_overlay.add_log(line)
	if line.to_lower().contains("uploading"):
		generating_overlay.set_status("Uploading seed to Archipelago.gg...")
	elif line.to_lower().contains("room ready"):
		generating_overlay.set_status("Archipelago.gg room ready. Finalizing lobby...")
	elif line.to_lower().contains("room created"):
		generating_overlay.set_status("Archipelago.gg room created. Starting hosted server...")


# =====================================================================
#                     CLOUD SAVES DELEGATION
# =====================================================================

func _on_checkout_save_pressed() -> void:
	SaveManager.checkout_save(self, NetworkManager.room_code, NetworkManager.user_id, checkout_save_btn, func(msg): status_label.text = msg)

func _on_checkin_save_pressed() -> void:
	SaveManager.checkin_save(self, NetworkManager.room_code, NetworkManager.user_id, checkin_save_btn, func(msg): status_label.text = msg)

func _on_force_unlock_pressed() -> void:
	SaveManager.force_unlock_session(self, NetworkManager.room_code, NetworkManager.user_id, force_unlock_btn, func(msg): status_label.text = msg)


# =====================================================================
#                    GAME LAUNCHER ORCHESTRATION
# =====================================================================

func _on_launch_game_pressed() -> void:
	if local_selected_games.is_empty():
		return
	if local_selected_games.size() == 1:
		_check_and_launch_game(local_selected_games[0])
	else:
		_show_multi_game_selector(local_selected_games)

func _check_and_launch_game(game_name: String) -> void:
	print("[Lobby] User initiated launch for game: '", game_name, "'")
	_show_launch_preparing_overlay(game_name)
	launcher.launch_game(self, game_name)

func _show_launch_preparing_overlay(game_name: String) -> void:
	_active_launch_game = game_name
	_active_launch_preset = launcher.get_preset(game_name)
	launch_overlay.set_modding_status("Initializing launch environment for " + game_name + "...", 5)

func _on_launcher_status_updated(stage: int, message: String, progress_pct: float) -> void:
	launch_overlay.set_modding_status(message, int(progress_pct))

func _on_launcher_prompt_file_selection(title_text: String, instructions_text: String, filters: PackedStringArray, callback: Callable) -> void:
	_active_prompt_callback = callback
	launch_title.text = title_text
	launch_instructions.text = instructions_text
	path_section.visible = true
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = true
	launch_confirm_btn.text = "Confirm Selection"
	launch_download_btn.visible = false
	launch_path_input.text = launcher.paths_config.get(_active_launch_game, "")
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	launch_overlay.open()

func _on_launcher_prompt_tool_installation(tool_name: String, download_url: String, subfolder: String, target_file: String, callback: Callable) -> void:
	launch_title.text = "Installing " + tool_name
	launch_instructions.text = "Wayfinder is automatically downloading and configuring " + tool_name + "..."
	path_section.visible = false
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = false
	launch_download_btn.visible = false
	launch_overlay.show_download_card("Installing " + tool_name)
	launch_overlay.open()
	launcher.ensure_tool_installed_or_download(self, tool_name, download_url, subfolder, target_file, callback)

func _on_launcher_completed(game_name: String, pid: int) -> void:
	print("[Lobby] Launch completed for ", game_name, " (PID: ", pid, ")")
	launch_overlay.close()
	_render_play_dashboard()

func _on_launcher_failed(game_name: String, error_msg: String) -> void:
	print("[Lobby Error] Launch failed for ", game_name, ": ", error_msg)
	Updater.log_message("ERROR", "Launch failed for " + game_name + ": " + error_msg)
	launch_title.text = "Launch Failed: " + game_name
	launch_instructions.text = "[color=#f87171]" + error_msg + "[/color]\n\nPlease check your game files or settings."
	path_section.visible = false
	emulator_path_section.visible = false
	launch_confirm_btn.visible = false
	launch_download_btn.visible = false
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	if launch_overlay.has_method("show_error_actions"):
		launch_overlay.show_error_actions(error_msg)
	launch_overlay.open()

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
		selection_btn.pressed.connect(_select_game_from_list.bind(game_name))
		game_selection_buttons.add_child(selection_btn)
		
	game_selection_section.visible = true
	launch_overlay.open()

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
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	_active_launch_game = game_name
	_active_launch_preset = launcher.get_preset(game_name)
	var support_tier_level: int = _active_launch_preset.get("support_tier", 2)
	launch_title.text = "Setup: " + game_name + " [Tier " + str(support_tier_level) + "]"
	
	var launch_mode: String = _active_launch_preset.get("launch_mode", "")
	var required_rom: String = _active_launch_preset.get("required_rom", "")
	var is_rom_game: bool = (required_rom != "" or launch_mode == "patch_rom" or _active_launch_preset.get("is_rom", false))
	
	var default_instructions: String = _active_launch_preset.get("install_instructions", "")
	if default_instructions == "":
		if is_rom_game:
			default_instructions = "Select your clean base ROM file (" + required_rom + ") to configure launch. Wayfinder will handle Archipelago tools and emulator configuration automatically."
		else:
			default_instructions = "Select your installed game executable to configure launch."
	
	var total_games_count: int = local_selected_games.size() if not local_selected_games.is_empty() else 1
	var custom_tag_instr: String = launcher.get_preset(game_name).get("short_tag", "")
	var slot_name_str: String = YamlBuilder.get_slot_name(NetworkManager.player_name, game_name, total_games_count, custom_tag_instr)
	var slot_prefix: String = "[color=#6ee7b7]• Multiworld Slot:[/color] [b]" + slot_name_str + "[/b]\n\n"
	
	var stored_path: String = launcher.get_saved_path(game_name, _active_launch_preset)
	if is_rom_game and required_rom != "" and stored_path.to_lower().ends_with(".exe"):
		stored_path = ""
		
	if is_rom_game and required_rom != "":
		var rom_label: String = required_rom
		path_label.text = "Base ROM File (" + rom_label + "):"
		launch_path_input.placeholder_text = "Select path to " + rom_label + "..."
		if stored_path == "":
			stored_path = launcher.find_existing_base_rom(required_rom)
			if stored_path != "":
				launcher.paths_config[game_name] = stored_path
				launcher.save_paths_config()
	else:
		path_label.text = "Executable Path (" + _active_launch_preset.get("default_executable", "game.exe") + "):"
		launch_path_input.placeholder_text = "Select path to game executable..."
		if stored_path == "":
			var auto_detected: String = launcher.find_game_executable(_active_launch_preset.get("default_executable", ""), _active_launch_preset.get("common_folders", []))
			if auto_detected != "":
				stored_path = auto_detected
				launcher.paths_config[game_name] = stored_path
				launcher.save_paths_config()
				
	launch_path_input.text = stored_path
	
	# Check if download catalog has an entry (ROM or PC game)
	var dl_identifier: String = required_rom if required_rom != "" else game_name
	var rom_download_entry: Dictionary = launcher.get_rom_download_entry(dl_identifier)
	if rom_download_entry.is_empty():
		rom_download_entry = launcher.get_rom_download_entry(game_name)
	if not rom_download_entry.is_empty():
		launch_download_btn.visible = true
		var dl_label: String = "Base ROM" if is_rom_game else "Game"
		launch_download_btn.text = "📥 Download " + dl_label + " Automatically"
		default_instructions = "Setup required for " + game_name + ".\n\nOption 1: Click Download " + dl_label + " Automatically below.\nOption 2: Browse to locate your existing " + ("base ROM file." if is_rom_game else "game executable.")
	else:
		launch_download_btn.visible = false
		if is_rom_game:
			default_instructions = "Please Browse to locate your existing clean base ROM file (" + (required_rom if required_rom != "" else "ROM") + ")."
		else:
			default_instructions = "Please Browse to locate your existing game executable."
		
	if launch_mode == "patch_rom":
		emulator_path_section.visible = true
		var emulator_preset: String = _active_launch_preset.get("emulator", "snes9x")
		emulator_path_label.text = "Emulator (" + emulator_preset.to_upper() + "):"
		var stored_emu_path: String = launcher.paths_config.get(emulator_preset, "")
		if stored_emu_path == "":
			var default_emu_exe: String = emulator_preset + ".exe"
			var auto_emu: String = launcher.find_game_executable(default_emu_exe, [emulator_preset, "emulators"])
			if auto_emu != "":
				stored_emu_path = auto_emu
				launcher.paths_config[emulator_preset] = stored_emu_path
				launcher.save_paths_config()
		launch_emulator_path_input.text = stored_emu_path
	else:
		emulator_path_section.visible = false
		
	var steam_btn = launch_overlay.get_node_or_null("%LaunchSteamBtn")
	var recheck_btn = launch_overlay.get_node_or_null("%LaunchRecheckBtn")
	if steam_btn:
		steam_btn.visible = false
	if recheck_btn:
		recheck_btn.visible = false

	if _active_launch_preset.has("required_steam_beta"):
		var steam_id: String = str(_active_launch_preset.get("steam_appid", "")).strip_edges()
		var beta_cfg: Dictionary = _active_launch_preset.get("required_steam_beta", {})
		if steam_id != "" and not beta_cfg.is_empty():
			var steam_res: Dictionary = LauncherUtils.check_steam_beta_status(stored_path, steam_id, beta_cfg, game_name)
			if steam_res.get("needs_downgrade", false):
				if steam_btn:
					steam_btn.visible = true
					steam_btn.text = "🎮 Open Steam Game Properties (Betas Tab)"
				if recheck_btn:
					recheck_btn.visible = true
					recheck_btn.text = "🔄 Re-check Steam Beta Status"
				default_instructions = steam_res.get("guidance_text", "")
				launch_confirm_btn.text = "Select Steam Beta First"
			else:
				if _active_launch_preset.has("mod_activation"):
					var act_cfg: Dictionary = _active_launch_preset.get("mod_activation", {})
					var act_info: Dictionary = LauncherUtils.check_mod_activation_status(stored_path, act_cfg)
					if act_info.get("state", "") == "disabled_in_lumafly":
						default_instructions = "[color=#34d399]✔ Steam Beta branch verified![/color]\n[color=#38bdf8]• Dormant modded files detected[/color]\nWayfinder will automatically activate your mod files upon launch."
				launch_confirm_btn.text = "Confirm & Launch"

	launch_instructions.text = slot_prefix + (instructions_override if instructions_override != "" else default_instructions)
	launch_overlay.open()

func _on_launch_steam_pressed() -> void:
	var steam_id: String = str(_active_launch_preset.get("steam_appid", "367520")).strip_edges()
	if steam_id == "":
		steam_id = "367520"
	print("[Lobby] Opening Steam properties for App ID: ", steam_id)
	OS.shell_open("steam://gameproperties/" + steam_id)

func _on_launch_recheck_pressed() -> void:
	if _active_launch_game != "":
		print("[Lobby] Re-checking prerequisites for: ", _active_launch_game)
		_setup_game_details_in_overlay(_active_launch_game)

func _on_launch_download_pressed() -> void:
	if _active_launch_game == "":
		return
	var required_rom: String = _active_launch_preset.get("required_rom", "")
	var launch_mode: String = _active_launch_preset.get("launch_mode", "")
	var is_rom_game: bool = (required_rom != "" or launch_mode == "patch_rom" or _active_launch_preset.get("is_rom", false))
	launch_download_btn.disabled = true
	
	if is_rom_game:
		var rom_key: String = required_rom if required_rom != "" else _active_launch_game
		launch_overlay.show_download_card("Downloading Base ROM (" + rom_key + ")")
		launcher.ensure_rom_exists_or_download(self, rom_key, func(success: bool, result_path_or_msg: String):
			launch_download_btn.disabled = false
			if success:
				launch_path_input.text = result_path_or_msg
				launcher.paths_config[_active_launch_game] = result_path_or_msg
				launcher.save_paths_config()
				_continue_launch_confirm(result_path_or_msg)
			else:
				_on_launcher_failed(_active_launch_game, result_path_or_msg)
		)
	else:
		launch_overlay.show_download_card("Downloading Game Files (" + _active_launch_game + ")")
		launcher.ensure_pc_game_installed(self, _active_launch_game, _active_launch_preset, func(success: bool, result_path_or_msg: String):
			launch_download_btn.disabled = false
			if success:
				launch_path_input.text = result_path_or_msg
				launcher.paths_config[_active_launch_game] = result_path_or_msg
				launcher.save_paths_config()
				_continue_launch_confirm(result_path_or_msg)
			else:
				_on_launcher_failed(_active_launch_game, result_path_or_msg)
		)

func _open_file_browse(target: String) -> void:
	launch_overlay._open_file_browse(target)

func _on_file_selected(selected_path_str: String) -> void:
	launch_overlay._on_file_selected(selected_path_str)

func _on_launch_confirm_pressed() -> void:
	var game_path_str: String = launch_path_input.text.strip_edges()
	var launch_mode_str: String = _active_launch_preset.get("launch_mode", "")
	
	if launch_mode_str == "patch_rom":
		var emulator_preset_key: String = _active_launch_preset.get("emulator", "snes9x")
		var emu_path_str: String = launch_emulator_path_input.text.strip_edges()
		if emu_path_str != "" and FileAccess.file_exists(emu_path_str):
			launcher.paths_config[emulator_preset_key] = emu_path_str
			launcher.save_paths_config()
			
	if _active_prompt_callback.is_valid():
		var prompt_cb: Callable = _active_prompt_callback
		_active_prompt_callback = Callable()
		launch_overlay.close()
		prompt_cb.call(true, game_path_str)
		return
		
	if game_path_str == "" or not FileAccess.file_exists(game_path_str):
		launch_instructions.text = "[color=#f87171]Selected file does not exist. Please browse to a valid file.[/color]"
		return
		
	launcher.paths_config[_active_launch_game] = game_path_str
	launcher.save_paths_config()
	_continue_launch_confirm(game_path_str)

func _continue_launch_confirm(game_path_str: String) -> void:
	var g_name: String = _active_launch_game
	launch_overlay.close()
	_check_and_launch_game(g_name)
