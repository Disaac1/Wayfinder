extends SceneTree

# =====================================================================
#             HOLLOW KNIGHT TIER 1 INTEGRATION TEST
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
	print("  Starting Hollow Knight Tier 1 Integration Test")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		_finish()
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	await lobby.launcher.load_launcher_config()
	
	# Test 1: Preset Validation for Hollow Knight
	print("[Test] 1. Validating Hollow Knight preset configuration...")
	var hk_preset: Dictionary = lobby.launcher.get_preset("Hollow Knight")
	if hk_preset.is_empty():
		_fail("Could not find preset for 'Hollow Knight'")
		_finish()
		return
		
	if hk_preset.get("support_tier", 0) != 1:
		_fail("Expected support_tier 1 for Hollow Knight, got " + str(hk_preset.get("support_tier", 0)))
		
	if hk_preset.get("launch_mode", "") != "direct":
		_fail("Expected launch_mode 'direct', got '" + hk_preset.get("launch_mode", "") + "'")
		
	if hk_preset.get("steam_appid", "") != "367520":
		_fail("Expected steam_appid '367520', got '" + hk_preset.get("steam_appid", "") + "'")

	if not hk_preset.get("prefer_steam_protocol", false):
		_fail("Expected prefer_steam_protocol to be true in Hollow Knight preset")
		
	if not hk_preset.has("config_writer"):
		_fail("Expected config_writer in Hollow Knight preset")
		
	if hk_preset.get("modding_api_url", "") == "":
		_fail("Expected modding_api_url to be configured")
		
	if hk_preset.get("mods_url", "") == "":
		_fail("Expected mods_url to be configured")

	print("[Test] Hollow Knight Tier 1 preset schema verified successfully.")
	
	# Test 2: Launch Context & Dynamic Config Generation
	print("[Test] 2. Testing launch context and dynamic Archipelago.GlobalSettings.json generation...")
	var nm = root.get_node_or_null("/root/NetworkManager")
	if nm:
		nm.player_name = "Isaac"
	var context: Dictionary = lobby.launcher.build_launch_context("C:/Program Files (x86)/Steam/steamapps/common/Hollow Knight/hollow_knight.exe", "", "", "Hollow Knight", 2)
	
	if context.get("slot_name", "") != "Isaac (HK)":
		_fail("Expected multi-game slot_name 'Isaac (HK)', got '" + context.get("slot_name", "") + "'")
		
	if not context.has("appdata_locallow") or context.get("appdata_locallow") == "":
		_fail("Expected valid appdata_locallow path in context")
		
	# Test writing to a temporary test config file using apply_config_writer
	var temp_config_dir: String = "user://temp_hk_test"
	DirAccess.make_dir_recursive_absolute(temp_config_dir)
	var temp_config_file: String = temp_config_dir.path_join("ArchipelagoMod.GlobalSettings.json")
	
	var mock_preset: Dictionary = hk_preset.duplicate(true)
	mock_preset["config_writer"]["file_path"] = temp_config_file
	
	var write_res: bool = lobby.launcher.apply_config_writer(mock_preset, context)
	if not write_res:
		_fail("apply_config_writer returned false")
		
	var fa: FileAccess = FileAccess.open(temp_config_file, FileAccess.READ)
	if not fa:
		_fail("Failed to open written test config file: " + temp_config_file)
	else:
		var json_str: String = fa.get_as_text()
		fa.close()
		var parsed = JSON.parse_string(json_str)
		if not (parsed is Dictionary):
			_fail("Failed to parse written settings JSON: " + json_str)
		else:
			var details: Dictionary = parsed.get("MenuConnectionDetails", {})
			if details.get("SlotName", "") != "Isaac (HK)":
				_fail("Expected SlotName 'Isaac (HK)' in MenuConnectionDetails, got '" + str(details.get("SlotName")) + "'")
			if not (details.get("ServerPort") is int or details.get("ServerPort") is float):
				_fail("Expected ServerPort to be an integer, got: " + str(details.get("ServerPort")))
			print("[Test] Generated ArchipelagoMod.GlobalSettings.json verified.")

	# Test 3: Auto-Discovery & Real Installation Status
	print("[Test] 3. Testing auto-discovery of hollow_knight.exe and Steam Beta downgrade status...")
	var discovered_exe: String = lobby.launcher.find_game_executable("hollow_knight.exe", ["Hollow Knight", "HollowKnight"])
	if discovered_exe == "":
		_fail("Auto-discovery failed to locate hollow_knight.exe in standard steam common folders")
	else:
		print("[Test] Auto-discovered Hollow Knight executable: ", discovered_exe)
		var hk_status: Dictionary = lobby.launcher.check_hollow_knight_modding_status(discovered_exe)
		print("[Test] Real Hollow Knight Modding Status: ", hk_status)
		if not hk_status.get("is_steam", false):
			_fail("Expected discovered executable in Steam directory to be detected as is_steam = true")
		if not hk_status.get("is_downgraded", false):
			_fail("Expected current machine's Steam install with 1.5.78.11833 to be detected as is_downgraded = true")
		if not hk_status.get("is_ready", false):
			_fail("Expected Hollow Knight to be ready when downgraded")
			
		var asm_info: Dictionary = hk_status.get("assembly_status", {})
		print("[Test] Real Assembly-CSharp Status: State='", asm_info.get("state", ""), "', has_modded_m=", asm_info.get("has_modded_m", false), ", is_active_modded=", asm_info.get("is_active_modded", false))
		if not (asm_info.get("is_active_modded", false) or asm_info.get("has_modded_m", false)):
			_fail("Expected either active modded Assembly-CSharp.dll or Lumafly dormant .m backup on real install")

	# Test 4: Mock Steam Betas Downgrade Detection
	print("[Test] 4. Testing simulated non-downgraded (latest public) Steam install...")
	var mock_steam_dir: String = "user://test_steam_env/steamapps/common/Hollow Knight"
	DirAccess.make_dir_recursive_absolute(mock_steam_dir)
	var mock_manifest: String = "user://test_steam_env/steamapps/appmanifest_367520.acf"
	var mfa = FileAccess.open(mock_manifest, FileAccess.WRITE)
	if mfa:
		mfa.store_string("\"AppState\"\n{\n\t\"appid\"\t\t\"367520\"\n\t\"name\"\t\t\"Hollow Knight\"\n\t\"UserConfig\"\n\t{\n\t\t\"BetaKey\"\t\t\"public\"\n\t}\n}\n")
		mfa.close()
	
	var mock_exe: String = mock_steam_dir.path_join("hollow_knight.exe")
	var efa = FileAccess.open(mock_exe, FileAccess.WRITE)
	if efa:
		efa.store_string("MOCK_EXE")
		efa.close()
		
	var mock_check: Dictionary = lobby.launcher.check_hollow_knight_modding_status(mock_exe)
	print("[Test] Mock Steam Check Result: ", mock_check)
	if not mock_check.get("needs_downgrade", false):
		_fail("Expected needs_downgrade = true when BetaKey is 'public' (latest non-downgraded version)")
	if not mock_check.get("guidance_text", "").contains("Downgrade Required"):
		_fail("Expected guidance_text to mention downgrade requirements")

	# Test 5: Lumafly Assembly-CSharp Swap Mechanics (.m / .v / active)
	print("[Test] 5. Testing Lumafly Assembly-CSharp.dll state detection and auto-activation...")
	var mock_hk_dir: String = "user://test_lumafly_env"
	var mock_managed: String = mock_hk_dir.path_join("hollow_knight_Data/Managed")
	DirAccess.make_dir_recursive_absolute(mock_managed)
	
	var mock_active_dll: String = mock_managed.path_join("Assembly-CSharp.dll")
	var mock_m_dll: String = mock_managed.path_join("Assembly-CSharp.dll.m")
	var mock_v_dll: String = mock_managed.path_join("Assembly-CSharp.dll.v")
	
	# Scenario: Active is vanilla, .m is modded (Lumafly disabled state)
	var v_fa = FileAccess.open(mock_active_dll, FileAccess.WRITE)
	v_fa.store_string("VANILLA_CODE_PAYLOAD_WITHOUT_HOOKS")
	v_fa.close()
	
	var m_fa = FileAccess.open(mock_m_dll, FileAccess.WRITE)
	m_fa.store_string("MODDED_CODE_PAYLOAD_WITH_ModHooks_INSIDE")
	m_fa.close()
	
	var asm_test1: Dictionary = LauncherUtils.check_assembly_csharp_status(mock_hk_dir)
	print("[Test] Initial Lumafly State: ", asm_test1.get("state", ""))
	if asm_test1.get("state", "") != "disabled_in_lumafly":
		_fail("Expected state 'disabled_in_lumafly', got: " + asm_test1.get("state", ""))
	if asm_test1.get("is_active_modded", true) != false:
		_fail("Expected is_active_modded = false for vanilla active dll")
	if asm_test1.get("has_modded_m", false) != true:
		_fail("Expected has_modded_m = true for .m dll containing ModHooks")
		
	# Activate modded assembly
	print("[Test] Activating modded assembly...")
	var act_res: Dictionary = LauncherUtils.activate_modded_assembly(mock_hk_dir)
	if not act_res.get("success", false):
		_fail("activate_modded_assembly failed: " + act_res.get("message", ""))
		
	var asm_test2: Dictionary = LauncherUtils.check_assembly_csharp_status(mock_hk_dir)
	print("[Test] Post-activation state: ", asm_test2.get("state", ""))
	if asm_test2.get("state", "") != "active":
		_fail("Expected state 'active' after activation, got: " + asm_test2.get("state", ""))
	if not FileAccess.file_exists(mock_v_dll):
		_fail("Expected vanilla backup to be preserved at Assembly-CSharp.dll.v")
	else:
		var v_read = FileAccess.open(mock_v_dll, FileAccess.READ).get_as_text()
		if v_read != "VANILLA_CODE_PAYLOAD_WITHOUT_HOOKS":
			_fail("Expected Assembly-CSharp.dll.v to preserve original vanilla payload")
			
	# Restore vanilla assembly
	print("[Test] Restoring vanilla assembly...")
	var rest_res: Dictionary = LauncherUtils.restore_vanilla_assembly(mock_hk_dir)
	if not rest_res.get("success", false):
		_fail("restore_vanilla_assembly failed: " + rest_res.get("message", ""))
	var asm_test3: Dictionary = LauncherUtils.check_assembly_csharp_status(mock_hk_dir)
	print("[Test] Post-restoration state: ", asm_test3.get("state", ""))
	if asm_test3.get("state", "") != "disabled_in_lumafly":
		_fail("Expected state 'disabled_in_lumafly' after restoration, got: " + asm_test3.get("state", ""))

	# Clean up mock environments
	if FileAccess.file_exists(mock_exe):
		DirAccess.remove_absolute(mock_exe)
	if FileAccess.file_exists(mock_manifest):
		DirAccess.remove_absolute(mock_manifest)
	if FileAccess.file_exists(temp_config_file):
		DirAccess.remove_absolute(temp_config_file)
	if FileAccess.file_exists(mock_active_dll):
		DirAccess.remove_absolute(mock_active_dll)
	if FileAccess.file_exists(mock_m_dll):
		DirAccess.remove_absolute(mock_m_dll)
	if FileAccess.file_exists(mock_v_dll):
		DirAccess.remove_absolute(mock_v_dll)
		
	_finish()

func _finish() -> void:
	print("==================================================")
	if test_passed:
		print("  HOLLOW KNIGHT TIER 1 INTEGRATION TEST PASSED!")
	else:
		printerr("  HOLLOW KNIGHT TIER 1 INTEGRATION TEST FAILED!")
	print("==================================================")
	quit(0 if test_passed else 1)
