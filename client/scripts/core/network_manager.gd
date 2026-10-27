extends Node

signal connected_to_server
signal connection_closed
signal room_created(room_code: String, user_id: String)
signal room_joined(room_code: String, user_id: String, players: Array)
signal room_state_updated(players: Array)
signal error_received(message: String)
signal generation_log_received(line: String)
signal kicked_from_room(message: String)
signal room_closed(message: String)
signal checks_updated(checks_data: Dictionary)
signal server_log_received(line: String)

var socket: WebSocketPeer = WebSocketPeer.new()
var is_connected: bool = false
var _ping_timer: float = 0.0
const PING_INTERVAL: float = 20.0
var is_reconnecting: bool = false

var server_url: String = "wss://wayfinder.disaac1.com"
var player_name: String = ""
var room_code: String = ""
var user_id: String = ""
var players: Array = []
var seed_status: String = "idle"
var seed_zip_name: String = ""
var seed_spoiler_name: String = ""
var tunnel_url: String = ""
var locked_by: String = ""
var checks: Dictionary = {}
var hosting_mode: String = "wayfinder_backend"
var hosting_status: String = ""
var hosting_room_url: String = ""
var hosting_server_url: String = ""

func _enter_tree() -> void:
	# Mount verified self-updating patches before the root scene loads
	Updater.bootstrap_early_updates()

func _ready() -> void:
	# Disable processing until we actively initiate a connection
	set_process(false)

func connect_to_server(url: String = server_url) -> Error:
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	server_url = url
	socket = WebSocketPeer.new() # Instantiate a new peer
	var err = socket.connect_to_url(url)
	if err == OK:
		is_connected = false
		set_process(true)
		print("Connecting to WebSocket server: ", url)
	else:
		print("Failed to start connection attempt to: ", url)
	return err

func disconnect_from_server() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close(1000, "Leaving room")
	is_connected = false
	set_process(false)
	print("Disconnected from server.")

