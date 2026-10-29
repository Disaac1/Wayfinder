extends SceneTree

var network_manager: Node
var http_client: HTTPRequest
var room_code: String = ""
var user_id: String = ""

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Phase 6 Checkout System Integration Test")
	print("==================================================")
	
	var net_script = load("res://scripts/core/network_manager.gd")
	if not net_script:
		_fail("Could not load network_manager.gd")
		return
		
	network_manager = net_script.new()
	root.add_child(network_manager)
	
	network_manager.connected_to_server.connect(_on_connected)
	network_manager.room_created.connect(_on_room_created)
	network_manager.room_state_updated.connect(_on_room_state_updated)
	network_manager.error_received.connect(_on_error)
	network_manager.connection_closed.connect(_on_closed)
	
	# Test watchdog timeout to prevent hanging on CI
	create_timer(25.0).timeout.connect(func():
		_fail("Test timed out waiting for backend connection or completion after 25s")
	)

	var err = network_manager.connect_to_server("ws://localhost:8080")
	if err != OK:
		_fail("Failed to connect: " + error_string(err))

func _on_connected() -> void:
	print("[Test] Connected. Creating room...")
	network_manager.create_room("Alice")

func _on_room_created(code: String, uid: String) -> void:
	room_code = code
	user_id = uid
	print("[Test] Room created: ", room_code, " with User ID: ", user_id)
	
	await create_timer(0.2).timeout
	var mock_yaml = "description: Test YAML\nname: Alice\ngame: Hollow Knight\nHollow Knight:\n  difficulty: normal\n"
	network_manager.update_player_state(["Hollow Knight"], true, mock_yaml)

func _on_room_state_updated(players: Array) -> void:
	if players.size() == 0:
		return
	
	var me: Dictionary = {}
	for p in players:
		if p.get("userId") == user_id:
			me = p
			break
			
	if me.is_empty() or me.get("games", []).size() == 0:
		return
		
	if network_manager.seed_status == "idle":
		print("[Test] Triggering seed generation...")
		network_manager.generate_seed()
		return
		
	if network_manager.seed_status == "done":
		print("[Test] Seed generation complete. Proceeding to Checkout validation...")
		# Unbind signals to prevent loops
		network_manager.room_state_updated.disconnect(_on_room_state_updated)
		_run_checkout_checkout()

func _run_checkout_checkout() -> void:
	print("[Test] 1. Requesting Checkout...")
	var http = HTTPRequest.new()
	root.add_child(http)
	
	var download_dir = "user://saves/".path_join(room_code)
	DirAccess.make_dir_recursive_absolute(download_dir)
	var zip_path = download_dir.path_join("save_checkout.zip")
	http.download_file = zip_path
	
	var url = network_manager.get_http_url() + "/api/session/" + room_code + "/checkout?userId=" + user_id
	var err = http.request(url)
	if err != OK:
		_fail("Checkout request failed to initiate")
		return
		
	var result = await http.request_completed
	http.queue_free()
	
	var response_code = result[1]
	print("[Test] Checkout response code: ", response_code)
	if response_code != 200:
		_fail("Expected 200 OK from checkout, got " + str(response_code))
		return
		
	# Confirm the database lock is reflected via WebSocket
	# Wait brief moment for WS broadcast to populate
	await create_timer(0.3).timeout
	print("[Test] NetworkManager.locked_by after checkout: ", network_manager.locked_by)
	if network_manager.locked_by != user_id:
		_fail("Expected room to be locked by " + user_id + ", got: " + network_manager.locked_by)
		return
		
	# Clean up downloaded zip (since no save exists yet, it returns JSON)
	DirAccess.remove_absolute(zip_path)
	
	_run_checkout_conflict()

func _run_checkout_conflict() -> void:
	print("[Test] 2. Verifying lock conflict with a fake user...")
	var http = HTTPRequest.new()
	root.add_child(http)
	
	var url = network_manager.get_http_url() + "/api/session/" + room_code + "/checkout?userId=fake_user_id"
	var err = http.request(url)
	if err != OK:
		_fail("Conflict test request failed to initiate")
		return
		
	var result = await http.request_completed
	http.queue_free()
	
	var response_code = result[1]
	print("[Test] Conflict checkout response code: ", response_code)
	if response_code != 409 and response_code != 403:
		_fail("Expected 409 Conflict or 403 Forbidden when trying to checkout a locked room, got " + str(response_code))
		return
		
	_run_checkin()

