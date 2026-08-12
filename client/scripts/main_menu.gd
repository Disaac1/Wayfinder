extends Control

@onready var name_input: LineEdit = %NameInput
@onready var server_input: LineEdit = %ServerInput
@onready var code_input: LineEdit = %CodeInput
@onready var create_btn: Button = %CreateBtn
@onready var join_btn: Button = %JoinBtn
@onready var error_label: Label = %ErrorLabel
@onready var recent_lobbies_container: VBoxContainer = %RecentLobbiesContainer

const SETTINGS_PATH = "user://settings.json"

var pending_action: String = "" # "create" or "join"
var pending_user_id: String = ""
var recent_lobbies: Array = []

func _ready() -> void:
	# Clear error label
	error_label.text = ""
	
	# Connect local button signals
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	
	# Connect NetworkManager signals
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_closed.connect(_on_connection_closed)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.error_received.connect(_on_error_received)
	
	# Load settings & fetch active server rooms
	_load_local_settings()
	_fetch_server_rooms_and_update_ui()

func _fetch_server_rooms_and_update_ui() -> void:
	var response: Dictionary = await NetworkManager.fetch_http("/api/rooms")
	var server_rooms_map: Dictionary = {}
	if not response.has("error"):
		var server_rooms_list: Array = response.get("data", {}).get("rooms", [])
		for r in server_rooms_list:
			server_rooms_map[r.get("code", "")] = r

		# Purge any local recent lobbies that no longer exist on the server
		var cleaned_recent_lobbies: Array = []
		for lobby in recent_lobbies:
			var code: String = lobby.get("room_code", "")
			if server_rooms_map.has(code):
				cleaned_recent_lobbies.append(lobby)

		if cleaned_recent_lobbies.size() != recent_lobbies.size():
			recent_lobbies = cleaned_recent_lobbies
			_save_all_settings()

	_update_recent_lobbies_ui(recent_lobbies, server_rooms_map)

func _on_create_pressed() -> void:
	if not _validate_name():
		return
	
	pending_user_id = "" # Fresh creation
	pending_action = "create"
	error_label.text = "Connecting..."
	_connect_network()

func _on_join_pressed() -> void:
	if not _validate_name():
		return
		
	var code = code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		error_label.text = "Room code must be exactly 6 characters"
		return
		
	# Check if we have a saved user_id for this room code and player name to enable resume takeover
	pending_user_id = ""
	for lobby in recent_lobbies:
		if lobby.get("room_code", "") == code and lobby.get("player_name", "") == name_input.text.strip_edges():
			pending_user_id = lobby.get("user_id", "")
			break
			
	pending_action = "join"
	error_label.text = "Connecting..."
	_connect_network()

func _validate_name() -> bool:
	var name_text = name_input.text.strip_edges()
	if name_text == "":
		error_label.text = "Player name cannot be empty"
		return false
	return true

func _connect_network() -> void:
	var url = server_input.text.strip_edges()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		error_label.text = "Server address must start with ws:// or wss://"
		return
		
	var err = NetworkManager.connect_to_server(url)
	if err != OK:
		error_label.text = "Failed to connect to server. Error code: " + str(err)

func _on_connected_to_server() -> void:
	var name_text = name_input.text.strip_edges()
	if pending_action == "create":
		error_label.text = "Creating room..."
		NetworkManager.create_room(name_text)
	elif pending_action == "join":
		var code = code_input.text.strip_edges().to_upper()
		if pending_user_id != "":
			error_label.text = "Reconnecting as " + name_text + "..."
			NetworkManager.reconnect_session(pending_user_id, code, name_text)
		else:
			error_label.text = "Joining room " + code + "..."
			NetworkManager.join_room(code, name_text)

func _on_connection_closed() -> void:
	error_label.text = "Connection closed by server"
	pending_action = ""

func _on_room_created(room_code: String, user_id: String) -> void:
	_save_recent_lobby(room_code, name_input.text.strip_edges(), user_id)
	_go_to_lobby()

func _on_room_joined(room_code: String, user_id: String, _players: Array) -> void:
	_save_recent_lobby(room_code, name_input.text.strip_edges(), user_id)
	_go_to_lobby()

func _on_error_received(message: String) -> void:
	error_label.text = "Error: " + message
	NetworkManager.disconnect_from_server()
	pending_action = ""

