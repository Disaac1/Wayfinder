extends SceneTree

# =====================================================================
#             APWORLD AGNOSTIC PIPELINE INTEGRATION TEST
# =====================================================================

var test_passed: bool = true
var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _fail(reason: String) -> void:
	printerr("[Test Failure] ", reason)
	test_passed = false

func _run_test() -> void:
	print("==================================================")
	print("  Starting APWorld Agnostic Integration Test")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		_finish()
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	await lobby.launcher.load_launcher_config()
	
	# Test 1: Synthesized Generic Preset for Unknown Community APWorld
	print("[Test] 1. Validating dynamic fallback preset for unknown community APWorld...")
	var unknown_game: String = "Custom Spelunky World"
	var fallback_preset: Dictionary = lobby.launcher.get_preset(unknown_game)
	if fallback_preset.is_empty():
		_fail("get_preset returned empty dictionary for unknown APWorld: " + unknown_game)
		_finish()
		return
		
	if fallback_preset.get("game_name") != unknown_game:
		_fail("Expected game_name '" + unknown_game + "', got '" + str(fallback_preset.get("game_name")) + "'")
		
	if fallback_preset.get("launch_mode") != "ap_client":
		_fail("Expected launch_mode 'ap_client', got '" + str(fallback_preset.get("launch_mode")) + "'")
		
	print("[Test] Unknown APWorld successfully resolved fallback preset: ", fallback_preset.get("client_component"))

	# Test 2: Dynamic Acronym Generation & Slot Naming
	print("[Test] 2. Testing smart acronym generator on arbitrary titles...")
	var tag1: String = lobby.YamlBuilder.get_short_game_tag("Custom Spelunky World")
	if tag1 != "CSW":
		_fail("Expected acronym 'CSW', got '" + tag1 + "'")
		
	var tag2: String = lobby.YamlBuilder.get_short_game_tag("Super Ultra Awesome Game 2")
	if tag2 != "SUAG2":
		_fail("Expected acronym 'SUAG2', got '" + tag2 + "'")
		
	# With custom declared tag in preset
	var tag_declared: String = lobby.YamlBuilder.get_short_game_tag("Hollow Knight", "HK")
	if tag_declared != "HK":
		_fail("Expected declared tag 'HK', got '" + tag_declared + "'")
		
	var slot_str: String = lobby.YamlBuilder.get_slot_name("Alice", "Custom Spelunky World", 2)
	if slot_str != "Alice (CSW)":
		_fail("Expected slot name 'Alice (CSW)', got '" + slot_str + "'")
		
	# Canonical short tags for known titles
	var tag_bw = lobby.YamlBuilder.get_short_game_tag("Pokemon Black and White")
	if tag_bw != "BW":
		_fail("Expected 'BW', got '" + tag_bw + "'")
	var tag_lm = lobby.YamlBuilder.get_short_game_tag("Luigi's Mansion")
	if tag_lm != "LM1":
		_fail("Expected 'LM1', got '" + tag_lm + "'")
	var tag_fusion = lobby.YamlBuilder.get_short_game_tag("Metroid Fusion")
	if tag_fusion != "Fusion":
		_fail("Expected 'Fusion', got '" + tag_fusion + "'")

	var multi_yaml = lobby.YamlBuilder.compile_yaml(["Pokemon Black and White", "Luigi's Mansion"], "", "Test", "ROOM", {}, lobby.launcher.launcher_presets)
	if not "name: Test (BW)" in multi_yaml:
		_fail("compile_yaml missing 'name: Test (BW)' in: " + multi_yaml)
	if not "name: Test (LM1)" in multi_yaml:
		_fail("compile_yaml missing 'name: Test (LM1)' in: " + multi_yaml)

	print("[Test] Dynamic acronyms and slot names verified: ", [tag1, tag2, slot_str, tag_bw, tag_lm, tag_fusion])

	# Test 3: Declarative Packages Pipeline Schema
	print("[Test] 3. Testing packages array parsing in lobby...")
	var mock_pkg_preset: Dictionary = {
		"game_name": "Test Native Modded Game",
		"packages": [
			{
				"name": "Core Engine Hooks",
				"download_url": "http://localhost:8080/tools/core_hooks.zip",
				"check_file": "bin/hooks.dll",
				"extract_target": "bin",
				"backup_files": ["main.dll"]
			},
			{
				"name": "Archipelago Mod",
				"download_url": "http://localhost:8080/tools/ap_mod.zip",
				"check_file": "mods/ap.dll",
				"extract_target": "mods"
			}
		]
	}
	
	var extracted_pkgs: Array = lobby._get_preset_packages(mock_pkg_preset)
	if extracted_pkgs.size() != 2:
		_fail("Expected 2 packages, got " + str(extracted_pkgs.size()))
	elif extracted_pkgs[0].get("name") != "Core Engine Hooks":
		_fail("Package name mismatch: " + str(extracted_pkgs[0].get("name")))
	elif extracted_pkgs[0].get("backup_files") != ["main.dll"]:
		_fail("Backup files mismatch: " + str(extracted_pkgs[0].get("backup_files")))
	else:
		print("[Test] Declarative packages schema parsed successfully: ", extracted_pkgs.size(), " packages.")

	# Test 4: Backwards-Compatible Legacy Key Synthesis
	print("[Test] 4. Testing legacy modding_api_* and mods_* synthesis...")
	var legacy_preset: Dictionary = {
		"game_name": "Legacy Mod Game",
		"modding_api_url": "http://example.com/api.zip",
		"modding_api_check_file": "managed/api.dll",
		"modding_api_extract_target": "managed",
		"mods_url": "http://example.com/mods.zip",
		"mods_check_file": "mods/mod.dll",
		"mods_extract_target": "mods"
	}
	var synthesized_pkgs: Array = lobby._get_preset_packages(legacy_preset)
	if synthesized_pkgs.size() != 2:
		_fail("Expected 2 synthesized packages, got " + str(synthesized_pkgs.size()))
	else:
		print("[Test] Legacy packages synthesized successfully.")

	# Test 5: Agnostic Patch Progress Tracking Schema
	print("[Test] 5. Testing patch_progress_tracking on Symphony of the Night...")
	var sotn_preset: Dictionary = lobby.launcher.get_preset("Symphony of the Night")
	var track_cfg: Dictionary = sotn_preset.get("patch_progress_tracking", {})
	if track_cfg.is_empty():
		_fail("Expected patch_progress_tracking dictionary in SOTN preset")
	elif track_cfg.get("completion_extension") != ".cue":
		_fail("Expected completion_extension '.cue', got " + str(track_cfg.get("completion_extension")))
	elif track_cfg.get("expected_bytes") != 538655040:
		_fail("Expected expected_bytes 538655040, got " + str(track_cfg.get("expected_bytes")))
	else:
		print("[Test] SOTN patch progress tracking verified cleanly from configuration.")

	_finish()

func _finish() -> void:
	print("==================================================")
	if test_passed:
		print("  APWORLD AGNOSTIC INTEGRATION TEST PASSED!")
	else:
		printerr("  APWORLD AGNOSTIC INTEGRATION TEST FAILED!")
	print("==================================================")
	quit(0 if test_passed else 1)
