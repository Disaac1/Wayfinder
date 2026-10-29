extends SceneTree

# =====================================================================
#             SUITE 2: GUIDED SETUP & GAME CATALOG MATRIX
# =====================================================================
# Data-driven validation of all focus games: Guided Setup JSON schemas,
# wizard step generation, dynamic UI control compilation, APWorld bundle
# presence, and game icon assets.
# =====================================================================

var test_passed: bool = true
var lobby: Node

const FOCUS_GAMES = [
	{"name": "Pokemon Emerald", "slug": "pokemon_emerald", "apworld": "", "custom_world": false},
	{"name": "Super Mario 64", "slug": "super_mario_64", "apworld": "", "custom_world": false},
	{"name": "Hollow Knight", "slug": "hollow_knight", "apworld": "", "custom_world": false},
	{"name": "Metroid Fusion", "slug": "metroid_fusion", "apworld": "", "custom_world": false},
	{"name": "Plants vs. Zombies", "slug": "plants_vs_zombies", "apworld": "", "custom_world": false},
	{"name": "Symphony of the Night", "slug": "symphony_of_the_night", "apworld": "", "custom_world": false},
	{"name": "Slay the Spire", "slug": "slay_the_spire", "apworld": "spire.apworld", "custom_world": true},
	{"name": "Slay the Spire 2", "slug": "slay_the_spire_2", "apworld": "spire2.apworld", "custom_world": true},
	{"name": "Hades", "slug": "hades", "apworld": "hades.apworld", "custom_world": true},
	{"name": "The Binding of Isaac Repentance", "slug": "the_binding_of_isaac_repentance", "apworld": "tboir.apworld", "custom_world": true},
	{"name": "Luigi's Mansion", "slug": "luigis_mansion", "apworld": "luigismansion.apworld", "custom_world": true}
]

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
	print("  SUITE 2: GUIDED SETUP & GAME CATALOG MATRIX                     ")
	print("==================================================================")

	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load res://scenes/lobby.tscn")
		_finish()
		return

	lobby = lobby_scene.instantiate()
	root.add_child(lobby)

	var registry = load("res://scripts/guided_setup/guided_setup_registry.gd")
	var launcher = lobby.launcher
	await launcher.load_launcher_config()

	# -------------------------------------------------------------
	# 1. Declarative Guided Setup Validation for All Focus Games
	# -------------------------------------------------------------
	print("\n[Test 1] Validating Guided Setup JSON schemas & UI generation across %d games..." % FOCUS_GAMES.size())

	for item in FOCUS_GAMES:
		var g_name = item["name"]
		var slug = item["slug"]
		print("\n  -> Testing: '%s' (slug: %s)..." % [g_name, slug])

		_assert_true(registry.has_guided_setup(g_name), "Registry missing guided setup for: " + g_name)
		var json_path = registry._get_declarative_json_path(g_name)
		_assert_true(json_path != "", "No JSON schema path found for: " + g_name)

		var wizard = registry.DeclarativeGuidedSetupScript.new()
		_assert_true(wizard.load_from_file(json_path), "Failed to load/parse JSON at: " + json_path)

		var req_keys = wizard._get_required_schema_keys()
		var steps = wizard._get_steps_data()
		_assert_true(steps.size() >= 3, "Expected at least 3 wizard steps, got %d for %s" % [steps.size(), g_name])

		# Build mock schema
		var mock_schema_options = []
		for k in req_keys:
			mock_schema_options.append({"name": k})
		var val_res = registry.validate_and_create(g_name, {"options": mock_schema_options})
		_assert_true(val_res.get("valid", false), "Validation failed for %s: %s" % [g_name, str(val_res.get("reason"))])

		var active_wizard = val_res.get("wizard")
		_assert_true(active_wizard != null, "Active wizard is null for: " + g_name)

		var dummy_container = VBoxContainer.new()
		root.add_child(dummy_container)
		var cfg = {}
		active_wizard.init_config(cfg)

		for s in steps:
			active_wizard.current_step = s.get("num", 1)
			active_wizard.build_wizard_ui(dummy_container, func(k, v): cfg[k] = v)

		_assert_true(dummy_container.get_child_count() > 0, "No UI controls generated for: " + g_name)
		dummy_container.queue_free()
		print("     [OK] Steps: %d, Required keys: %d, Title: '%s'" % [steps.size(), req_keys.size(), wizard._get_game_title()])

	# -------------------------------------------------------------
	# 2. Custom APWorld Package Presence
	# -------------------------------------------------------------
	print("\n[Test 2] Verifying custom APWorld bundles in client and backend...")
	for item in FOCUS_GAMES:
		if not item.get("custom_world", false):
			continue
		var apworld_file = item["apworld"]
		var client_apworld = "res://Archipelago/custom_worlds/" + apworld_file
		var backend_apworld = "res://../backend/archipelago_core/custom_worlds/" + apworld_file

		_assert_true(FileAccess.file_exists(client_apworld), "Missing client APWorld bundle: " + client_apworld)
		_assert_true(FileAccess.file_exists(backend_apworld), "Missing backend APWorld bundle: " + backend_apworld)
		print("  -> Passed: Verified %s in client and backend bundles." % apworld_file)

	# -------------------------------------------------------------
	# 3. Game Icon Asset Presence
	# -------------------------------------------------------------
	print("\n[Test 3] Verifying game artwork icon assets...")
	for item in FOCUS_GAMES:
		var slug = item["slug"]
		var icon_path = "res://../backend/data/games/" + slug + "/icon.png"
		_assert_true(FileAccess.file_exists(icon_path), "Missing game icon at: " + icon_path)
	print("  -> Passed: All %d focus game icons exist on disk." % FOCUS_GAMES.size())

	_finish()

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  SUITE 2: ALL GUIDED SETUP & CATALOG TESTS PASSED! [OK]         ")
	else:
		printerr("  SUITE 2: COMPLETED WITH FAILURES!                              ")
	print("==================================================================")
	if lobby:
		lobby.queue_free()
	quit(0 if test_passed else 1)
