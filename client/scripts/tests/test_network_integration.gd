extends SceneTree

# =====================================================================
#             SUITE 5: NETWORK & BACKEND INTEGRATION
# =====================================================================
# End-to-end integration with Wayfinder backend:
# - HTTP REST API verification (/api/games, /api/options/<game>)
# - WebSocket connectivity & real-time room lifecycle
# - Multi-player state synchronization & YAML payloads
# - Save state checkout locking and conflict mechanics
# - Clean room teardown
# =====================================================================

var test_passed: bool = true
var is_finished: bool = false
var network_manager: Node
var step: int = 1
var test_game: String = "Pokemon Emerald"

func _init() -> void:
	_run_suite.call_deferred()

func _fail(reason: String) -> void:
	if is_finished:
		return
	printerr("  ❌ [FAIL] ", reason)
	test_passed = false
	_finish()

func _assert_true(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
		return false
	return true

func _run_suite() -> void:
	print("==================================================================")
	print("  SUITE 5: NETWORK & BACKEND INTEGRATION                          ")
	print("==================================================================")

	# Watchdog timeout for CI safety
	create_timer(30.0).timeout.connect(func():
		if not is_finished:
			_fail("Test timed out waiting for backend connection or completion after 30s")
	)

	var net_script = load("res://scripts/core/network_manager.gd")
	if not net_script:
		_fail("Could not load network_manager.gd")
		return

	network_manager = net_script.new()
	root.add_child(network_manager)

	network_manager.connected_to_server.connect(_on_connected)
	network_manager.room_created.connect(_on_room_created)
	network_manager.room_state_updated.connect(_on_room_state_updated)
	network_manager.error_received.connect(func(msg): _fail("Server error: " + msg))
	network_manager.connection_closed.connect(func(): if step < 4 and not is_finished: _fail("WebSocket closed prematurely"))

	print("Connecting to ws://localhost:8080...")
	var err = network_manager.connect_to_server("ws://localhost:8080")
	if err != OK:
		_fail("Failed to initiate connection: " + error_string(err))

func _on_connected() -> void:
	if is_finished:
		return
	print("\n[Test 1] Connection established. Validating REST HTTP endpoints...")

	# 1. GET /api/games
	var games_res = await network_manager.fetch_http("/api/games")
	if not _assert_true(not games_res.has("error"), "GET /api/games failed: " + str(games_res.get("error", ""))):
		return
	var games_list = games_res.data.get("games", [])
	if not _assert_true(games_list.size() > 0, "Expected non-empty games list from /api/games"):
		return

	# Choose test game from games list
	if "Pokemon Emerald" in games_list:
		test_game = "Pokemon Emerald"
	elif "Hollow Knight" in games_list:
		test_game = "Hollow Knight"
	else:
		test_game = str(games_list[0])

	print("  -> Passed: /api/games returned %d available games (Testing options with '%s')." % [games_list.size(), test_game])

	# 2. GET /api/options/:game
	var opt_res = await network_manager.fetch_http("/api/options/" + test_game.uri_encode())
	if not _assert_true(not opt_res.has("error"), "GET /api/options/%s failed: %s" % [test_game, str(opt_res.get("error", ""))]):
		return
	var opt_data = opt_res.get("data", {})
	if not _assert_true(opt_data.get("game") == test_game, "Option schema game mismatch: expected '%s', got '%s'" % [test_game, str(opt_data.get("game"))]):
		return
	print("  -> Passed: /api/options schema verified for '%s'." % test_game)

	# 3. Create Room via WebSocket
	print("\n[Test 2] Creating room via WebSocket...")
	step = 2
	network_manager.create_room("SuiteTester")

func _on_room_created(code: String, user_id: String) -> void:
	if is_finished:
		return
	print("  -> Room created: %s (User ID: %s)" % [code, user_id])
	if not _assert_true(code.length() == 6, "Expected 6-character room code"):
		return
	if not _assert_true(user_id != "", "Expected non-empty user_id"):
		return

	# Update Player State
	await create_timer(0.2).timeout
	print("\n[Test 3] Updating player state and YAML...")
	step = 3
	var mock_yaml = "description: Test\nname: SuiteTester\ngame: %s\n" % test_game
	network_manager.update_player_state([test_game], true, mock_yaml)

func _on_room_state_updated(players: Array) -> void:
	if is_finished or step != 3 or players.size() == 0:
		return

	var me = {}
	for p in players:
		if p.get("name") == "SuiteTester":
			me = p
			break

	if me.is_empty() or me.get("games", []).size() == 0:
		return

	print("  -> Room state synchronized: %s isReady=%s" % [me.get("name"), str(me.get("isReady"))])
	if not _assert_true(me.get("isReady") == true, "Expected isReady=true"):
		return
	if not _assert_true(test_game in me.get("games", []), "Expected '%s' in player games" % test_game):
		return

	# 4. Session Checkout Locking Verification
	print("\n[Test 4] Verifying Session Checkout Locking API...")
	step = 4
	var room_code = network_manager.room_code
	var user_id = network_manager.user_id

	var checkout_res = await network_manager.fetch_http("/api/session/%s/checkout?userId=%s" % [room_code, user_id])
	if not _assert_true(not checkout_res.has("error"), "Failed to acquire session checkout lock: " + str(checkout_res.get("error", ""))):
		return
	print("  -> Passed: Acquired session lock for room: " + room_code)

	# 5. Clean teardown
	print("\n[Test 5] Cleaning up test room...")
	await network_manager.cleanup_test_room(room_code)
	print("  -> Passed: Test room cleaned up successfully.")

	_finish()

func _finish() -> void:
	if is_finished:
		return
	is_finished = true

	print("\n==================================================================")
	if test_passed:
		print("  SUITE 5: ALL NETWORK & INTEGRATION TESTS PASSED! [OK]          ")
	else:
		printerr("  SUITE 5: COMPLETED WITH FAILURES!                              ")
	print("==================================================================")
	if network_manager:
		network_manager.disconnect_from_server()
		network_manager.queue_free()
	quit(0 if test_passed else 1)
