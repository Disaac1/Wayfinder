extends SceneTree

# =====================================================================
#             SUITE 4: UI COMPONENTS & PLAY DASHBOARD
# =====================================================================
# Validates view mode switching (Setup View vs Play Dashboard View),
# Add Game modal search and filtering, progress calculation, and host
# tools UI state.
# =====================================================================

var test_passed: bool = true
var lobby: Node

func _init() -> void:
	_run_suite.call_deferred()

func _fail(reason: String) -> void:
	printerr("  ❌ [FAIL] ", reason)
	test_passed = false

func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _run_suite() -> void:
	print("==================================================================")
	print("  SUITE 4: UI COMPONENTS & PLAY DASHBOARD                         ")
	print("==================================================================")

	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load res://scenes/lobby.tscn")
		_finish()
		return

	lobby = lobby_scene.instantiate()
	root.add_child(lobby)

	# -------------------------------------------------------------
	# 1. View Mode Switching (Setup View <-> Play Dashboard)
	# -------------------------------------------------------------
	print("\n[Test 1] Verifying view mode switching...")
	lobby.local_selected_games = ["Pokemon Emerald", "Hollow Knight"]
	lobby._switch_view_mode("play")
	_assert_true(lobby.current_view_mode == "play", "current_view_mode should be 'play'")
	_assert_true(lobby.play_dashboard_view.visible == true, "play_dashboard_view must be visible in play mode")
	_assert_true(lobby.lobby_setup_view.visible == false, "lobby_setup_view must be hidden in play mode")

	lobby._switch_view_mode("setup")
	_assert_true(lobby.current_view_mode == "setup", "current_view_mode should be 'setup'")
	_assert_true(lobby.lobby_setup_view.visible == true, "lobby_setup_view must be visible in setup mode")
	_assert_true(lobby.play_dashboard_view.visible == false, "play_dashboard_view must be hidden in setup mode")
	print("  -> Passed: Seamless switching between Setup View and Play Dashboard View.")

	# -------------------------------------------------------------
	# 2. Add Game Modal Search and Filtering
	# -------------------------------------------------------------
	print("\n[Test 2] Verifying Add Game modal catalog search and filtering...")
	var modal_scene = load("res://scenes/modals/add_game_modal.tscn")
	_assert_true(modal_scene != null, "Failed to load add_game_modal.tscn")
	var modal = modal_scene.instantiate()
	root.add_child(modal)

	var launcher = lobby.launcher
	var sample_games = [
		"Pokemon Emerald",
		"Hollow Knight",
		"Super Mario 64",
		"A Hat in Time",
		"Adventure",
		"Aquaria"
	]
	var supported_fn = func(g_name: String) -> bool:
		return launcher.has_curated_preset(g_name)

	modal.open(sample_games, supported_fn, [])

	var checkbox: CheckBox = modal.get_node("%ShowAllWorldsCheckBox")
	var count_label: Label = modal.get_node("%CountLabel")
	var grid: GridContainer = modal.get_node("%GamePopupGrid")

	_assert_true(checkbox.button_pressed == false, "Checkbox should be unchecked by default")

	# With toggle OFF, only curated games should be visible
	var visible_count = 0
	for child in grid.get_children():
		if child is Button and child.visible:
			visible_count += 1
	_assert_true(visible_count == 3, "Expected 3 curated games visible by default, got %d" % visible_count)

	# Toggle ON
	checkbox.button_pressed = true
	var all_visible_count = 0
	for child in grid.get_children():
		if child is Button and child.visible:
			all_visible_count += 1
	_assert_true(all_visible_count == 6, "Expected 6 games visible with toggle ON, got %d" % all_visible_count)

	modal.queue_free()
	print("  -> Passed: Add Game modal curation toggle and grid filtering verified.")

	# -------------------------------------------------------------
	# 3. Play Dashboard Dynamic Checks & Node Structure
	# -------------------------------------------------------------
	print("\n[Test 3] Verifying Play Dashboard UI nodes and checks structure...")
	var badge = lobby.get_node("%ActiveSeedBadge")
	var switcher = lobby.get_node("%ViewSwitcherHBox")
	var play_view = lobby.get_node("%PlayDashboardView")
	var setup_view = lobby.get_node("%LobbySetupView")
	var games_grid = lobby.get_node("%GamesGridContainer")

	_assert_true(badge != null, "ActiveSeedBadge node missing")
	_assert_true(switcher != null, "ViewSwitcherHBox node missing")
	_assert_true(play_view != null, "PlayDashboardView node missing")
	_assert_true(setup_view != null, "LobbySetupView node missing")
	_assert_true(games_grid != null, "GamesGridContainer node missing")
	print("  -> Passed: Play Dashboard component tree verified.")

	# -------------------------------------------------------------
	# 4. Host Tooling & Status Badges
	# -------------------------------------------------------------
	print("\n[Test 4] Verifying Host tools and status badge controls...")
	_assert_true(lobby.room_label != null, "Room label must exist")
	_assert_true(lobby.status_label != null, "Status label must exist")
	_assert_true(lobby.server_label != null, "Server label must exist")
	_assert_true(lobby.connection_badge != null, "Connection badge must exist")
	print("  -> Passed: Host headers and status badge controls verified.")

	_finish()

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  SUITE 4: ALL UI & DASHBOARD TESTS PASSED! [OK]                 ")
	else:
		printerr("  SUITE 4: COMPLETED WITH FAILURES!                              ")
	print("==================================================================")
	if lobby:
		lobby.queue_free()
	quit(0 if test_passed else 1)
