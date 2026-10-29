extends SceneTree

var network_manager: Node

func _init() -> void:
	# Defer execution so tree structure is initialized
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Godot WebSocket Integration Test")
	print("==================================================")
	
	# Load and instantiate the NetworkManager script
	var net_script = load("res://scripts/core/network_manager.gd")
	if not net_script:
		_fail("Could not load network_manager.gd")
		return
		
	network_manager = net_script.new()
	root.add_child(network_manager)
	
	# Bind signals
	network_manager.connected_to_server.connect(_on_connected)
	network_manager.room_created.connect(_on_room_created)
	network_manager.room_state_updated.connect(_on_room_state_updated)
	network_manager.error_received.connect(_on_error)
	network_manager.connection_closed.connect(_on_closed)
	
	# Test watchdog timeout to prevent hanging on CI
	create_timer(25.0).timeout.connect(func():
		_fail("Test timed out waiting for backend connection or completion after 25s")
	)

	# Connect to the local server
	var err = network_manager.connect_to_server("ws://localhost:8080")
	if err != OK:
		_fail("Failed to connect to server: " + error_string(err))

func _on_connected() -> void:
	print("[Test] Connection established. Verifying HTTP REST APIs...")
	
	print("[Test] Fetching available games list...")
	var games_res = await network_manager.fetch_http("/api/games")
	if games_res.has("error"):
		_fail("Failed to fetch games list: " + games_res.error)
		return
	var games_list = games_res.data.get("games", [])
	print("[Test] Available games list: ", games_list)
	if not "Hollow Knight" in games_list:
		_fail("Expected 'Hollow Knight' in games list, but got: " + str(games_list))
		return
		
	var opt_res = await network_manager.fetch_http("/api/options/" + "Hollow Knight".uri_encode())
	if opt_res.has("error"):
		_fail("Failed to fetch Hollow Knight options: " + opt_res.error)
		return
	var opt_data = opt_res.data
	print("[Test] Hollow Knight options loaded. Options count: ", opt_data.get("options", []).size())
	if opt_data.get("game") != "Hollow Knight":
		_fail("Expected game field in option schema to be 'Hollow Knight'")
		return
		
	print("[Test] HTTP REST APIs verified. Now creating room...")
	network_manager.create_room("TestAlice")

func _on_room_created(code: String, user_id: String) -> void:
	print("[Test] Room created. Code: ", code, ", User ID: ", user_id)
	if code.length() != 6:
		_fail("Invalid room code length (expected 6, got " + str(code.length()) + ")")
		return
		
	# Delay slightly before updating state to allow initial state broadcast to complete
	await create_timer(0.2).timeout
	var mock_yaml = "description: Test YAML\nname: TestAlice\ngame: Hollow Knight\nHollow Knight:\n  difficulty: normal\n"
	print("[Test] Updating state with games ['Hollow Knight'], isReady = true, and mock YAML...")
	network_manager.update_player_state(["Hollow Knight"], true, mock_yaml)

func _on_room_state_updated(players: Array) -> void:
	print("[Test] Received updated room state: ", players)
	if players.size() == 0:
		return
		
	# Find our player in the state list
	var me: Dictionary = {}
	for p in players:
		if p.get("name") == "TestAlice":
			me = p
			break
			
	if me.is_empty():
		_fail("Player 'TestAlice' not found in state list")
		return
		
	# Wait until we see our updated games list (to skip the initial empty room_state)
	var games = me.get("games", [])
	if games.size() == 0:
		print("[Test] Empty games list received, awaiting next update...")
		return
		
	# Verify assertions
	if not "Hollow Knight" in games:
		_fail("Expected games list to contain 'Hollow Knight', got: " + str(games))
		return
		
	if not me.get("isReady", false):
		_fail("Expected isReady to be true")
		return
		
	if not me.get("isHost", false):
		_fail("Expected player to be flagged as Host")
		return
		
	var yaml = me.get("yaml", "")
	print("[Test] Verifying stored player YAML: ", yaml)
	if not yaml or not "difficulty: normal" in yaml:
		_fail("Expected player YAML to contain 'difficulty: normal', but got: " + str(yaml))
		return
		
	# If seed status is idle, request generation!
	if network_manager.seed_status == "idle":
		print("[Test] Triggering seed generation...")
		network_manager.generate_seed()
		return
		
	if network_manager.seed_status == "generating":
		print("[Test] Generation in progress...")
		return
		
	if network_manager.seed_status == "done":
		print("[Test] Seed generation complete!")
		print("[Test] Seed zip: ", network_manager.seed_zip_name)
		print("[Test] Spoiler log: ", network_manager.seed_spoiler_name)
		print("[Test] Tunnel connection URL: ", network_manager.tunnel_url)
		
		# Assert seed names and tunnel_url are populated
		if network_manager.seed_zip_name == "":
			_fail("Expected seed zip name to be non-empty")
			return
		if network_manager.tunnel_url == "":
			_fail("Expected tunnel_url to be non-empty")
			return
		if not "ws://localhost:" in network_manager.tunnel_url:
			_fail("Expected tunnel_url to start with 'ws://localhost:', got: " + network_manager.tunnel_url)
			return
			
		print("\n==================================================")
		print("  INTEGRATION TEST PASSED SUCCESSFULY!")
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