func _go_to_lobby() -> void:
	# Disconnect local signals first to avoid leaks
	NetworkManager.connected_to_server.disconnect(_on_connected_to_server)
	NetworkManager.connection_closed.disconnect(_on_connection_closed)
	NetworkManager.room_created.disconnect(_on_room_created)
	NetworkManager.room_joined.disconnect(_on_room_joined)
	NetworkManager.error_received.disconnect(_on_error_received)
	
	# Transition scene
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

# --- Local Settings Saving / Loading ---

func _load_local_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
		
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_text) == OK:
		var data = json.get_data()
		if data.has("player_name"):
			name_input.text = data.get("player_name", "")
		if data.has("recent_lobbies"):
			recent_lobbies = data.get("recent_lobbies", [])

func _save_recent_lobby(room_code: String, player_name: String, user_id: String) -> void:
	var list = recent_lobbies.duplicate()
	var new_list = []
	for lobby in list:
		if lobby.get("room_code", "") != room_code:
			new_list.append(lobby)
			
	new_list.insert(0, {
		"room_code": room_code,
		"player_name": player_name,
		"user_id": user_id,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	if new_list.size() > 5:
		new_list.resize(5)
		
	recent_lobbies = new_list
	_save_all_settings()

func _save_all_settings() -> void:
	var data = {
		"player_name": name_input.text.strip_edges(),
		"recent_lobbies": recent_lobbies
	}
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _update_recent_lobbies_ui(lobbies: Array, server_rooms_map: Dictionary) -> void:
	for child in recent_lobbies_container.get_children():
		child.queue_free()
		
	var displayed_codes: Dictionary = {}
	var items_to_render: Array = []

	# First add local recent lobbies (if still valid on server or if server map is empty)
	for lobby in lobbies:
		var code: String = lobby.get("room_code", "")
		if code != "" and not displayed_codes.has(code):
			displayed_codes[code] = true
			items_to_render.append({
				"code": code,
				"player_name": lobby.get("player_name", ""),
				"user_id": lobby.get("user_id", ""),
				"server_info": server_rooms_map.get(code, {})
			})

	# Then add active server rooms not in local history
	for code in server_rooms_map.keys():
		if not displayed_codes.has(code):
			displayed_codes[code] = true
			items_to_render.append({
				"code": code,
				"player_name": "",
				"user_id": "",
				"server_info": server_rooms_map.get(code, {})
			})

	if items_to_render.size() == 0:
		var lbl = Label.new()
		lbl.text = "No active server lobbies"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		lbl.add_theme_font_size_override("font_size", 12)
		recent_lobbies_container.add_child(lbl)
		return
		
	for item in items_to_render:
		var row: HBoxContainer = _create_lobby_row(item)
		recent_lobbies_container.add_child(row)

func _create_lobby_row(item: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var code: String = item.get("code", "")
	var name_val: String = item.get("player_name", "")
	var uid: String = item.get("user_id", "")
	var s_info: Dictionary = item.get("server_info", {})

	var host_name: String = s_info.get("hostName", name_val)
	var count: int = s_info.get("playerCount", 1)
	var seed_status: String = s_info.get("seedStatus", "idle")

	var btn: Button = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)

	var status_text: String = " [RUNNING]" if seed_status == "done" else ""
	if name_val != "":
		btn.text = "Room " + code + status_text + " (" + host_name + ")"
	else:
		btn.text = "Room " + code + status_text + " (" + host_name + ", " + str(count) + "P)"

	btn.pressed.connect(func():
		code_input.text = code
		if name_val != "":
			name_input.text = name_val
		pending_user_id = uid
		_on_join_pressed()
	)
	row.add_child(btn)

	var del_btn: Button = Button.new()
	del_btn.text = "X"
	del_btn.tooltip_text = "Delete room from server"
	del_btn.custom_minimum_size = Vector2(28, 0)
	del_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	del_btn.pressed.connect(func():
		_on_delete_room_pressed(code)
	)
	row.add_child(del_btn)

	return row

func _on_delete_room_pressed(room_code: String) -> void:
	print("[Main Menu] Deleting room from server: ", room_code)
	var new_recent: Array = []
	for l in recent_lobbies:
		if l.get("room_code", "") != room_code:
			new_recent.append(l)
	recent_lobbies = new_recent
	_save_all_settings()

	var res: Dictionary = await NetworkManager.delete_room(room_code)
	if res.has("error"):
		error_label.text = "Failed to delete room: " + str(res.error)
	else:
		error_label.text = "Room " + room_code + " deleted."

	_fetch_server_rooms_and_update_ui()

