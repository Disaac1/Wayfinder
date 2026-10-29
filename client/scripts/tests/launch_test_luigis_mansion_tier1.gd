extends SceneTree

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

func _run_test() -> void:
	print("==================================================")
	print("  Starting Luigi's Mansion 1 Tier 1 Support Test  ")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	var launcher = lobby.launcher
	
	# Load launch config directly into launcher presets to test Luigi's Mansion
	var lm_launch_path: String = "res://../backend/data/games/luigis_mansion/launch.json"
	var lm_file = FileAccess.open(lm_launch_path, FileAccess.READ)
	if not lm_file:
		_fail("Could not find Luigi's Mansion launch.json at: " + lm_launch_path)
		return
	var lm_preset = JSON.parse_string(lm_file.get_as_text())
	lm_file.close()
	
	launcher.launcher_presets["Luigi's Mansion"] = lm_preset
	print("[Test 1] Presets and Identity Resolver...")
	var canon_preset = launcher.get_preset("Luigi's Mansion")
	if canon_preset.is_empty():
		_fail("Failed to resolve Luigi's Mansion preset")
		return
	if canon_preset.get("support_tier") != 1:
		_fail("Luigi's Mansion support_tier is not 1")
		return
	if canon_preset.get("patch_extension") != ".aplm":
		_fail("Expected .aplm patch extension")
		return
	print("  -> [PASS] Luigi's Mansion identified as Tier 1 with .aplm patch")
	
	print("[Test 2] Testing ROM Aliases & Identification...")
	var aliases = canon_preset.get("rom_aliases", [])
	if not "Luigi's Mansion (USA).iso" in aliases or not "GLME01.iso" in aliases:
		_fail("Expected ROM aliases missing")
		return
	print("  -> [PASS] Recognized GameCube ISO aliases: ", aliases.size(), " variants")
	
	print("[Test 3] Testing PopTracker Configuration...")
	var tracker = canon_preset.get("tracker", {})
	if not tracker.get("supported", false):
		_fail("PopTracker is not marked supported")
		return
	if tracker.get("pack_version") != "0.1.1":
		_fail("Expected PopTracker pack version 0.1.1")
		return
	if not str(tracker.get("pack_download_url")).contains("lmpt.zip"):
		_fail("Invalid PopTracker download url")
		return
	print("  -> [PASS] PopTracker config verified for pack: ", tracker.get("pack_name"))

	print("[Test 4] Testing Dolphin & Host.yaml Configuration Sync...")
	var test_yaml_path = ProjectSettings.globalize_path("res://test_host.yaml")
	
	var initial_yaml = """
luigismansion_options:
  iso_file: ""
  dolphin_settings:
    path: ""
    auto_start: true
"""
	var write_fa = FileAccess.open("res://test_host.yaml", FileAccess.WRITE)
	write_fa.store_string(initial_yaml)
	write_fa.close()
	
	var mock_iso_path = "C:/Games/GameCube/Luigi's Mansion (USA).iso"
	var mock_dolphin_path = "C:/Emulators/Dolphin/Dolphin.exe"
	
	launcher._write_synced_host_yaml_file(test_yaml_path, mock_iso_path, "", mock_dolphin_path)
	
	var read_fa = FileAccess.open("res://test_host.yaml", FileAccess.READ)
	var synced_content = read_fa.get_as_text()
	read_fa.close()
	
	if not "iso_file: \"" + mock_iso_path + "\"" in synced_content:
		_fail("Synced host.yaml missing iso_file path injection")
		return
	if not "path: \"" + mock_dolphin_path + "\"" in synced_content:
		_fail("Synced host.yaml missing dolphin path injection")
		return
	print("  -> [PASS] host.yaml correctly synced with ISO and Dolphin paths!")
	
	print("[Test 5] Testing Guided Setup Configuration Schema...")
	var lm_setup_path: String = "res://../backend/data/games/luigis_mansion/guided_setup.json"
	var setup_file = FileAccess.open(lm_setup_path, FileAccess.READ)
	if not setup_file:
		_fail("Could not find guided_setup.json at: " + lm_setup_path)
		return
	var setup_data = JSON.parse_string(setup_file.get_as_text())
	setup_file.close()
	
	if setup_data.get("game_title") != "Luigi's Mansion":
		_fail("Invalid game_title in guided_setup.json")
		return
	var steps = setup_data.get("steps", [])
	if steps.size() != 4:
		_fail("Expected 4 guided setup steps, got: " + str(steps.size()))
		return
	print("  -> [PASS] Guided setup schema verified with 4 comprehensive wizard steps!")


	print("[Test 7] Testing DolphinTool RVZ Conversion Hooks...")
	var dummy_tool = launcher._find_dolphin_tool_path("C:/Emulators/Dolphin/Dolphin.exe")
	# Even if not on disk, verify convert_rvz_to_iso handles missing file safely
	var res_missing = launcher.convert_rvz_to_iso("nonexistent.rvz", "nonexistent.iso", "nonexistent_tool.exe")
	if res_missing.get("success", true):
		_fail("convert_rvz_to_iso should fail with nonexistent tool")
		return
	print("  -> [PASS] RVZ to ISO conversion helper validated cleanly.")

	print("[Test 6] Testing APWorld Presence...")
	var apworld_path = "res://Archipelago/custom_worlds/luigismansion.apworld"
	if not FileAccess.file_exists(apworld_path):
		_fail("luigismansion.apworld not found in client custom_worlds!")
		return
	print("  -> [PASS] luigismansion.apworld exists in client custom_worlds bundle.")

	print("==================================================")
	print("  LUIGI'S MANSION 1 SUPPORT TEST PASSED!          ")
	print("==================================================")
	if lobby:
		lobby.queue_free()
	
	if FileAccess.file_exists("res://test_host.yaml"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://test_host.yaml"))
	quit(0)
