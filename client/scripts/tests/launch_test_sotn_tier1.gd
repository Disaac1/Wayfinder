extends SceneTree

# =====================================================================
#             TIER 1 LAUNCH & SOTN DUAL-TRACK VALIDATION TEST
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
	print("  Starting Symphony of the Night Tier 1 Integration Test")
	print("==================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		_finish()
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	await lobby.launcher.load_launcher_config()
	
	# Test 1: Preset Validation for Symphony of the Night
	print("[Test] 1. Validating SOTN preset configuration...")
	var sotn_preset: Dictionary = lobby.launcher.get_preset("Symphony of the Night")
	if sotn_preset.is_empty():
		_fail("Could not find preset for 'Symphony of the Night'")
		_finish()
		return
		
	if sotn_preset.get("support_tier", 0) != 1:
		_fail("Expected support_tier 1 for Symphony of the Night, got " + str(sotn_preset.get("support_tier", 0)))
		
	var host_yaml_cfg = sotn_preset.get("host_yaml", {})
	if host_yaml_cfg.get("section", "") != "sotn_settings":
		_fail("Expected host_yaml section 'sotn_settings', got '" + host_yaml_cfg.get("section", "") + "'")
		
	print("[Test] SOTN preset verified with section: ", host_yaml_cfg.get("section", ""))
	
	# Test 2: Canonical Slug & Alias Resolution
	await lobby._ensure_remote_guided_setup("Symphony of the Night")
	print("[Test] 2. Validating Canonical Slug & Alias Resolution...")
	var guided_registry = load("res://scripts/guided_setup/guided_setup_registry.gd")
	var slug_canonical = guided_registry.get_game_slug("Symphony of the Night")
	var slug_alias1 = guided_registry.get_game_slug("Castlevania: Symphony of the Night")
	var slug_alias2 = guided_registry.get_game_slug("castlevania_sotn")
	var slug_alias3 = guided_registry.get_game_slug("sotn")
	
	if slug_canonical != "symphony_of_the_night":
		_fail("Canonical slug mismatch: " + slug_canonical)
	if slug_alias1 != "symphony_of_the_night" or slug_alias2 != "symphony_of_the_night" or slug_alias3 != "symphony_of_the_night":
		_fail("Alias slug mismatch: " + str([slug_alias1, slug_alias2, slug_alias3]))
		
	var has_setup = guided_registry.has_guided_setup("Symphony of the Night")
	if not has_setup:
		_fail("has_guided_setup returned false for Symphony of the Night")
	print("[Test] Canonical slug and alias resolution verified successfully.")
	
	# Test 3: Dual-Track Host YAML Synchronization
	print("[Test] 3. Testing host.yaml sync with sotn_settings & sotn_options...")
	var mock_yaml_dir = "user://temp_sotn_test"
	DirAccess.make_dir_recursive_absolute(mock_yaml_dir)
	var mock_yaml_path = mock_yaml_dir.path_join("test_host.yaml")
	
	var mock_rom = "user://base_roms/Castlevania - Symphony of the Night (USA) (Track 1).bin"
	var mock_bizhawk = "C:/Tools/BizHawk/EmuHawk.exe"
	
	lobby.launcher._write_synced_host_yaml_file(mock_yaml_path, ProjectSettings.globalize_path(mock_rom), mock_bizhawk)
	
	var fa = FileAccess.open(mock_yaml_path, FileAccess.READ)
	if not fa:
		_fail("Failed to open written test_host.yaml")
		_finish()
		return
		
	var yaml_content = fa.get_as_text()
	fa.close()
	
	if not "sotn_settings:" in yaml_content:
		_fail("host.yaml missing 'sotn_settings:' section")
	if not "sotn_options:" in yaml_content:
		_fail("host.yaml missing 'sotn_options:' backwards-compatibility section")
	if not "rom_file:" in yaml_content:
		_fail("host.yaml missing 'rom_file:' entry")
		
	print("[Test] host.yaml generated correctly:\n", yaml_content)
	
	# Cleanup test file
	DirAccess.remove_absolute(mock_yaml_path)
	
	# Test 4: PS1 Firmware Auto-Installation (ps-30a.bin)
	print("\n[Test] 4. Testing BizHawk PS1 Firmware (ps-30a.bin) Auto-Installation...")
	var mock_biz_dir: String = "user://temp_bizhawk_fw_test"
	DirAccess.make_dir_recursive_absolute(mock_biz_dir)
	var mock_biz_exe: String = mock_biz_dir.path_join("EmuHawk.exe")
	
	var fw_signal_done: Array = [false]
	lobby.launcher.ensure_emulator_firmware(lobby, sotn_preset, mock_biz_exe, "", func(fw_success: bool, _res_path: String):
		fw_signal_done[0] = true
		if not fw_success:
			_fail("ensure_emulator_firmware returned failure")
		else:
			var fw_path = ProjectSettings.globalize_path(mock_biz_dir.path_join("Firmware/ps-30a.bin"))
			print("  -> Firmware installed successfully to: ", fw_path)
			var check_file = FileAccess.open(fw_path, FileAccess.READ)
			if not check_file:
				_fail("Could not read installed firmware at " + fw_path)
			else:
				var fw_size = check_file.get_length()
				check_file.close()
				if fw_size != 524288:
					_fail("Firmware size mismatch. Expected 524288, got " + str(fw_size))
				else:
					print("  -> Verified ps-30a.bin exact size: 524,288 bytes!")
	)
	
	var fw_timeout = 20
	while not fw_signal_done[0] and fw_timeout > 0:
		await create_timer(0.2).timeout
		fw_timeout -= 1
		
	if not fw_signal_done[0]:
		_fail("Firmware auto-installation timed out!")
		
	# Verify uppercase and alias presence
	var fw_alias_path = mock_biz_dir.path_join("Firmware/PS-30A.BIN")
	if not FileAccess.file_exists(fw_alias_path):
		_fail("Firmware alias PS-30A.BIN missing from " + fw_alias_path)
	else:
		print("  -> Verified PS-30A.BIN alias present!")
		
	_finish()

func _finish() -> void:
	print("==================================================")
	if test_passed:
		print("  SOTN TIER 1 INTEGRATION TEST PASSED!")
	else:
		printerr("  SOTN TIER 1 INTEGRATION TEST FAILED!")
	print("==================================================")
	quit(0 if test_passed else 1)
