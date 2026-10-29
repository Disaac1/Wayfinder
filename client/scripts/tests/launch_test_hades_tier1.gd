extends SceneTree

# =====================================================================
#                 HADES TIER 1 INTEGRATION TEST
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
		print("     ALL HADES TIER 1 INTEGRATION TESTS PASSED!   ")
		print("==================================================")
		quit(0)
	else:
		quit(1)

func _run_test() -> void:
	print("==================================================")
	print("        Starting Hades Tier 1 Support Test        ")
	print("==================================================")

	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return

	lobby = lobby_scene.instantiate()
	root.add_child(lobby)

	var launcher = lobby.launcher

	# Load launch config directly into launcher presets
	var launch_path: String = "res://../backend/data/games/hades/launch.json"
	var file = FileAccess.open(launch_path, FileAccess.READ)
	if not file:
		_fail("Could not find Hades launch.json at: " + launch_path)
		return
	var preset: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	launcher.launcher_presets["Hades"] = preset

	# -----------------------------------------------------------------
	# Test 1: Presets and Identity Resolver
	# -----------------------------------------------------------------
	print("[Test 1] Presets and Identity Resolver...")
	var canon_preset = launcher.get_preset("Hades")
	if canon_preset.is_empty():
		_fail("Failed to resolve preset for 'Hades'")
		return
	if canon_preset.get("support_tier") != 1:
		_fail("Expected support_tier 1, got " + str(canon_preset.get("support_tier")))
		return
	if canon_preset.get("launch_mode") != "ap_client":
		_fail("Expected launch_mode 'ap_client', got " + str(canon_preset.get("launch_mode")))
		return
	if canon_preset.get("steam_appid") != "1145360":
		_fail("Expected steam_appid '1145360', got " + str(canon_preset.get("steam_appid")))
		return
	print("  -> [PASS] Identified as Tier 1 ap_client with Steam AppID 1145360")

	# Test alias resolution
	var test_aliases = ["hades", "Hades 1", "hades1", "Polycosmos"]
	for a in test_aliases:
		var resolved = launcher.get_preset(a)
		if resolved.is_empty() or resolved.get("game_name") != "Hades":
			_fail("Failed to resolve alias: " + a)
			return
	print("  -> [PASS] Successfully resolved all Hades aliases")

	# -----------------------------------------------------------------
	# Test 2: Executable Configuration & Subfolders
	# -----------------------------------------------------------------
	print("[Test 2] Executable Configuration & Subfolders...")
	var exec_name: String = canon_preset.get("client_executable", canon_preset.get("executable_name", ""))
	if exec_name != "Hades.exe":
		_fail("Expected executable 'Hades.exe', got '" + exec_name + "'")
		return
	var sub_folders: Array = canon_preset.get("sub_folders", [])
	if not "Hades" in sub_folders or not "Hades/x64" in sub_folders:
		_fail("Expected 'Hades' and 'Hades/x64' in sub_folders")
		return
	print("  -> [PASS] Target executable Hades.exe and subfolders verified")

	# -----------------------------------------------------------------
	# Test 3: Client Component & Auto-Connect
	# -----------------------------------------------------------------
	print("[Test 3] Client Component & Auto-Connect...")
	if canon_preset.get("client_tool") != "archipelago_client":
		_fail("Expected client_tool 'archipelago_client', got '" + str(canon_preset.get("client_tool")) + "'")
		return
	if canon_preset.get("client_component") != "Hades Client":
		_fail("Expected client_component 'Hades Client', got '" + str(canon_preset.get("client_component")) + "'")
		return
	if not canon_preset.get("auto_connect", false):
		_fail("Expected auto_connect to be true")
		return
	if canon_preset.get("clipboard_action") != "copy_server_address":
		_fail("Expected clipboard_action 'copy_server_address'")
		return
	print("  -> [PASS] Archipelago 'Hades Client' auto-connect and clipboard configuration verified")

	# -----------------------------------------------------------------
	# Test 4: Host.yaml Synchronization & {game_dir}/StyxScribe.py
	# -----------------------------------------------------------------
	print("[Test 4] Host.yaml Synchronization & {game_dir}/StyxScribe.py Evaluation...")
	var test_yaml_path: String = ProjectSettings.globalize_path("res://test_hades_host.yaml")
	var initial_yaml: String = """
hades_options:
  styx_scribe_path: ""
"""
	var write_fa = FileAccess.open("res://test_hades_host.yaml", FileAccess.WRITE)
	write_fa.store_string(initial_yaml)
	write_fa.close()

	var mock_game_path = "C:/Steam/steamapps/common/Hades/Hades.exe"
	launcher._write_synced_host_yaml_file(test_yaml_path, mock_game_path, "", "", "localhost:38000")

	var read_fa = FileAccess.open("res://test_hades_host.yaml", FileAccess.READ)
	var synced_content: String = read_fa.get_as_text()
	read_fa.close()
	DirAccess.remove_absolute(test_yaml_path)

	var expected_scribe = "C:/Steam/steamapps/common/Hades/StyxScribe.py"
	if not expected_scribe in synced_content:
		_fail("host.yaml missing synced styx_scribe_path: " + expected_scribe + "\nContent was:\n" + synced_content)
		return
	print("  -> [PASS] host.yaml successfully synchronized with hades_options.styx_scribe_path: ", expected_scribe)

	# -----------------------------------------------------------------
	# Test 5: Mod Packages & ModImporter Configuration
	# -----------------------------------------------------------------
	print("[Test 5] Mod Packages & ModImporter Configuration...")
	var packages: Array = canon_preset.get("packages", [])
	if packages.size() < 4:
		_fail("Expected at least 4 mod packages, got " + str(packages.size()))
		return
	var pkg_names = []
	for p in packages:
		pkg_names.append(p.get("name", ""))
	if not "ModImporter" in pkg_names or not "ModUtil" in pkg_names or not "StyxScribe" in pkg_names or not "Polycosmos AP Mod" in pkg_names:
		_fail("Missing expected packages in configuration: " + str(pkg_names))
		return
	if not canon_preset.has("mod_importer"):
		_fail("Expected mod_importer configuration block in preset")
		return
	print("  -> [PASS] All 4 packages and mod_importer hook verified")

	# -----------------------------------------------------------------
	# Test 6: PopTracker Configuration
	# -----------------------------------------------------------------
	print("[Test 6] PopTracker Configuration...")
	var tracker: Dictionary = canon_preset.get("tracker", {})
	if not tracker.get("supported", false):
		_fail("Expected tracker.supported to be true")
		return
	if tracker.get("package_uid") != "hades_ap":
		_fail("Expected package_uid 'hades_ap', got '" + str(tracker.get("package_uid")) + "'")
		return
	if tracker.get("pack_version") != "3.0.3":
		_fail("Expected pack_version '3.0.3', got '" + str(tracker.get("pack_version")) + "'")
		return
	if tracker.get("pack_sha256") != "1267876c4033c911ca2d2b2a77a07429c69bbe67a5104a0e2fc7f617831c0031":
		_fail("Mismatched PopTracker sha256 checksum")
		return
	print("  -> [PASS] PopTracker package hades_ap v3.0.3 verified with autotracking")

	# -----------------------------------------------------------------
	# Test 7: Guided Setup Schema Validation
	# -----------------------------------------------------------------
	print("[Test 7] Guided Setup Schema Validation...")
	var setup_path: String = "res://../backend/data/games/hades/guided_setup.json"
	var setup_file = FileAccess.open(setup_path, FileAccess.READ)
	if not setup_file:
		_fail("Could not find guided_setup.json at: " + setup_path)
		return
	var setup_data: Dictionary = JSON.parse_string(setup_file.get_as_text())
	setup_file.close()

	var default_config: Dictionary = setup_data.get("default_config", {})
	if not default_config.has("heat_system") or not default_config.has("location_system") or not default_config.has("weaponsanity") or not default_config.has("death_link"):
		_fail("guided_setup.json missing primary default_config keys")
		return
	var steps: Array = setup_data.get("steps", [])
	if steps.size() < 3:
		_fail("Expected at least 3 setup wizard steps, got " + str(steps.size()))
		return
	print("  -> [PASS] Guided setup wizard schema validated with ", steps.size(), " steps")

	# -----------------------------------------------------------------
	# Test 8: APWorld Presence Verification
	# -----------------------------------------------------------------
	print("[Test 8] APWorld Presence Verification...")
	var backend_apworld = "res://../backend/archipelago_core/custom_worlds/hades.apworld"
	var client_apworld = "res://Archipelago/custom_worlds/hades.apworld"
	if not FileAccess.file_exists(backend_apworld):
		_fail("Missing backend custom world: " + backend_apworld)
		return
	if not FileAccess.file_exists(client_apworld):
		_fail("Missing client custom world: " + client_apworld)
		return
	print("  -> [PASS] hades.apworld verified in both backend and client bundles")

	# -----------------------------------------------------------------
	# Test 9: Icon Presence Verification
	# -----------------------------------------------------------------
	print("[Test 9] Icon Presence Verification...")
	var icon_path = "res://../backend/data/games/hades/icon.png"
	if not FileAccess.file_exists(icon_path):
		_fail("Missing icon at: " + icon_path)
		return
	print("  -> [PASS] Game icon verified at: ", icon_path)

	_finish()
