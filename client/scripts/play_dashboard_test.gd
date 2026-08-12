extends SceneTree

var lobby: Node
var net_mgr: Node

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Play Dashboard & Lockdown Integration Test")
	print("==================================================")
	
	# Load network manager script
	net_mgr = root.get_node_or_null("NetworkManager")
	if not net_mgr:
		var net_script = load("res://scripts/network_manager.gd")
		if not net_script:
			_fail("Could not load network_manager.gd")
			return
		net_mgr = net_script.new()
		net_mgr.name = "NetworkManager"
		root.add_child(net_mgr)
	
	# Test 1: Instantiate Lobby scene
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	print("[Test] 1. Validating UI nodes structure...")
	var badge = lobby.get_node("%ActiveSeedBadge")
	var switcher = lobby.get_node("%ViewSwitcherHBox")
	var play_view = lobby.get_node("%PlayDashboardView")
	var setup_view = lobby.get_node("%LobbySetupView")
	var games_grid = lobby.get_node("%GamesGridContainer")
	
	if not badge or not switcher or not play_view or not setup_view or not games_grid:
		_fail("One or more Play Dashboard UI nodes are missing from lobby.tscn")
		return
	print("[Test] All Play Dashboard UI nodes verified present.")
	
	# Test 2: View Switcher Functions
	print("[Test] 2. Testing view switching logic...")
	lobby.local_selected_games = ["Pokemon Emerald", "Hollow Knight"]
	
	lobby._switch_view_mode("play")
	await create_timer(0.2).timeout
	
	if not play_view.visible or setup_view.visible:
		_fail("Switching to Play View failed")
		return
	print("[Test] Play View active verified.")
	
	var card_count = games_grid.get_child_count()
	print("[Test] Grid rendered game cards count: ", card_count)
	if card_count != 2:
		_fail("Expected 2 game cards in GamesGridContainer, found: " + str(card_count))
		return
	print("[Test] Grid rendered cards successfully (2 cards).")
	
	lobby._switch_view_mode("setup")
	await create_timer(0.2).timeout
	if not setup_view.visible or play_view.visible:
		_fail("Switching to Setup View failed")
		return
	print("[Test] Setup View active verified.")
	
	# Test 3: Seed lockdown UI states
	print("[Test] 3. Testing seed lockdown state updates...")
	# Simulate NetworkManager seed_status = "done"
	net_mgr.seed_status = "done"
	net_mgr.seed_zip_name = "AP_TestSeed.zip"
	net_mgr.seed_spoiler_name = "AP_TestSpoiler.txt"
	
	lobby._update_players_ui([])
	await create_timer(0.2).timeout
	
	if not badge.visible or not switcher.visible:
		_fail("Active seed badge or view switcher remained hidden when seed status is done")
		return
	print("[Test] Active seed badge and view switcher verified visible when seed status is done.")
	
	if not play_view.visible:
		_fail("Auto-switch to Play View did not trigger when seed status is done")
		return
	print("[Test] Auto-switch to Play View on seed completion verified.")
	
	# Cleanup
	lobby.queue_free()
	net_mgr.queue_free()
	
	print("\n==================================================")
	print("  PLAY DASHBOARD & LOCKDOWN INTEGRATION TEST PASSED!")
	print("==================================================")
	quit(0)

func _fail(reason: String) -> void:
	printerr("[Test FAIL] ", reason)
	if lobby:
		lobby.queue_free()
	if net_mgr:
		net_mgr.queue_free()
	quit(1)
