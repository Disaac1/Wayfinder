extends SceneTree

var test_passed: bool = true
var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _fail(reason: String) -> void:
	printerr("[Test Failure] ", reason)
	test_passed = false

func _run_test() -> void:
	print("==================================================")
	print("  Starting Dynamic Guided Setup Multi-Game Test")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		_finish()
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	var registry = load("res://scripts/guided_setup/guided_setup_registry.gd")
	var games_to_test = [
		"Pokemon Emerald",
		"Super Mario 64",
		"Hollow Knight",
		"Metroid Fusion",
		"Plants vs. Zombies",
		"Symphony of the Night",
		"Slay the Spire",
		"Slay the Spire 2"
	]
	
	for g_name in games_to_test:
		if not registry.has_guided_setup(g_name):
			await lobby._ensure_remote_guided_setup(g_name)
		print("\n[Test] Checking Guided Setup for: ", g_name)
		if not registry.has_guided_setup(g_name):
			_fail("Registry reported no guided setup for: " + g_name)
			continue
			
		var json_path = registry._get_declarative_json_path(g_name)
		if json_path == "":
			_fail("No declarative json path found for: " + g_name)
			continue
		print("  -> Found declarative config: ", json_path)
		
		# Test instantiation
		var wizard = registry.DeclarativeGuidedSetupScript.new()
		if not wizard.load_from_file(json_path):
			_fail("Failed to parse guided setup JSON at: " + json_path)
			continue
			
		var req_keys = wizard._get_required_schema_keys()
		print("  -> Game title: '", wizard._get_game_title(), "', required keys: ", req_keys.size())
		
		# Build a mock schema containing the required keys
		var mock_schema_options = []
		for k in req_keys:
			mock_schema_options.append({"name": k})
		var mock_schema = {"options": mock_schema_options}
		
		var val_res = registry.validate_and_create(g_name, mock_schema)
		if not val_res.get("valid", false) or val_res.get("wizard") == null:
			_fail("validate_and_create failed for " + g_name + ": " + str(val_res.get("reason")))
			continue
			
		var active_wizard = val_res["wizard"]
		var cfg = {}
		active_wizard.init_config(cfg)
		
		var steps = active_wizard._get_steps_data()
		print("  -> Wizard steps count: ", steps.size())
		if steps.size() == 0:
			_fail("Wizard has 0 steps for: " + g_name)
			continue
			
		var dummy_container = VBoxContainer.new()
		root.add_child(dummy_container)
		for s in steps:
			var s_num = s.get("num", 1)
			active_wizard.current_step = s_num
			active_wizard.build_wizard_ui(dummy_container, func(k, v):
				cfg[k] = v
			)
		if dummy_container.get_child_count() == 0:
			_fail("UI build generated 0 child controls for " + g_name)
		else:
			print("  -> Successfully built UI across all steps with ", dummy_container.get_child_count(), " total controls")
		dummy_container.queue_free()

	_finish()

func _finish() -> void:
	print("\n==================================================")
	if test_passed:
		print("  ALL GUIDED SETUP MULTI-GAME TESTS PASSED!")
	else:
		printerr("  GUIDED SETUP MULTI-GAME TEST FAILED!")
	print("==================================================")
	if lobby:
		lobby.queue_free()
	quit(0 if test_passed else 1)
