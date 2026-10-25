extends SceneTree

var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Super Mario 64 Guided Setup Test")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	# Test 1: Registry lookup & SM64 Guided Setup Instantiation
	await lobby._ensure_remote_guided_setup("Super Mario 64")
	print("[Test] 1. Verifying GuidedSetupRegistry lookup & instantiating SM64 Guided Setup...")
	if not lobby.GuidedSetupRegistry.has_guided_setup("Super Mario 64"):
		_fail("GuidedSetupRegistry missing registration for Super Mario 64")
		return
		
	var mock_valid_schema = {
		"options": [
			{"name": "completion_type"}, {"name": "amount_of_stars"}, {"name": "stars_to_finish"},
			{"name": "area_rando"}, {"name": "progressive_keys"}, {"name": "enable_move_rando"}
		]
	}
	var create_res = lobby.GuidedSetupRegistry.validate_and_create("Super Mario 64", mock_valid_schema)
	if not create_res.get("valid", false) or create_res.get("wizard") == null:
		_fail("Failed to validate and create SM64 wizard: " + str(create_res.get("reason")))
		return
		
	var wizard = create_res["wizard"]
	var test_config = {}
	wizard.init_config(test_config)
	
	if wizard.current_config.get("completion_type") != 0:
		_fail("Default completion_type expected 0, got: " + str(wizard.current_config.get("completion_type")))
		return
	if wizard.current_config.get("amount_of_stars") != 120:
		_fail("Default amount_of_stars expected 120, got: " + str(wizard.current_config.get("amount_of_stars")))
		return
	print("[Test] Default SM64 config verified: ", wizard.current_config)
	
	# Test 2: UI Building across all 5 Wizard Steps
	print("[Test] 2. Testing SM64 UI construction across Steps 1 through 5...")
	var dummy_container = VBoxContainer.new()
	root.add_child(dummy_container)
	
	for step_num in range(1, 6):
		wizard.current_step = step_num
		wizard.build_wizard_ui(dummy_container, func(k, v):
			test_config[k] = v
		)
		if dummy_container.get_child_count() == 0:
			_fail("Step " + str(step_num) + " failed to generate UI elements")
			return
		print("  -> Step " + str(step_num) + " built successfully with " + str(dummy_container.get_child_count()) + " child controls")
		
	dummy_container.queue_free()
	
	# Test 3: Preset Application & YamlBuilder compilation
	print("[Test] 3. Testing SM64 Preset Application and YamlBuilder compilation...")
	test_config["completion_type"] = 1
	test_config["amount_of_stars"] = 70
	test_config["stars_to_finish"] = 50
	test_config["area_rando"] = 3
	test_config["enable_move_rando"] = true
	test_config["death_link"] = true
	
	var compiled_yaml = lobby.YamlBuilder.compile_yaml(["Super Mario 64"], "Super Mario 64", "MarioPlayer", "SM64ROOM", {"Super Mario 64": test_config})
	print("[Test] Compiled SM64 YAML snippet:\n", compiled_yaml)
	
	if not "completion_type: 1" in compiled_yaml or not "amount_of_stars: 70" in compiled_yaml or not "area_rando: 3" in compiled_yaml:
		_fail("Compiled YAML did not contain updated SM64 guided setup options")
		return
		
	print("[Test] SM64 YAML compilation verified successfully!")
	
	# Test 4: Dynamic Schema Validation for Super Mario 64
	print("[Test] 4. Testing SM64 Dynamic Schema Validation...")
	var val_res = lobby.GuidedSetupRegistry.validate_and_create("Super Mario 64", mock_valid_schema)
	if not val_res.get("valid", false):
		_fail("Valid SM64 schema failed validation: " + val_res.get("reason", ""))
		return
	print("[Test] Valid SM64 schema passed validation!")
	
	lobby.queue_free()
	
	print("\n==================================================")
	print("  SUPER MARIO 64 GUIDED SETUP TEST PASSED!")
	print("==================================================")
	quit(0)

func _fail(reason: String) -> void:
	printerr("[Test FAIL] ", reason)
	if lobby:
		lobby.queue_free()
	quit(1)
