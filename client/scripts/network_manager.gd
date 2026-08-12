extends Node

signal connected_to_server
signal connection_closed
signal room_created(room_code: String, user_id: String)
signal room_joined(room_code: String, user_id: String, players: Array)
signal room_state_updated(players: Array)
signal error_received(message: String)
signal generation_log_received(line: String)

var socket: WebSocketPeer = WebSocketPeer.new()
var is_connected: bool = false

var server_url: String = "ws://localhost:8080"
var player_name: String = ""
var room_code: String = ""
var user_id: String = ""
var players: Array = []
var seed_status: String = "idle"
var seed_zip_name: String = ""
var seed_spoiler_name: String = ""
var tunnel_url: String = ""
var locked_by: String = ""

func _ready() -> void:
	# Disable processing until we actively initiate a connection
	set_process(false)

func connect_to_server(url: String = server_url) -> Error:
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

func _process(_delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			connected_to_server.emit()
			print("WebSocket connection fully established.")
			
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var text = packet.get_string_from_utf8()
			_handle_raw_message(text)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			connection_closed.emit()
			set_process(false)
			print("WebSocket connection closed by remote peer.")
			
	elif state == WebSocketPeer.STATE_CONNECTING:
		pass
	else:
		# Error or state is none
		pass

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
		
	print("NetworkManager received: ", data)
	_handle_message(data)

func _handle_message(data: Dictionary) -> void:
	var type = data.get("type", "")
	match type:
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
			var lb = data.get("lockedBy")
			locked_by = lb if lb != null else ""
			
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
			var lb2 = data.get("lockedBy")
			locked_by = lb2 if lb2 != null else ""
			room_state_updated.emit(players)
			
		"error":
			var message = data.get("message", "Unknown error")
			error_received.emit(message)
			
		"generation_log":
			var line = data.get("line", "")
			generation_log_received.emit(line)

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

func get_http_url() -> String:
	var base = server_url
	if base.begins_with("ws://"):
		return base.replace("ws://", "http://")
	elif base.begins_with("wss://"):
		return base.replace("wss://", "https://")
	return "http://localhost:8080"

func get_ap_server_url() -> String:
	if tunnel_url == "":
		return ""
	if "localhost" in tunnel_url or "127.0.0.1" in tunnel_url:
		# Extract server host (remote IP or domain) from lobby connection url
		var parts = server_url.split("://")
		if parts.size() > 1:
			var host_part = parts[1].split(":")[0]
			var port = tunnel_url.split(":")[-1]
			return "ws://" + host_part + ":" + port
	return tunnel_url

func fetch_http(endpoint: String) -> Dictionary:
	var http = HTTPRequest.new()
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

func delete_room(code: String) -> Dictionary:
	var http = HTTPRequest.new()
	add_child(http)
	var url = get_http_url() + "/api/rooms/" + code.uri_encode() + "/delete"
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

