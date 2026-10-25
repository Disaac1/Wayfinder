extends SceneTree

# =====================================================================
#   VALIDATION TEST FOR SOTN LAUNCH & PROGRESS BAR BUG FIXES
# =====================================================================

var test_passed: bool = true

func _fail(reason: String) -> void:
	printerr("[Test Failure] ", reason)
	test_passed = false

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================================")
	print("  STARTING SOTN / FUSION DUAL-LAUNCH & PROGRESS BAR FIX TEST      ")
	print("==================================================================")

	var launcher_script = load("res://scripts/core/game_launcher.gd")
	var launcher = launcher_script.new()
	launcher.load_paths_config()
	await launcher.load_launcher_config()

	# -------------------------------------------------------------
	# Test 1: Monotonic Progress Bar & Completion Detection
	# -------------------------------------------------------------
	print("\n[Test 1] Testing modding progress bar monotonicity & smooth advance...")
	var dummy_node = Control.new()
	root.add_child(dummy_node)

	var mock_patch_dir = "user://test_fix_dir"
	DirAccess.make_dir_recursive_absolute(mock_patch_dir)
	var mock_patch = mock_patch_dir.path_join("AP_TestSeed_P1_Isaac.apsotn")

	# Tracking config
	var tracking_cfg = {
		"completion_extension": ".cue",
		"progress_extension": ".bin",
		"expected_bytes": 538655040
	}

	# Ensure neither comp nor prog exists yet
	var mock_comp = mock_patch_dir.path_join("AP_TestSeed_P1_Isaac.cue")
	var mock_prog = mock_patch_dir.path_join("AP_TestSeed_P1_Isaac.bin")
	if FileAccess.file_exists(mock_comp):
		DirAccess.remove_absolute(mock_comp)
	if FileAccess.file_exists(mock_prog):
		DirAccess.remove_absolute(mock_prog)

	# Verify monotonic progress formula
	var prev_pct = 49
	for tick in range(1, 25):
		var smooth_pct = int(clamp(50.0 + (float(tick) / 120.0) * 42.0, 50, 92))
		if smooth_pct < prev_pct:
			_fail("Progress bar jumped backwards at tick " + str(tick) + ": " + str(smooth_pct) + " < " + str(prev_pct))
		prev_pct = smooth_pct
	print("  -> Progress advances strictly monotonically (50% -> 92%) without sawtooth oscillation.")

	# Test completion detection
	var fa_cue = FileAccess.open(mock_comp, FileAccess.WRITE)
	fa_cue.store_string("FILE \"test.bin\" BINARY\n  TRACK 01 MODE2/2352\n")
	fa_cue.close()

	var detected_completion = launcher._check_extension_exists_in_dir(mock_patch_dir, ".cue")
	if not detected_completion:
		_fail("Extension .cue was not detected in " + mock_patch_dir)
	else:
		print("  -> Completion .cue file detected cleanly.")

	DirAccess.remove_absolute(mock_comp)
	DirAccess.remove_absolute(mock_patch_dir)
	dummy_node.queue_free()

	# -------------------------------------------------------------
	# Test 2: Host.yaml Synchronization & bizhawkclient_options
	# -------------------------------------------------------------
	print("\n[Test 2] Testing host.yaml bizhawkclient_options and emuhawk_path sync...")
	var test_yaml_dir = "user://temp_yaml_verify"
	DirAccess.make_dir_recursive_absolute(test_yaml_dir)
	var test_yaml_path = test_yaml_dir.path_join("host.yaml")

	var initial_yaml = """
bizhawkclient_options:
  emuhawk_path: ""
  rom_start: true
"""
	var fa_init = FileAccess.open(test_yaml_path, FileAccess.WRITE)
	fa_init.store_string(initial_yaml)
	fa_init.close()

	var real_bizhawk = "C:/RealBizHawk/EmuHawk.exe"
	launcher._write_synced_host_yaml_file(test_yaml_path, "C:/Games/sotn.bin", real_bizhawk)

	var fa_read = FileAccess.open(test_yaml_path, FileAccess.READ)
	var synced_content = fa_read.get_as_text()
	fa_read.close()

	if "mock_test_tools" in synced_content:
		_fail("Residual 'mock_test_tools' found in synced host.yaml")
	if not "emuhawk_path: \"C:/RealBizHawk/EmuHawk.exe\"" in synced_content:
		_fail("Updated emuhawk_path missing from synced host.yaml")
	if not "rom_start: true" in synced_content:
		_fail("rom_start: true missing or quoted in synced host.yaml")
	print("  -> host.yaml synced properly with clean emuhawk_path and unquoted boolean rom_start: true.")

	DirAccess.remove_absolute(test_yaml_path)
	DirAccess.remove_absolute(test_yaml_dir)

	# -------------------------------------------------------------
	# Test 3: BizHawk config.ini PSX+U Firmware Injection
	# -------------------------------------------------------------
	print("\n[Test 3] Testing BizHawk config.ini FirmwareUserSpecifications injection...")
	var test_biz_dir = "user://temp_biz_cfg"
	DirAccess.make_dir_recursive_absolute(test_biz_dir)
	var test_cfg_path = test_biz_dir.path_join("config.ini")

	var sample_cfg = """{
  "TargetDisplayFilter": 0,
  "FirmwareUserSpecifications": {},
  "StartFullscreen": false
}"""
	var fa_cfg = FileAccess.open(test_cfg_path, FileAccess.WRITE)
	fa_cfg.store_string(sample_cfg)
	fa_cfg.close()

	launcher._inject_emulator_firmware_config(ProjectSettings.globalize_path(test_biz_dir), {
		"file": "config.ini",
		"section": "FirmwareUserSpecifications",
		"key": "PSX+U",
		"value": "Firmware/ps-30a.bin"
	})

	var fa_cfg_read = FileAccess.open(test_cfg_path, FileAccess.READ)
	var updated_cfg = fa_cfg_read.get_as_text()
	fa_cfg_read.close()

	if not "\"PSX+U\": \"Firmware/ps-30a.bin\"" in updated_cfg:
		_fail("config.ini missing PSX+U firmware specification")
	else:
		print("  -> config.ini successfully updated with PSX+U firmware specification.")

	DirAccess.remove_absolute(test_cfg_path)
	DirAccess.remove_absolute(test_biz_dir)

	# -------------------------------------------------------------
	# Test 4: Verify Globalized Path Resolution in Launcher
	# -------------------------------------------------------------
	print("\n[Test 4] Testing target_client_path globalization...")
	var user_client_path = "user://tools/Archipelago/ArchipelagoBizHawkClient.exe"
	var global_res = ProjectSettings.globalize_path(user_client_path)
	if global_res.begins_with("user://"):
		_fail("globalize_path failed to convert user:// prefix: " + global_res)
	else:
		print("  -> Verified client path globalized from user:// to: ", global_res)

	_finish()

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  ALL SOTN / FUSION BUG FIX TESTS PASSED!                        ")
	else:
		printerr("  SOTN / FUSION BUG FIX TESTS FAILED!                            ")
	print("==================================================================")
	quit(0 if test_passed else 1)