func _process(delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			_ping_timer = 0.0
			connected_to_server.emit()
			print("WebSocket connection fully established.")
			
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			send_message({ "type": "ping" })

		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var text = packet.get_string_from_utf8()
			_handle_raw_message(text)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			print("WebSocket connection closed by remote peer.")
			if room_code != "" and user_id != "":
				_attempt_auto_reconnect()
			else:
				connection_closed.emit()
				set_process(false)
		elif not is_reconnecting:
			# A failed initial connection also reaches CLOSED, but never
			# transitions through STATE_OPEN to set is_connected.
			connection_closed.emit()
			set_process(false)
			
	elif state == WebSocketPeer.STATE_CONNECTING:
		pass
	else:
		# Error or state is none
		pass

func _attempt_auto_reconnect() -> void:
	if is_reconnecting:
		return
	is_reconnecting = true
	print("[NetworkManager] Connection dropped unexpectedly. Attempting automatic session recovery in 2 seconds...")
	await get_tree().create_timer(2.0).timeout
	if room_code == "" or user_id == "":
		is_reconnecting = false
		return
	
	var err = connect_to_server(server_url)
	if err == OK:
		var connected_ok = false
		for i in range(50):
			await get_tree().create_timer(0.1).timeout
			if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
				connected_ok = true
				break
			elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				break
		if connected_ok:
			print("[NetworkManager] Re-established connection! Resuming room session ", room_code)
			reconnect_session(user_id, room_code, player_name)
			is_reconnecting = false
			return

	print("[NetworkManager] Auto-reconnect failed. Notifying listeners.")
	is_reconnecting = false
	connection_closed.emit()
	set_process(false)

func _handle_raw_message(text: String) -> void:
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("JSON Parse Error: ", json.get_error_message(), " at ", text)
		return
		
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		print("Received non-dictionary message: ", data)
		return
		
	var type: String = data.get("type", "")
	if type != "ping" and type != "pong":
		print("NetworkManager received: ", data)
	_handle_message(data)

func _handle_message(data: Dictionary) -> void:
	var type = data.get("type", "")
	match type:
		"ping", "pong":
			return
		"room_created":
			room_code = data.get("roomCode", "")
			user_id = data.get("userId", "")
			room_created.emit(room_code, user_id)
			
		"room_joined":
			room_code = data.get("roomCode", "")
			user_id = data.get("userId", "")
			players = data.get("players", [])
			seed_status = data.get("seedStatus", "idle")
			var sz = data.get("seedZipName")
			seed_zip_name = sz if sz != null else ""
			var ss = data.get("seedSpoilerName")
			seed_spoiler_name = ss if ss != null else ""
			var tu = data.get("tunnelUrl")
			tunnel_url = tu if tu != null else ""
			var hosting_mode_joined = data.get("hostingMode")
			hosting_mode = hosting_mode_joined if hosting_mode_joined is String else "wayfinder_backend"
			var hosting_status_joined = data.get("hostingStatus")
			hosting_status = hosting_status_joined if hosting_status_joined is String else ""
			var hosting_room_url_joined = data.get("hostingRoomUrl")
			hosting_room_url = hosting_room_url_joined if hosting_room_url_joined is String else ""
			var hosting_server_url_joined = data.get("hostingServerUrl")
			hosting_server_url = hosting_server_url_joined if hosting_server_url_joined is String else ""
			var lb = data.get("lockedBy")
			locked_by = lb if lb != null else ""
			var ch = data.get("checks")
			checks = ch if ch is Dictionary else {}
			
			for p in players:
				if p.get("userId") == user_id:
					player_name = p.get("name", "")
					break
					
			room_joined.emit(room_code, user_id, players)
			
		"room_state":
			players = data.get("players", [])
			seed_status = data.get("seedStatus", "idle")
			var sz2 = data.get("seedZipName")
			seed_zip_name = sz2 if sz2 != null else ""
			var ss2 = data.get("seedSpoilerName")
			seed_spoiler_name = ss2 if ss2 != null else ""
			var tu2 = data.get("tunnelUrl")
			tunnel_url = tu2 if tu2 != null else ""
			var hosting_mode_value = data.get("hostingMode")
			hosting_mode = hosting_mode_value if hosting_mode_value is String else "wayfinder_backend"
			var hosting_status_value = data.get("hostingStatus")
			hosting_status = hosting_status_value if hosting_status_value is String else ""
			var hosting_room_url_value = data.get("hostingRoomUrl")
			hosting_room_url = hosting_room_url_value if hosting_room_url_value is String else ""
			var hosting_server_url_value = data.get("hostingServerUrl")
			hosting_server_url = hosting_server_url_value if hosting_server_url_value is String else ""
			var lb2 = data.get("lockedBy")
			locked_by = lb2 if lb2 != null else ""
			var ch2 = data.get("checks")
			if ch2 is Dictionary:
				checks = ch2
				checks_updated.emit(checks)
			room_state_updated.emit(players)

		"checks_updated":
			var ch3 = data.get("checks")
			if ch3 is Dictionary:
				checks = ch3
				checks_updated.emit(checks)
			
		"error":
			var message = data.get("message", "Unknown error")
			error_received.emit(message)
			
		"generation_log":
			var line = data.get("line", "")
			generation_log_received.emit(line)

		"kicked":
			var kicked_msg = data.get("message", "You have been kicked from the room.")
			kicked_from_room.emit(kicked_msg)

		"room_deleted":
			var closed_msg = data.get("message", "The room has been closed.")
			room_closed.emit(closed_msg)

		"server_log":
			var s_line = data.get("line", "")
			if s_line != "":
				server_log_received.emit(s_line)

func send_message(data: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var text = JSON.stringify(data)
		socket.send_text(text)
	else:
		print("Failed to send message: WebSocket is closed. State: ", socket.get_ready_state())

func create_room(name: String) -> void:
	player_name = name
	send_message({
		"type": "create_room",
		"playerName": name
	})

func join_room(code: String, name: String) -> void:
	player_name = name
	room_code = code.to_upper()
	send_message({
		"type": "join_room",
		"roomCode": room_code,
		"playerName": name
	})

func reconnect_session(id: String, code: String, name: String) -> void:
	user_id = id
	player_name = name
	room_code = code.to_upper()
	send_message({
		"type": "reconnect",
		"userId": id,
		"roomCode": room_code
	})

func generate_seed() -> void:
	send_message({
		"type": "generate_seed"
	})

func update_player_state(games: Array, is_ready: bool, yaml_str: String = "") -> void:
	send_message({
		"type": "update_state",
		"games": games,
		"isReady": is_ready,
		"yaml": yaml_str if yaml_str != "" else null
	})

func kick_player(target_user_id: String) -> void:
	send_message({
		"type": "kick_player",
		"targetUserId": target_user_id
	})

func leave_room() -> void:
	print("[NetworkManager] Leaving room: ", room_code)
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_message({
			"type": "leave_room",
			"roomCode": room_code,
			"userId": user_id
		})
	disconnect_from_server()
	room_code = ""
	user_id = ""
	players = []
	checks = {}
	hosting_server_url = ""

func close_room() -> void:
	print("[NetworkManager] Closing room: ", room_code)
	if room_code != "" and user_id != "":
		delete_room(room_code, user_id)
	leave_room()

func get_http_url() -> String:
	var base = server_url
	if base.begins_with("ws://"):
		return base.replace("ws://", "http://")
	elif base.begins_with("wss://"):
		return base.replace("wss://", "https://")
	return "https://wayfinder.disaac1.com"

func get_ap_server_url() -> String:
	if hosting_server_url != "":
		return hosting_server_url
	if tunnel_url == "":
		return ""
	if "localhost" in tunnel_url or "127.0.0.1" in tunnel_url:
		# Extract server host (remote IP or domain) from lobby connection url
		var parts = server_url.split("://")
		if parts.size() > 1:
			var host_part = parts[1].split(":")[0].split("/")[0]
			var port = tunnel_url.split(":")[-1]
			return "ws://" + host_part + ":" + port

	# If tunnel_url is a wss:// URL without an explicit port, inject :443
	# Archipelago client requires :443 to avoid defaulting to port 38281
	if tunnel_url.begins_with("wss://"):
		var scheme_split: PackedStringArray = tunnel_url.split("://")
		if scheme_split.size() > 1:
			var rest: String = scheme_split[1]
			var slash_idx: int = rest.find("/")
			var host_part: String = rest.substr(0, slash_idx) if slash_idx != -1 else rest
			var path_part: String = rest.substr(slash_idx) if slash_idx != -1 else ""
			if not ":" in host_part:
				return "wss://" + host_part + ":443" + path_part

	return tunnel_url

func fetch_http(endpoint: String) -> Dictionary:
	var http = HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	var url = get_http_url() + endpoint
	print("[HTTP GET] Requesting: ", url)
	var err = http.request(url)
	if err != OK:
		http.queue_free()
		return {"error": "Failed to initiate HTTP request"}
		
	var result = await http.request_completed
	# result = [result, response_code, headers, body]
	var res_code = result[1]
	var body = result[3]
	http.queue_free()
	
	if res_code != 200:
		return {"error": "HTTP Server returned status: " + str(res_code)}
		
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		return {"error": "Failed to parse response as JSON"}
		
	if typeof(json.data) == TYPE_DICTIONARY:
		return {"data": json.data}
	elif typeof(json.data) == TYPE_ARRAY:
		return {"data": {"list": json.data}}
	return {"data": {}}

func set_hosting_mode(mode: String) -> Dictionary:
	if room_code == "" or user_id == "":
		return {"error": "Not connected to a room"}
	var http = HTTPRequest.new()
	add_child(http)
	var url = get_http_url() + "/api/rooms/" + room_code.uri_encode() + "/hosting/mode"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"userId": user_id, "hostingMode": mode})
	var err = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"error": "Failed to initiate hosting mode request"}
	var result = await http.request_completed
	http.queue_free()
	var response_body = result[3].get_string_from_utf8()
	var parsed = JSON.parse_string(response_body)
	if result[1] < 200 or result[1] >= 300:
		if parsed is Dictionary and parsed.has("error"):
			return {"error": str(parsed.error)}
		return {"error": "Hosting mode request failed with HTTP " + str(result[1])}
	return parsed if parsed is Dictionary else {"success": true}

