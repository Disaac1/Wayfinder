extends SceneTree

# =====================================================================
#   AUTOMATED TEST SUITE: GAME-AGNOSTIC LAUNCHER & FIRMWARE ARCHITECTURE
# =====================================================================

var test_passed: bool = true

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("\n==================================================================")
	print("  STARTING GAME-AGNOSTIC LAUNCHER ARCHITECTURE TEST SUITE")
	print("==================================================================")

	var launcher_script = load("res://scripts/core/game_launcher.gd")
	var launcher = launcher_script.new()

	# -------------------------------------------------------------
	# Test 1: Static Code Audit - Verify Zero Hardcoded Game Strings
	# -------------------------------------------------------------
	print("\n[Test 1] Auditing game_launcher.gd and lobby.gd for zero hardcoded game strings...")
	var launcher_file = FileAccess.open("res://scripts/core/game_launcher.gd", FileAccess.READ)
	var launcher_text = launcher_file.get_as_text()
	launcher_file.close()

	var lobby_file = FileAccess.open("res://scripts/ui/lobby.gd", FileAccess.READ)
	var lobby_text = lobby_file.get_as_text()
	lobby_file.close()

	var banned_game_patterns = [
		"sotn",
		"symphony_of_the_night",
		"ps-30a",
		"ensure_bizhawk_ps1_firmware",
		"_find_sotn_track2_path",
		"_inject_bizhawk_ps1_firmware_config",
		"--sm64ap_name",
		"--sm64ap_ip"
	]

	for pat in banned_game_patterns:
		if launcher_text.to_lower().contains(pat.to_lower()):
			_fail("game_launcher.gd contains banned game-specific string: " + pat)
		if lobby_text.to_lower().contains(pat.to_lower()):
			_fail("lobby.gd contains banned game-specific string: " + pat)

	print("  -> Passed: Both game_launcher.gd and lobby.gd have 0 hardcoded game strings.")

	# -------------------------------------------------------------
	# Test 2: Generic _inject_emulator_firmware_config Verification
	# -------------------------------------------------------------
	print("\n[Test 2] Testing generic _inject_emulator_firmware_config with arbitrary section/key...")
	var test_emu_dir = "user://temp_generic_emu_test"
	DirAccess.make_dir_recursive_absolute(test_emu_dir)
	var test_ini = test_emu_dir.path_join("custom_config.ini")
	var init_cfg = """{
  "General": {
    "Volume": 100
  },
  "CustomCoreOptions": {}
}"""
	var fa = FileAccess.open(test_ini, FileAccess.WRITE)
	fa.store_string(init_cfg)
	fa.close()

	launcher._inject_emulator_firmware_config(ProjectSettings.globalize_path(test_emu_dir), {
		"file": "custom_config.ini",
		"section": "CustomCoreOptions",
		"key": "CORE_BIOS",
		"value": "Firmware/custom_bios.bin"
	})

	var fa_read = FileAccess.open(test_ini, FileAccess.READ)
	var read_txt = fa_read.get_as_text()
	fa_read.close()

	if not "\"CORE_BIOS\": \"Firmware/custom_bios.bin\"" in read_txt:
		_fail("Generic config injection failed to insert CORE_BIOS into CustomCoreOptions")
	else:
		print("  -> Passed: Generic config injection succeeded for custom section/key.")

	DirAccess.remove_absolute(test_ini)
	DirAccess.remove_absolute(test_emu_dir)

	# -------------------------------------------------------------
	# Test 3: Generic ensure_emulator_firmware with Synthetic Preset
	# -------------------------------------------------------------
	print("\n[Test 3] Testing ensure_emulator_firmware with synthetic mock game preset...")
	var mock_game_dir = "user://temp_synthetic_game"
	DirAccess.make_dir_recursive_absolute(mock_game_dir)
	var mock_src_bios = mock_game_dir.path_join("test_bios.bin")
	var fw_fa = FileAccess.open(mock_src_bios, FileAccess.WRITE)
	fw_fa.store_string("MOCK_BIOS_DATA_1234567890")
	fw_fa.close()

	var synthetic_preset = {
		"game_name": "Synthetic Retro Game",
		"required_firmware": [
			{
				"name": "Synthetic BIOS",
				"file_name": "test_bios.bin",
				"dest_subpath": "Firmware/test_bios.bin",
				"dest_aliases": ["Firmware/TEST_BIOS.BIN", "Firmware/test_bios_alt.bin"],
				"emulator_config": {
					"file": "config.ini",
					"section": "FirmwareSpecs",
					"key": "SYNTH_CORE",
					"value": "Firmware/test_bios.bin"
				}
			}
		]
	}

	var mock_emu_dir = "user://temp_mock_emu_dir"
	DirAccess.make_dir_recursive_absolute(mock_emu_dir)
	var emu_cfg_file = mock_emu_dir.path_join("config.ini")
	var emu_cfg_fa = FileAccess.open(emu_cfg_file, FileAccess.WRITE)
	emu_cfg_fa.store_string("{\n  \"FirmwareSpecs\": {}\n}")
	emu_cfg_fa.close()

	var dummy_node = Node.new()
	var test_rom_path = mock_game_dir.path_join("game.rom")

	var fw_done: Array = [false]
	launcher.ensure_emulator_firmware(dummy_node, synthetic_preset, mock_emu_dir.path_join("emulator.exe"), test_rom_path, func(ok: bool, _res: String):
		fw_done[0] = true
		if not ok:
			_fail("ensure_emulator_firmware returned failure for synthetic preset")
		else:
			var target_fw = mock_emu_dir.path_join("Firmware/test_bios.bin")
			var alt_fw = mock_emu_dir.path_join("Firmware/test_bios_alt.bin")
			if not FileAccess.file_exists(target_fw):
				_fail("target_fw does not exist: " + target_fw)
			elif not FileAccess.file_exists(alt_fw):
				_fail("alt_fw alias does not exist: " + alt_fw)
			else:
				print("  -> Passed: ensure_emulator_firmware dynamically copied firmware and aliases.")

			var check_cfg = FileAccess.open(emu_cfg_file, FileAccess.READ)
			var cfg_content = check_cfg.get_as_text()
			check_cfg.close()
			if not "\"SYNTH_CORE\": \"Firmware/test_bios.bin\"" in cfg_content:
				_fail("SYNTH_CORE not injected into emulator config.ini")
			else:
				print("  -> Passed: Generic emulator config successfully injected.")
	)

	if not fw_done[0]:
		_fail("ensure_emulator_firmware callback did not execute")

	# Clean up synthetic test assets
	DirAccess.remove_absolute(mock_emu_dir.path_join("Firmware/test_bios.bin"))
	DirAccess.remove_absolute(mock_emu_dir.path_join("Firmware/TEST_BIOS.BIN"))
	DirAccess.remove_absolute(mock_emu_dir.path_join("Firmware/test_bios_alt.bin"))
	DirAccess.remove_absolute(mock_emu_dir.path_join("Firmware"))
	DirAccess.remove_absolute(emu_cfg_file)
	DirAccess.remove_absolute(mock_emu_dir)
	DirAccess.remove_absolute(mock_src_bios)
	DirAccess.remove_absolute(mock_game_dir)
	dummy_node.queue_free()

	# -------------------------------------------------------------
	# Test 4: Generic Supplemental ROM Resolution
	# -------------------------------------------------------------
	print("\n[Test 4] Testing generic _find_supplemental_rom_path...")
	var test_rom_dir = "user://temp_multi_disc"
	DirAccess.make_dir_recursive_absolute(test_rom_dir)
	var disc1_path = test_rom_dir.path_join("Grand Game (Disc 1).bin")
	var disc2_path = test_rom_dir.path_join("Grand Game (Disc 2).bin")
	var fa_d1 = FileAccess.open(disc1_path, FileAccess.WRITE)
	fa_d1.store_string("DISC1")
	fa_d1.close()
	var fa_d2 = FileAccess.open(disc2_path, FileAccess.WRITE)
	fa_d2.store_string("DISC2")
	fa_d2.close()

	var found_disc2 = launcher._find_supplemental_rom_path(disc1_path, "Grand Game (Disc 2).bin")
	if found_disc2 == "":
		_fail("Failed to resolve Disc 2 supplemental ROM")
	else:
		print("  -> Passed: Resolved supplemental ROM: ", found_disc2)

	DirAccess.remove_absolute(disc1_path)
	DirAccess.remove_absolute(disc2_path)
	DirAccess.remove_absolute(test_rom_dir)

	_finish()

func _fail(reason: String) -> void:
	printerr("  -> [FAIL] ", reason)
	test_passed = false

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  ALL GAME-AGNOSTIC LAUNCHER ARCHITECTURE TESTS PASSED! [OK]")
		print("==================================================================\n")
		quit(0)
	else:
		printerr("  TEST SUITE COMPLETED WITH FAILURES.")
		print("==================================================================\n")
		quit(1)
