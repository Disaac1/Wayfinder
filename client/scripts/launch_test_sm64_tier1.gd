extends SceneTree

var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Super Mario 64 Tier 1 Integration Test ")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	# Test 1: Shared Tools Registry & Tier 1 Preset Validation for Super Mario 64
	print("[Test] 1. Verifying Shared Tools Registry & Super Mario 64 Tier 1 preset schema...")
	await lobby.launcher.load_launcher_config()
	var preset = lobby.launcher.launcher_presets.get("Super Mario 64", {})
	if preset.is_empty():
		_fail("Super Mario 64 preset missing from launcher_presets")
		return
	if preset.get("support_tier") != 1:
		_fail("Super Mario 64 support_tier expected to be 1, got: " + str(preset.get("support_tier")))
		return
		
	var client_tool_key = preset.get("client_tool", "")
	var client_tool = lobby.launcher.launcher_tools.get(client_tool_key, {})
	if client_tool.is_empty() or client_tool.get("download_url", "") == "":
		_fail("Shared client_tool '" + client_tool_key + "' missing or has empty download_url")
		return
		
	print("[Test] Shared tools registry and Super Mario 64 Tier 1 preset schema verified successfully!")
	print("  -> Client Tool: ", client_tool)
	
	# Test 2: Base ROM bypass pipeline for Super Mario 64 (zero ROM requirement)
	print("[Test] 2. Testing zero-ROM pipeline for Super Mario 64...")
	var rom_state = {"completed": false, "success": false, "path": "initial"}
	lobby.launcher.ensure_rom_exists_or_download(lobby, "", func(success, path_or_err):
		rom_state.completed = true
		rom_state.success = success
		rom_state.path = path_or_err
	)
	
	if not rom_state.success or rom_state.path != "":
		_fail("Zero-ROM pipeline failed for SM64. Expected success with empty path, got: " + str(rom_state.path))
		return
	print("[Test] Zero-ROM pipeline verified successfully! (No ROM required)")
	
	# Test 3: Auto-Discovery Scanner for SM64EX
	print("[Test] 3. Testing Tool Scanner for Super Mario 64 EX...")
	var mock_tools_dir = "user://mock_sm64_tools"
	var mock_sm64_dir = mock_tools_dir.path_join("SM64EX")
	DirAccess.make_dir_recursive_absolute(mock_tools_dir)
	DirAccess.make_dir_recursive_absolute(mock_sm64_dir)
	
	var mock_sm64_exe = mock_sm64_dir.path_join("sm64.us.f3dex2e.exe")
	var sm64_f = FileAccess.open(mock_sm64_exe, FileAccess.WRITE)
	if not sm64_f:
		_fail("Could not create mock file at: " + mock_sm64_exe)
		return
	sm64_f.store_string("Mock SM64EX Exe")
	sm64_f.close()
	
	var sm64_disc = lobby.launcher.find_executable_recursive(mock_tools_dir, "sm64.us.f3dex2e.exe")
	if sm64_disc == "":
		_fail("Failed to discover sm64.us.f3dex2e.exe in mock_sm64_tools")
		return
	print("[Test] Discovered SM64EX Executable: ", sm64_disc)
	
	# Cleanup mock files
	DirAccess.remove_absolute(mock_sm64_exe)
	DirAccess.remove_absolute(mock_sm64_dir)
	DirAccess.remove_absolute(mock_tools_dir)
	lobby.queue_free()
	
	print("\n==================================================")
	print("  SUPER MARIO 64 TIER 1 INTEGRATION TEST PASSED!")
	print("==================================================")
	quit(0)

func _fail(reason: String) -> void:
	printerr("[Test FAIL] ", reason)
	if lobby:
		lobby.queue_free()
	quit(1)
