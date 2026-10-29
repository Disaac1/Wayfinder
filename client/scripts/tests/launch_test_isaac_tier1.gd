extends SceneTree

# =====================================================================
#        THE BINDING OF ISAAC: REPENTANCE TIER 1 INTEGRATION TEST
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
		print("  ALL ISAAC TIER 1 INTEGRATION TESTS PASSED!     ")
		print("==================================================")
		quit(0)
	else:
		quit(1)

func _run_test() -> void:
	print("==================================================")
	print("  Starting The Binding of Isaac Repentance Test   ")
	print("==================================================")

	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return

	lobby = lobby_scene.instantiate()
	root.add_child(lobby)

	var launcher = lobby.launcher

	# Load launch config directly into launcher presets
	var launch_path: String = "res://../backend/data/games/the_binding_of_isaac_repentance/launch.json"
	var file = FileAccess.open(launch_path, FileAccess.READ)
	if not file:
		_fail("Could not find Isaac launch.json at: " + launch_path)
		return
	var preset: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	launcher.launcher_presets["The Binding of Isaac Repentance"] = preset

	# -----------------------------------------------------------------
	# Test 1: Presets and Identity Resolver
	# -----------------------------------------------------------------
	print("[Test 1] Presets and Identity Resolver...")
	var canon_preset = launcher.get_preset("The Binding of Isaac Repentance")
	if canon_preset.is_empty():
		_fail("Failed to resolve preset for 'The Binding of Isaac Repentance'")
		return
	if canon_preset.get("support_tier") != 1:
		_fail("Expected support_tier 1, got " + str(canon_preset.get("support_tier")))
		return
	if canon_preset.get("launch_mode") != "direct":
		_fail("Expected launch_mode 'direct', got " + str(canon_preset.get("launch_mode")))
		return
	if canon_preset.get("steam_appid") != "250900":
		_fail("Expected steam_appid '250900', got " + str(canon_preset.get("steam_appid")))
		return
	if not canon_preset.get("prefer_steam_protocol", false):
		_fail("Expected prefer_steam_protocol to be true")
		return
	print("  -> [PASS] Identified as Tier 1 Steam game (AppID 250900)")

	# Test alias resolution
	var test_aliases = ["The Binding of Isaac: Repentance", "Binding of Isaac", "tboir", "isaac"]
	for a in test_aliases:
		var resolved = launcher.get_preset(a)
		if resolved.is_empty() or resolved.get("game_name") != "The Binding of Isaac Repentance":
			_fail("Failed to resolve alias: " + a)
			return
	print("  -> [PASS] Successfully resolved all Isaac aliases")

	# -----------------------------------------------------------------
	# Test 2: Executable Configuration & Subfolders
	# -----------------------------------------------------------------
	print("[Test 2] Executable Configuration & Subfolders...")
	var exec_name: String = canon_preset.get("client_executable", canon_preset.get("executable_name", ""))
	if exec_name != "isaac-ng.exe":
		_fail("Expected executable 'isaac-ng.exe', got '" + exec_name + "'")
		return
	var sub_folders: Array = canon_preset.get("sub_folders", [])
	if not "The Binding of Isaac Rebirth" in sub_folders:
		_fail("Expected 'The Binding of Isaac Rebirth' in sub_folders")
		return
	print("  -> [PASS] Target executable isaac-ng.exe and subfolders verified")

	# -----------------------------------------------------------------
	# Test 3: Companion Client Tool & Clipboard Auto-Connect
	# -----------------------------------------------------------------
	print("[Test 3] Companion Client Tool & Clipboard Auto-Connect...")
	if canon_preset.get("client_tool") != "archipelago_client":
		_fail("Expected client_tool 'archipelago_client', got '" + str(canon_preset.get("client_tool")) + "'")
		return
	if canon_preset.get("client_component") != "Isaac Client":
		_fail("Expected client_component 'Isaac Client', got '" + str(canon_preset.get("client_component")) + "'")
		return
	if not canon_preset.get("auto_connect", false):
		_fail("Expected auto_connect to be true")
		return
	if canon_preset.get("clipboard_action") != "copy_server_address":
		_fail("Expected clipboard_action 'copy_server_address'")
		return
	print("  -> [PASS] Companion 'Isaac Client' auto-connect and clipboard configuration verified")

	# -----------------------------------------------------------------
	# Test 4: Host.yaml Synchronization & {game_dir} Evaluation
	# -----------------------------------------------------------------
	print("[Test 4] Host.yaml Synchronization & {game_dir} Evaluation...")
	var test_yaml_path: String = ProjectSettings.globalize_path("res://test_isaac_host.yaml")
	var initial_yaml: String = """
tboir_options:
  game_folder: ""
"""
	var write_fa = FileAccess.open("res://test_isaac_host.yaml", FileAccess.WRITE)
	write_fa.store_string(initial_yaml)
	write_fa.close()

	var mock_game_path = "C:/Steam/steamapps/common/The Binding of Isaac Rebirth/isaac-ng.exe"
	launcher._write_synced_host_yaml_file(test_yaml_path, mock_game_path, "", "", "localhost:38000")

	var read_fa = FileAccess.open("res://test_isaac_host.yaml", FileAccess.READ)
	var synced_content: String = read_fa.get_as_text()
	read_fa.close()
	DirAccess.remove_absolute(test_yaml_path)

	var expected_dir = "C:/Steam/steamapps/common/The Binding of Isaac Rebirth"
	if not expected_dir in synced_content:
		_fail("host.yaml missing synced game_folder: " + expected_dir + "\nContent was:\n" + synced_content)
		return
	print("  -> [PASS] host.yaml successfully synchronized with tboir_options.game_folder: ", expected_dir)

	# -----------------------------------------------------------------
	# Test 5: Guided Setup Schema Validation
	# -----------------------------------------------------------------
	print("[Test 5] Guided Setup Schema Validation...")
	var setup_path: String = "res://../backend/data/games/the_binding_of_isaac_repentance/guided_setup.json"
	var setup_file = FileAccess.open(setup_path, FileAccess.READ)
	if not setup_file:
		_fail("Could not find guided_setup.json at: " + setup_path)
		return
	var setup_data: Dictionary = JSON.parse_string(setup_file.get_as_text())
	setup_file.close()

	var default_config: Dictionary = setup_data.get("default_config", {})
	if not default_config.has("goals") or not default_config.has("goal_amount") or not default_config.has("death_link"):
		_fail("guided_setup.json missing primary default_config keys")
		return
	var steps: Array = setup_data.get("steps", [])
	if steps.size() < 3:
		_fail("Expected at least 3 setup wizard steps, got " + str(steps.size()))
		return
	print("  -> [PASS] Guided setup wizard schema validated with ", steps.size(), " steps")

	# -----------------------------------------------------------------
	# Test 6: APWorld Presence Verification
	# -----------------------------------------------------------------
	print("[Test 6] APWorld Presence Verification...")
	var backend_apworld = "res://../backend/archipelago_core/custom_worlds/tboir.apworld"
	var client_apworld = "res://Archipelago/custom_worlds/tboir.apworld"
	if not FileAccess.file_exists(backend_apworld):
		_fail("Missing backend custom world: " + backend_apworld)
		return
	if not FileAccess.file_exists(client_apworld):
		_fail("Missing client custom world: " + client_apworld)
		return
	print("  -> [PASS] tboir.apworld verified in both backend and client bundles")

	# -----------------------------------------------------------------
	# Test 7: Icon Presence Verification
	# -----------------------------------------------------------------
	print("[Test 7] Icon Presence Verification...")
	var icon_path = "res://../backend/data/games/the_binding_of_isaac_repentance/icon.png"
	if not FileAccess.file_exists(icon_path):
		_fail("Missing icon at: " + icon_path)
		return
	print("  -> [PASS] Game icon verified at: ", icon_path)

	_finish()
