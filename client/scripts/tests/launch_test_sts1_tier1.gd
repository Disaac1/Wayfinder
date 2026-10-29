extends SceneTree

# =====================================================================
#             SLAY THE SPIRE 1 TIER 1 INTEGRATION TEST
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
		print("  ALL SLAY THE SPIRE 1 TIER 1 INTEGRATION TESTS PASSED! ")
		print("==================================================")
		quit(0)
	else:
		quit(1)

func _run_test() -> void:
	print("==================================================")
	print("    Starting Slay the Spire 1 Tier 1 Support Test ")
	print("==================================================")

	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return

	lobby = lobby_scene.instantiate()
	root.add_child(lobby)

	var launcher = lobby.launcher

	# Load launch config directly into launcher presets
	var launch_path: String = "res://../backend/data/games/slay_the_spire/launch.json"
	var file = FileAccess.open(launch_path, FileAccess.READ)
	if not file:
		_fail("Could not find Slay the Spire launch.json at: " + launch_path)
		return
	var preset: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	launcher.launcher_presets["Slay the Spire"] = preset

	# -----------------------------------------------------------------
	# Test 1: Presets and Identity Resolver
	# -----------------------------------------------------------------
	print("[Test 1] Presets and Identity Resolver...")
	var canon_preset = launcher.get_preset("Slay the Spire")
	if canon_preset.is_empty():
		_fail("Failed to resolve preset for 'Slay the Spire'")
		return
	if canon_preset.get("support_tier") != 1:
		_fail("Expected support_tier 1, got " + str(canon_preset.get("support_tier")))
		return
	if canon_preset.get("launch_mode") != "direct":
		_fail("Expected launch_mode 'direct', got " + str(canon_preset.get("launch_mode")))
		return
	if canon_preset.get("steam_appid") != "646570":
		_fail("Expected steam_appid '646570', got " + str(canon_preset.get("steam_appid")))
		return
	print("  -> [PASS] Identified as Tier 1 direct launch with Steam AppID 646570")

	# Test alias resolution
	var test_aliases = ["slay_the_spire", "sts", "sts1", "slaythespire", "Slay The Spire"]
	for a in test_aliases:
		var resolved = launcher.get_preset(a)
		if resolved.is_empty() or resolved.get("game_name") != "Slay the Spire":
			_fail("Failed to resolve alias: " + a)
			return
	print("  -> [PASS] Successfully resolved all Slay the Spire aliases")

	# -----------------------------------------------------------------
	# Test 2: Executable Configuration & Subfolders
	# -----------------------------------------------------------------
	print("[Test 2] Executable Configuration & Subfolders...")
	var exec_name: String = canon_preset.get("client_executable", canon_preset.get("executable_name", ""))
	if exec_name != "SlayTheSpire.exe":
		_fail("Expected executable 'SlayTheSpire.exe', got '" + exec_name + "'")
		return
	var sub_folders: Array = canon_preset.get("sub_folders", [])
	if not "SlayTheSpire" in sub_folders or not "Slay the Spire" in sub_folders:
		_fail("Expected 'SlayTheSpire' and 'Slay the Spire' in sub_folders")
		return
	var exec_aliases: Array = canon_preset.get("executable_aliases", [])
	if not "ModTheSpire.exe" in exec_aliases or not "ModTheSpire.jar" in exec_aliases:
		_fail("Expected ModTheSpire in executable_aliases")
		return
	print("  -> [PASS] Target executable SlayTheSpire.exe, aliases, and subfolders verified")

	# -----------------------------------------------------------------
	# Test 3: Config Writer Evaluation
	# -----------------------------------------------------------------
	print("[Test 3] Config Writer Evaluation...")
	if not canon_preset.has("config_writer"):
		_fail("Expected config_writer in preset")
		return
	var writer_cfg = canon_preset.get("config_writer", {})
	var file_path_template = writer_cfg.get("file_path", "")
	if not "preferences/ArchipelagoMW-2.0_archipelagoConfig" in file_path_template:
		_fail("Expected file_path to target preferences/ArchipelagoMW-2.0_archipelagoConfig")
		return

	var mock_context = {
		"game_dir": "C:/Steam/steamapps/common/SlayTheSpire",
		"server_clean_url": "wayfinder.disaac1.com:38000",
		"slot_name": "HeroPlayer"
	}
	var interpolated_path = launcher.interpolate_template(file_path_template, mock_context)
	var expected_path = "C:/Steam/steamapps/common/SlayTheSpire/preferences/ArchipelagoMW-2.0_archipelagoConfig"
	if interpolated_path != expected_path:
		_fail("Interpolated config path mismatch: " + interpolated_path + " vs " + expected_path)
		return

	var interpolated_content = launcher.interpolate_template(writer_cfg.get("template", ""), mock_context)
	if not "ConnectAddress=wayfinder.disaac1.com:38000" in interpolated_content or not "ConnectSlot=HeroPlayer" in interpolated_content:
		_fail("Interpolated content missing connection credentials: " + interpolated_content)
		return
	print("  -> [PASS] Dynamic mod preferences config writer verified")

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
	var setup_path: String = "res://../backend/data/games/slay_the_spire/guided_setup.json"
	var setup_file = FileAccess.open(setup_path, FileAccess.READ)
	if not setup_file:
		_fail("Could not find guided_setup.json at: " + setup_path)
		return
	var setup_data: Dictionary = JSON.parse_string(setup_file.get_as_text())
	setup_file.close()

	var default_config: Dictionary = setup_data.get("default_config", {})
	if not default_config.has("characters") or not default_config.has("pick_num_characters") or not default_config.has("ascension") or not default_config.has("death_link"):
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
	var backend_apworld = "res://../backend/archipelago_core/custom_worlds/spire.apworld"
	var client_apworld = "res://Archipelago/custom_worlds/spire.apworld"
	if not FileAccess.file_exists(backend_apworld):
		_fail("Missing backend custom world: " + backend_apworld)
		return
	if not FileAccess.file_exists(client_apworld):
		_fail("Missing client custom world: " + client_apworld)
		return
	print("  -> [PASS] spire.apworld verified in both backend and client bundles")

	# -----------------------------------------------------------------
	# Test 7: Icon Presence Verification
	# -----------------------------------------------------------------
	print("[Test 7] Icon Presence Verification...")
	var icon_path = "res://../backend/data/games/slay_the_spire/icon.png"
	if not FileAccess.file_exists(icon_path):
		_fail("Missing icon at: " + icon_path)
		return
	print("  -> [PASS] Game icon verified at: ", icon_path)

	_finish()
