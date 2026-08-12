extends SceneTree

var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Pokemon Emerald Tier 1 Integration Test")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	# Test 1: Shared Tools Registry & Tier 1 Preset Validation
	print("[Test] 1. Verifying Shared Tools Registry & Pokemon Emerald Tier 1 preset schema...")
	await lobby.launcher.load_launcher_config()
	var preset = lobby.launcher.launcher_presets.get("Pokemon Emerald", {})
	if preset.is_empty():
		_fail("Pokemon Emerald preset missing from launcher_presets")
		return
	if preset.get("support_tier") != 1:
		_fail("Pokemon Emerald support_tier expected to be 1, got: " + str(preset.get("support_tier")))
		return
		
	var client_tool_key = preset.get("client_tool", "")
	var client_tool = lobby.launcher.launcher_tools.get(client_tool_key, {})
	if client_tool.is_empty() or client_tool.get("download_url", "") == "":
		_fail("Shared client_tool '" + client_tool_key + "' missing or has empty download_url")
		return
		
	var emu_tool_key = preset.get("emulator_tool", "")
	var emu_tool = lobby.launcher.launcher_tools.get(emu_tool_key, {})
	if emu_tool.is_empty() or emu_tool.get("download_url", "") == "":
		_fail("Shared emulator_tool '" + emu_tool_key + "' missing or has empty download_url")
		return
		
	print("[Test] Shared tools registry and Tier 1 preset schema verified successfully!")
	print("  -> Client Tool: ", client_tool)
	print("  -> Emulator Tool: ", emu_tool)
	
	# Test 2: Base ROM check and Download pipeline
	print("[Test] 2. Testing ROM pipeline with mock source...")
	lobby.launcher.load_roms_catalog()
	var test_rom_name = "Test_Emerald_Mock_ROM.gba"
	var base_roms_dir = "user://base_roms"
	var rom_path = base_roms_dir.path_join(test_rom_name)
	
	if FileAccess.file_exists(rom_path):
		DirAccess.remove_absolute(rom_path)
		
	var mock_server_dir = "user://mock_host_t1"
	DirAccess.make_dir_recursive_absolute(mock_server_dir)
	var mock_source_rom = mock_server_dir.path_join("emerald_source.gba")
	var file = FileAccess.open(mock_source_rom, FileAccess.WRITE)
	if not file:
		_fail("Failed to write mock source ROM")
		return
	file.store_string("Mock GBA ROM Binary Data")
	file.close()
	
	var file_url = "file://" + ProjectSettings.globalize_path(mock_source_rom)
	lobby.launcher.roms_catalog[test_rom_name] = file_url
	
	var rom_state = {"completed": false, "success": false, "path": ""}
	lobby.launcher.ensure_rom_exists_or_download(lobby, test_rom_name, func(success, path_or_err):
		rom_state.completed = true
		rom_state.success = success
		rom_state.path = path_or_err
	)
	
	var timeout = 5.0
	while not rom_state.completed and timeout > 0:
		await create_timer(0.1).timeout
		timeout -= 0.1
		
	if not rom_state.success:
		_fail("ROM pipeline failed: " + rom_state.path)
		return
	print("[Test] Base ROM verified at: ", rom_state.path)
	
	# Test 3: Auto-Discovery Scanner for Tools
	print("[Test] 3. Testing Tool Scanner for Archipelago Client & BizHawk...")
	var mock_tools_dir = "user://mock_test_tools"
	var mock_ap_dir = mock_tools_dir.path_join("Archipelago")
	var mock_biz_dir = mock_tools_dir.path_join("BizHawk")
	DirAccess.make_dir_recursive_absolute(mock_tools_dir)
	DirAccess.make_dir_recursive_absolute(mock_ap_dir)
	DirAccess.make_dir_recursive_absolute(mock_biz_dir)
	
	var mock_ap_exe = mock_ap_dir.path_join("ArchipelagoBizHawkClient.exe")
	var ap_f = FileAccess.open(mock_ap_exe, FileAccess.WRITE)
	if not ap_f:
		_fail("Could not create mock file at: " + mock_ap_exe)
		return
	ap_f.store_string("Mock AP BizHawk Client Exe")
	ap_f.close()
	
	var mock_biz_exe = mock_biz_dir.path_join("EmuHawk.exe")
	var biz_f = FileAccess.open(mock_biz_exe, FileAccess.WRITE)
	if not biz_f:
		_fail("Could not create mock file at: " + mock_biz_exe)
		return
	biz_f.store_string("Mock EmuHawk Exe")
	biz_f.close()
	
	var ap_disc = lobby.launcher.find_executable_recursive(mock_tools_dir, "ArchipelagoBizHawkClient.exe")
	if ap_disc == "":
		_fail("Failed to discover ArchipelagoBizHawkClient.exe in mock_test_tools")
		return
	print("[Test] Discovered Archipelago Client: ", ap_disc)
	
	var biz_disc = lobby.launcher.find_executable_recursive(mock_tools_dir, "EmuHawk.exe")
	if biz_disc == "":
		_fail("Failed to discover EmuHawk.exe in mock_test_tools")
		return
	print("[Test] Discovered BizHawk: ", biz_disc)
	
	# Test 4: Archipelago host.yaml syncing
	print("[Test] 4. Testing Archipelago host.yaml sync...")
	lobby.launcher.sync_archipelago_host_yaml(rom_state.path, biz_disc)
	var yaml_path = "user://tools/Archipelago/host.yaml"
	if not FileAccess.file_exists(yaml_path):
		_fail("host.yaml was not created at expected location")
		return
	var yf = FileAccess.open(yaml_path, FileAccess.READ)
	var y_content = yf.get_as_text()
	yf.close()
	if not "pokemon_emerald_options:" in y_content or not "bizhawkclient_options:" in y_content:
		_fail("host.yaml missing required options blocks. Content: " + y_content)
		return
	print("[Test] Archipelago host.yaml sync verified successfully!")
	
	# Cleanup mock files
	DirAccess.remove_absolute(rom_path)
	DirAccess.remove_absolute(mock_source_rom)
	DirAccess.remove_absolute(mock_server_dir)
	DirAccess.remove_absolute(mock_ap_exe)
	DirAccess.remove_absolute(mock_biz_exe)
	DirAccess.remove_absolute(mock_ap_dir)
	DirAccess.remove_absolute(mock_biz_dir)
	DirAccess.remove_absolute(mock_tools_dir)
	lobby.queue_free()
	
	print("\n==================================================")
	print("  POKEMON EMERALD TIER 1 INTEGRATION TEST PASSED!")
	print("==================================================")
	quit(0)

func _fail(reason: String) -> void:
	printerr("[Test FAIL] ", reason)
	if lobby:
		lobby.queue_free()
	quit(1)