func _run_checkin() -> void:
	print("[Test] 3. Simulating local save creation and Checkin...")
	var save_dir = "user://saves/".path_join(room_code)
	var save_path = save_dir.path_join(room_code + ".apsave")
	
	# Create a dummy save file
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		_fail("Failed to write dummy save file locally")
		return
	file.store_string("Mock Archipelago Save File Content")
	file.close()
	
	# Zip it using ZIPPacker
	var upload_zip_path = save_dir.path_join("save_upload.zip")
	var packer = ZIPPacker.new()
	var err = packer.open(upload_zip_path, ZIPPacker.APPEND_CREATE)
	if err != OK:
		_fail("Failed to initialize ZIPPacker")
		return
		
	var save_file = FileAccess.open(save_path, FileAccess.READ)
	var buffer = save_file.get_buffer(save_file.get_length())
	save_file.close()
	
	packer.start_file(room_code + ".apsave")
	packer.write_file(buffer)
	packer.close_file()
	packer.close()
	
	# Read packed zip
	var zip_file = FileAccess.open(upload_zip_path, FileAccess.READ)
	var zip_data = zip_file.get_buffer(zip_file.get_length())
	zip_file.close()
	
	# Upload
	var http = HTTPRequest.new()
	root.add_child(http)
	
	var url = network_manager.get_http_url() + "/api/session/" + room_code + "/checkin?userId=" + user_id
	var headers = ["Content-Type: application/zip"]
	err = http.request_raw(url, headers, HTTPClient.METHOD_POST, zip_data)
	if err != OK:
		_fail("Checkin request failed to initiate")
		return
		
	var result = await http.request_completed
	http.queue_free()
	
	# Clean up local test save files
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(upload_zip_path)
	
	var response_code = result[1]
	print("[Test] Checkin response code: ", response_code)
	if response_code != 200:
		_fail("Expected 200 OK from checkin, got " + str(response_code))
		return
		
	await create_timer(0.3).timeout
	print("[Test] NetworkManager.locked_by after checkin: ", network_manager.locked_by)
	if network_manager.locked_by != "":
		_fail("Expected room lock to be cleared, but got: " + network_manager.locked_by)
		return
		
	_run_force_unlock()

func _run_force_unlock() -> void:
	print("[Test] 4. Verifying Force Unlock override...")
	# Checkout first to lock it again
	var http = HTTPRequest.new()
	root.add_child(http)
	var url = network_manager.get_http_url() + "/api/session/" + room_code + "/checkout?userId=" + user_id
	http.request(url)
	await http.request_completed
	http.queue_free()
	
	await create_timer(0.2).timeout
	if network_manager.locked_by != user_id:
		_fail("Re-acquiring lock failed")
		return
		
	# Call Force Unlock from fake user (anyone should be allowed to unlock)
	var http_unlock = HTTPRequest.new()
	root.add_child(http_unlock)
	var unlock_url = network_manager.get_http_url() + "/api/session/" + room_code + "/unlock?userId=anonymous"
	var err = http_unlock.request(unlock_url, [], HTTPClient.METHOD_POST)
	if err != OK:
		_fail("Unlock request failed to initiate")
		return
		
	var result = await http_unlock.request_completed
	http_unlock.queue_free()
	
	var response_code = result[1]
	print("[Test] Unlock response code: ", response_code)
	if response_code != 200:
		_fail("Expected 200 OK from force unlock, got " + str(response_code))
		return
		
	await create_timer(0.3).timeout
	print("[Test] NetworkManager.locked_by after force unlock: ", network_manager.locked_by)
	if network_manager.locked_by != "":
		_fail("Expected lock to be cleared by force unlock, but got: " + network_manager.locked_by)
		return
		
	print("\n==================================================")
	print("  CHECKOUT SYSTEM INTEGRATION TEST PASSED SUCCESSFULY!")
	print("==================================================")
	_success()

func _on_error(message: String) -> void:
	_fail("Error received from server: " + message)

func _on_closed() -> void:
	_fail("WebSocket closed unexpectedly")

func _fail(reason: String) -> void:
	printerr("[Test FAIL] ", reason)
	if network_manager:
		if network_manager.room_code != "":
			await network_manager.cleanup_test_room(network_manager.room_code)
		network_manager.disconnect_from_server()
	quit(1)

func _success() -> void:
	if network_manager:
		if network_manager.room_code != "":
			await network_manager.cleanup_test_room(network_manager.room_code)
		network_manager.disconnect_from_server()
	quit(0)
