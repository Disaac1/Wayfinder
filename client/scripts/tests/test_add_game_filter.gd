extends SceneTree

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("--- Running Add Game Filter Test ---")
	
	var launcher_script = load("res://scripts/core/game_launcher.gd")
	var launcher = launcher_script.new()
	launcher.load_paths_config()
	launcher.load_roms_catalog()
	launcher.load_local_presets_sync()
	
	# Manually populate an experimental Tier 4 game into launcher_presets (simulating backend /api/launcher/config)
	launcher.launcher_presets["A Hat in Time"] = {
		"game_name": "A Hat in Time",
		"support_tier": 4,
		"launch_mode": "ap_client"
	}
	
	# 1. Test has_curated_preset
	print("[Test 1] Checking has_curated_preset on Tier 1-3 vs Tier 4...")
	assert(launcher.has_curated_preset("Pokemon Emerald") == true, "Pokemon Emerald must be curated")
	assert(launcher.has_curated_preset("Hollow Knight") == true, "Hollow Knight must be curated")
	assert(launcher.has_curated_preset("Super Mario 64") == true, "Super Mario 64 must be curated")
	assert(launcher.has_curated_preset("Castlevania - Symphony of the Night") == true, "SotN must be curated")
	assert(launcher.has_curated_preset("Plants vs. Zombies") == true, "PvZ must be curated")
	assert(launcher.has_curated_preset("Metroid Fusion") == true, "Metroid Fusion must be curated")
	assert(launcher.has_curated_preset("Elementipelago") == true, "Elementipelago must be curated")
	assert(launcher.has_curated_preset("Stardew Valley") == true, "Stardew Valley must be curated")
	
	assert(launcher.has_preset("A Hat in Time") == true, "A Hat in Time has preset")
	assert(launcher.has_curated_preset("A Hat in Time") == false, "A Hat in Time must NOT be curated")
	print("  -> Passed: Curated preset checks verified.")
	
	# 2. Test AddGameModal filtering
	print("[Test 2] Testing AddGameModal visibility and toggle behavior...")
	var modal_scene = load("res://scenes/modals/add_game_modal.tscn")
	var modal = modal_scene.instantiate()
	root.add_child(modal)
	
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
	
	assert(checkbox.button_pressed == false, "Checkbox should be unchecked by default on open")
	
	# With toggle OFF, only 3 games (Emerald, HK, SM64) should be visible
	var visible_buttons = []
	for child in grid.get_children():
		if child is Button and child.visible:
			visible_buttons.append(child.text)
			
	print("Visible games with toggle OFF: ", visible_buttons)
	assert(visible_buttons.size() == 3, "Only 3 curated games should be visible with toggle OFF, got: " + str(visible_buttons.size()))
	assert(visible_buttons.has("Pokemon Emerald"), "Pokemon Emerald should be visible")
	assert(visible_buttons.has("Hollow Knight"), "Hollow Knight should be visible")
	assert(visible_buttons.has("Super Mario 64"), "Super Mario 64 should be visible")
	assert(not visible_buttons.has("A Hat in Time"), "A Hat in Time should be hidden")
	assert(count_label.text == "3 Games", "CountLabel should show 3 Games")
	
	# Now toggle ON
	print("[Test 3] Toggling Show All Worlds ON...")
	checkbox.button_pressed = true
	
	visible_buttons.clear()
	for child in grid.get_children():
		if child is Button and child.visible:
			visible_buttons.append(child.text)
			
	print("Visible games with toggle ON: ", visible_buttons.size())
	assert(visible_buttons.size() == 6, "All 6 games should be visible with toggle ON, got: " + str(visible_buttons.size()))
	assert(visible_buttons.has("A Hat in Time"), "A Hat in Time should now be visible")
	assert(count_label.text == "6 Games", "CountLabel should show 6 Games")
	
	# Now toggle OFF again
	print("[Test 4] Toggling Show All Worlds OFF again...")
	checkbox.button_pressed = false
	visible_buttons.clear()
	for child in grid.get_children():
		if child is Button and child.visible:
			visible_buttons.append(child.text)
	assert(visible_buttons.size() == 3, "Only 3 curated games should be visible after toggling off")
	assert(count_label.text == "3 Games", "CountLabel should show 3 Games again")
	
	modal.queue_free()
	print("\n==================================================")
	print("  ADD GAME FILTER TEST PASSED SUCCESSFULLY!")
	print("==================================================")
	quit(0)
