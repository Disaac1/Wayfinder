extends SceneTree

var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Pokemon Emerald Guided Setup Test")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	# Test 1: Guided Setup Class Instantiation & Default Config
	await lobby._ensure_remote_guided_setup("Pokemon Emerald")
	print("[Test] 1. Instantiating Pokemon Emerald Guided Setup dynamically via GuidedSetupRegistry...")
	if not lobby.GuidedSetupRegistry.has_guided_setup("Pokemon Emerald"):
		_fail("GuidedSetupRegistry missing registration/file for Pokemon Emerald")
		return
		
	var valid_mock_schema = {
		"options": [
			{"name": "goal"}, {"name": "norman_count"}, {"name": "elite_four_count"}, {"name": "badges"},
			{"name": "hms"}, {"name": "key_items"}, {"name": "overworld_items"}, {"name": "wild_pokemon"},
			{"name": "starters"}, {"name": "trainer_parties"}, {"name": "exp_modifier"}, {"name": "reusable_tms_tutors"},
			{"name": "turbo_a"}, {"name": "better_shops"}
		]
	}
	var create_res = lobby.GuidedSetupRegistry.validate_and_create("Pokemon Emerald", valid_mock_schema)
	if not create_res.get("valid", false) or create_res.get("wizard") == null:
		_fail("Failed to validate and create Pokemon Emerald wizard: " + str(create_res.get("reason")))
		return
		
	var wizard = create_res["wizard"]
	var test_config = {}
	wizard.init_config(test_config)
	
	if wizard.current_config.get("goal") != "champion":
		_fail("Default goal expected 'champion', got: " + str(wizard.current_config.get("goal")))
		return
	if wizard.current_config.get("norman_count") != 4:
		_fail("Default norman_count expected 4, got: " + str(wizard.current_config.get("norman_count")))
		return
	print("[Test] Default config verified: ", wizard.current_config)
	
	# Test 2: UI Building across all 5 Wizard Steps
	print("[Test] 2. Testing UI construction across Steps 1 through 5...")
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
	
	# Test 3: Preset Application & YAML Compilation
	print("[Test] 3. Testing Preset Application and YamlBuilder compilation...")
	test_config["goal"] = "steven"
	test_config["norman_count"] = 5
	test_config["exp_modifier"] = 200
	test_config["wild_pokemon"] = "match_base_stats_and_type"
	test_config["turbo_a"] = true
	
	var compiled_yaml = lobby.YamlBuilder.compile_yaml(["Pokemon Emerald"], "Pokemon Emerald", "Tester", "TEST1234", {"Pokemon Emerald": test_config})
	print("[Test] Compiled YAML snippet:\n", compiled_yaml)
	
	if not "goal: steven" in compiled_yaml or not "exp_modifier: 200" in compiled_yaml:
		_fail("Compiled YAML did not contain updated guided setup options")
		return
		
	print("[Test] YAML compilation verified successfully!")
	
	# Test 4: Dynamic Schema Validation & Fallback Check
	print("[Test] 4. Testing Dynamic Schema Validation & Fallback Guard...")
	var test_valid_res = lobby.GuidedSetupRegistry.validate_and_create("Pokemon Emerald", valid_mock_schema)
	if not test_valid_res.get("valid", false):
		_fail("Schema validation failed on valid mock schema: " + test_valid_res.get("reason", ""))
		return
	print("[Test] Valid schema passed validation!")
	
	var invalid_mock_schema = {
		"options": [
			{"name": "badges"}, {"name": "hms"} # missing goal, norman_count, etc.
		]
	}
	var res_invalid = lobby.GuidedSetupRegistry.validate_and_create("Pokemon Emerald", invalid_mock_schema)
	if res_invalid.get("valid", false):
		_fail("Incompatible schema should have failed validation but passed!")
		return
	print("[Test] Incompatible schema correctly triggered fallback guard: ", res_invalid.get("reason"))
	
	lobby.queue_free()
	
	print("\n==================================================")
	print("  POKEMON EMERALD GUIDED SETUP TEST PASSED!")
	print("==================================================")
	quit(0)

func _fail(reason: String) -> void:
	printerr("[Test FAIL] ", reason)
	if lobby:
		lobby.queue_free()
	quit(1)