func cleanup_test_room(code: String) -> Dictionary:
	var http = HTTPRequest.new()
	add_child(http)
	var url = get_http_url() + "/api/test/cleanup"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"roomCode": code})
	print("[HTTP POST] Cleanup Requesting: ", url)
	var err = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"error": "Failed to initiate HTTP cleanup request"}
		
	var result = await http.request_completed
	var res_code = result[1]
	http.queue_free()
	
	if res_code != 200:
		return {"error": "Cleanup failed with code " + str(res_code)}
	return {"success": true}

func delete_room(code: String, u_id: String = "") -> Dictionary:
	var target_uid: String = u_id if u_id != "" else user_id
	var http = HTTPRequest.new()
	add_child(http)
	var url = get_http_url() + "/api/rooms/" + code.uri_encode() + "/delete?userId=" + target_uid.uri_encode()
	var headers = ["Content-Type: application/json"]
	print("[HTTP POST] Delete Room Requesting: ", url)
	var err = http.request(url, headers, HTTPClient.METHOD_POST, "")
	if err != OK:
		http.queue_free()
		return {"error": "Failed to initiate HTTP delete request"}
		
	var result = await http.request_completed
	var res_code = result[1]
	http.queue_free()
	
	if res_code != 200:
		return {"error": "Delete failed with code " + str(res_code)}
	return {"success": true}

func send_server_command(command: String) -> Dictionary:
	if room_code == "" or user_id == "":
		return {"error": "Not connected to a room"}
	var payload = JSON.stringify({
		"userId": user_id,
		"command": command
	})
	var http = HTTPRequest.new()
	add_child(http)
	var url = get_http_url() + "/api/rooms/" + room_code.uri_encode() + "/command"
	var headers = ["Content-Type: application/json"]
	print("[HTTP POST] Server Command Requesting: ", url, " -> ", command)
	var err = http.request(url, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		http.queue_free()
		return {"error": "Failed to initiate command request"}
	var response = await http.request_completed
	http.queue_free()
	var res_code = response[1]
	var body = response[3].get_string_from_utf8()
	var json = JSON.parse_string(body)
	if json is Dictionary:
		return json
	return {"statusCode": res_code}

func fetch_seed_data() -> Dictionary:
	if room_code == "":
		return {"error": "No active room"}
	return await fetch_http("/api/rooms/" + room_code.uri_encode() + "/seed-data")
