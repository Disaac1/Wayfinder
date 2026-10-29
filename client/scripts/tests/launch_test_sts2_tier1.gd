extends SceneTree

# =====================================================================
#             SLAY THE SPIRE 2 TIER 1 INTEGRATION TEST
# =====================================================================

var test_passed: bool = true
var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _fail(reason: String) -> void:
	printerr("[Test Failure] ", reason)
	test_passed = false
	if lobby:
		lobby.queue_free()
	quit(1)

func _finish() -> void:
	if lobby:
		lobby.queue_free()
	if test_passed:
		print("==================================================")
		print("  ALL SLAY THE SPIRE 2 TIER 1 INTEGRATION TESTS PASSED! ")
		print("==================================================")
		quit(0)
	else:
		quit(1)

func _run_test() -> void:
	print("==================================================")
	print("    Starting Slay the Spire 2 Tier 1 Support Test ")
	print("==================================================")

	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return

	lobby = lobby_scene.instantiate()
	root.add_child(lobby)

	var launcher = lobby.launcher

	# Load launch config directly into launcher presets
	var launch_path: String = "res://../backend/data/games/slay_the_spire_2/launch.json"
	var file = FileAccess.open(launch_path, FileAccess.READ)
	if not file:
		_fail("Could not find Slay the Spire 2 launch.json at: " + launch_path)
		return
	var preset: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	launcher.launcher_presets["Slay the Spire II"] = preset

	# -----------------------------------------------------------------
	# Test 1: Presets and Identity Resolver
	# -----------------------------------------------------------------
	print("[Test 1] Presets and Identity Resolver...")
	var canon_preset = launcher.get_preset("Slay the Spire II")
	if canon_preset.is_empty():
		_fail("Failed to resolve preset for 'Slay the Spire II'")
		return
	if canon_preset.get("support_tier") != 1:
		_fail("Expected support_tier 1, got " + str(canon_preset.get("support_tier")))
		return
	if canon_preset.get("launch_mode") != "direct":
		_fail("Expected launch_mode 'direct', got " + str(canon_preset.get("launch_mode")))
		return
	if canon_preset.get("steam_appid") != "2868840":
		_fail("Expected steam_appid '2868840', got " + str(canon_preset.get("steam_appid")))
		return
	print("  -> [PASS] Identified as Tier 1 direct launch with Steam AppID 2868840")

	# Test alias resolution
	var test_aliases = ["Slay the Spire 2", "slay_the_spire_2", "sts2", "slaythespire2", "Slay the Spire II"]
	for a in test_aliases:
		var resolved = launcher.get_preset(a)
		if resolved.is_empty() or resolved.get("game_name") != "Slay the Spire II":
			_fail("Failed to resolve alias: " + a)
			return
	print("  -> [PASS] Successfully resolved all Slay the Spire II aliases")

	# -----------------------------------------------------------------
	# Test 2: Executable Configuration & Subfolders
	# -----------------------------------------------------------------
	print("[Test 2] Executable Configuration & Subfolders...")
	var exec_name: String = canon_preset.get("client_executable", canon_preset.get("executable_name", ""))
	if exec_name != "SlayTheSpire2.exe":
		_fail("Expected executable 'SlayTheSpire2.exe', got '" + exec_name + "'")
		return
	var sub_folders: Array = canon_preset.get("sub_folders", [])
	if not "SlayTheSpire2" in sub_folders or not "Slay the Spire 2" in sub_folders:
		_fail("Expected 'SlayTheSpire2' and 'Slay the Spire 2' in sub_folders")
		return
	print("  -> [PASS] Target executable SlayTheSpire2.exe and subfolders verified")

	# -----------------------------------------------------------------
	# Test 3: Mod Package Auto-Extraction Definition
	# -----------------------------------------------------------------
	print("[Test 3] Mod Package Auto-Extraction Definition...")
	var packages: Array = canon_preset.get("packages", [])
	if packages.is_empty():
		_fail("Expected packages definition in preset")
		return
	var pkg: Dictionary = packages[0]
	if not "Archipelago.zip" in pkg.get("download_url", ""):
		_fail("Expected download_url to target Archipelago.zip")
		return
	if pkg.get("extract_target") != "mods/Archipelago":
		_fail("Expected extract_target 'mods/Archipelago', got " + str(pkg.get("extract_target")))
		return
	if pkg.get("check_file") != "mods/Archipelago/Archipelago.dll":
		_fail("Expected check_file 'mods/Archipelago/Archipelago.dll', got " + str(pkg.get("check_file")))
		return
	print("  -> [PASS] Mod package Archipelago.zip for mods/Archipelago verified")

	# -----------------------------------------------------------------
	# Test 4: Auto-Connect & Clipboard Action
	# -----------------------------------------------------------------
	print("[Test 4] Auto-Connect & Clipboard Action...")
	if not canon_preset.get("auto_connect", false):
		_fail("Expected auto_connect to be true")
		return
	if canon_preset.get("clipboard_action") != "copy_server_address":
		_fail("Expected clipboard_action 'copy_server_address'")
		return
	print("  -> [PASS] Auto-connect and copy_server_address verified")

	# -----------------------------------------------------------------
	# Test 5: Guided Setup Schema Validation
	# -----------------------------------------------------------------
	print("[Test 5] Guided Setup Schema Validation...")
	var setup_path: String = "res://../backend/data/games/slay_the_spire_2/guided_setup.json"
	var setup_file = FileAccess.open(setup_path, FileAccess.READ)
	if not setup_file:
		_fail("Could not find guided_setup.json at: " + setup_path)
		return
	var setup_data: Dictionary = JSON.parse_string(setup_file.get_as_text())
	setup_file.close()

	var default_config: Dictionary = setup_data.get("default_config", {})
	if not default_config.has("characters") or not default_config.has("pick_num_characters") or not default_config.has("lock_characters") or not default_config.has("death_link"):
		_fail("guided_setup.json missing primary default_config keys")
		return
	var steps: Array = setup_data.get("steps", [])
	if steps.size() < 4:
		_fail("Expected at least 4 setup wizard steps, got " + str(steps.size()))
		return
	print("  -> [PASS] Guided setup wizard schema validated with ", steps.size(), " steps")

	# -----------------------------------------------------------------
	# Test 6: APWorld Presence Verification
	# -----------------------------------------------------------------
	print("[Test 6] APWorld Presence Verification...")
	var backend_apworld = "res://../backend/archipelago_core/custom_worlds/spire2.apworld"
	var client_apworld = "res://Archipelago/custom_worlds/spire2.apworld"
	if not FileAccess.file_exists(backend_apworld):
		_fail("Missing backend custom world: " + backend_apworld)
		return
	if not FileAccess.file_exists(client_apworld):
		_fail("Missing client custom world: " + client_apworld)
		return
	print("  -> [PASS] spire2.apworld verified in both backend and client bundles")

	# -----------------------------------------------------------------
	# Test 7: Icon Presence Verification
	# -----------------------------------------------------------------
	print("[Test 7] Icon Presence Verification...")
	var icon_path = "res://../backend/data/games/slay_the_spire_2/icon.png"
	if not FileAccess.file_exists(icon_path):
		_fail("Missing icon at: " + icon_path)
		return
	print("  -> [PASS] Game icon verified at: ", icon_path)

	_finish()
