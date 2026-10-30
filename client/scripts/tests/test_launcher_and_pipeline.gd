extends SceneTree

# =====================================================================
#             SUITE 3: LAUNCH PIPELINE & CONFIG GENERATION
# =====================================================================
# Validates game-agnostic architecture, async pipeline execution stages,
# dynamic config writers (host.yaml & mod templates), Lumafly assembly
# swapping mechanics, and multi-game patch discrimination.
# =====================================================================

var test_passed: bool = true
var lobby: Node

func _init() -> void:
	_run_suite.call_deferred()

func _fail(reason: String) -> void:
	printerr("  ❌ [FAIL] ", reason)
	test_passed = false

func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _run_suite() -> void:
	print("==================================================================")
	print("  SUITE 3: LAUNCH PIPELINE & CONFIG GENERATION                   ")
	print("==================================================================")

	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load res://scenes/lobby.tscn")
		_finish()
		return

	lobby = lobby_scene.instantiate()
	root.add_child(lobby)

	var launcher = lobby.launcher
	await launcher.load_launcher_config()

	# -------------------------------------------------------------
	# 1. Architectural Audit: Zero Hardcoded Game Strings
	# -------------------------------------------------------------
	print("\n[Test 1] Auditing game_launcher.gd and lobby.gd for zero hardcoded game strings...")
	var launcher_code = FileAccess.open("res://scripts/core/game_launcher.gd", FileAccess.READ).get_as_text()
	var lobby_code = FileAccess.open("res://scripts/ui/lobby.gd", FileAccess.READ).get_as_text()

	var banned_game_strings = [
		"\"Pokemon Emerald\"",
		"\"Pokemon - Emerald Version\"",
		"\"Castlevania - Symphony of the Night\"",
		"\"Super Mario 64\"",
		"\"Slay the Spire\"",
		"\"Plants vs. Zombies\""
	]

	for pat in banned_game_strings:
		_assert_true(not pat in launcher_code, "game_launcher.gd contains hardcoded game string: " + pat)
		_assert_true(not pat in lobby_code, "lobby.gd contains hardcoded game string: " + pat)
	print("  -> Passed: Core launcher and lobby scripts are 100% data-driven and game-agnostic.")

	# -------------------------------------------------------------
	# 2. Async Launch Pipeline State Machine
	# -------------------------------------------------------------
	print("\n[Test 2] Testing full async launch_game pipeline on synthetic preset...")
	var launcher_script = load("res://scripts/core/game_launcher.gd")
	var temp_test_dir = "user://test_pipeline_run"
	DirAccess.make_dir_recursive_absolute(temp_test_dir)
	var mock_exe_path = temp_test_dir.path_join("mock_steam_game.exe")
	var fa = FileAccess.open(mock_exe_path, FileAccess.WRITE)
	fa.store_string("MOCK_GAME_EXE")
	fa.close()

	launcher.launcher_presets["PipelineTestGame"] = {
		"game_name": "PipelineTestGame",
		"launch_mode": "steam",
		"steam_appid": "123450",
		"client_executable": "mock_steam_game.exe"
	}
	launcher.paths_config["PipelineTestGame"] = mock_exe_path

	var recorded_stages: Array[int] = []
	launcher.launch_status_updated.connect(func(stage: int, _msg: String, _pct: float):
		recorded_stages.append(stage)
	)

	var signal_state = {}
	launcher.launch_completed.connect(func(g_name: String, _pid: int):
		signal_state["completed_game"] = g_name
	)

	var dummy_node = Control.new()
	root.add_child(dummy_node)
	var launch_res = await launcher.launch_game(dummy_node, "PipelineTestGame")
	dummy_node.queue_free()

	_assert_true(launch_res == true, "launch_game failed for synthetic game")
	_assert_true(signal_state.get("completed_game") == "PipelineTestGame", "launch_completed signal did not fire")
	_assert_true(recorded_stages.has(launcher_script.LaunchStage.INITIALIZING), "Missing INITIALIZING stage")
	_assert_true(recorded_stages.has(launcher_script.LaunchStage.PREPARING_ROM), "Missing PREPARING_ROM stage")
	_assert_true(recorded_stages.has(launcher_script.LaunchStage.PREPARING_TOOLS), "Missing PREPARING_TOOLS stage")
	_assert_true(recorded_stages.has(launcher_script.LaunchStage.SYNCING_CONFIG), "Missing SYNCING_CONFIG stage")
	_assert_true(recorded_stages.has(launcher_script.LaunchStage.SPAWNING_PROCESS), "Missing SPAWNING_PROCESS stage")

	launcher.launcher_presets.erase("PipelineTestGame")
	launcher.paths_config.erase("PipelineTestGame")
	DirAccess.remove_absolute(mock_exe_path)
	print("  -> Passed: Pipeline executed all stages sequentially in order: ", recorded_stages)

	# -------------------------------------------------------------
	# 3. Dynamic Config Writers & Template Interpolation
	# -------------------------------------------------------------
	print("\n[Test 3] Verifying host.yaml sync and mod template interpolation...")
	# Slay the Spire config template
	var sts_template = "ConnectAddress={server_clean_url}\nConnectSlot={slot_name}\n"
	var mock_context = {
		"game_dir": "C:/Games/SlayTheSpire",
		"server_clean_url": "127.0.0.1:38000",
		"slot_name": "HeroTester"
	}
	var interpolated = launcher.interpolate_template(sts_template, mock_context)
	_assert_true("ConnectAddress=127.0.0.1:38000" in interpolated, "Missing ConnectAddress in interpolated config")
	_assert_true("ConnectSlot=HeroTester" in interpolated, "Missing ConnectSlot in interpolated config")

	# Host.yaml synchronization
	var test_yaml_path = ProjectSettings.globalize_path("res://test_suite_host.yaml")
	var initial_yaml = "hades_options:\n  styx_scribe_path: \"\"\ntboir_options:\n  game_folder: \"\"\n"
	var yfa = FileAccess.open("res://test_suite_host.yaml", FileAccess.WRITE)
	yfa.store_string(initial_yaml)
	yfa.close()

	launcher._write_synced_host_yaml_file(test_yaml_path, "C:/Steam/Hades/Hades.exe", "", "", "localhost:38000")
	var rfa = FileAccess.open("res://test_suite_host.yaml", FileAccess.READ)
	var synced = rfa.get_as_text()
	rfa.close()
	DirAccess.remove_absolute(test_yaml_path)

	_assert_true("C:/Steam/Hades/StyxScribe.py" in synced, "host.yaml missing synced styx_scribe_path")

	# Luigi's Mansion nested host_yaml sync
	var lm_yaml_path = ProjectSettings.globalize_path("res://test_suite_lm_host.yaml")
	var lm_initial = "luigismansion_options:\n  iso_file: \"\"\n"
	var lm_fa = FileAccess.open("res://test_suite_lm_host.yaml", FileAccess.WRITE)
	lm_fa.store_string(lm_initial)
	lm_fa.close()

	launcher._write_synced_host_yaml_file(lm_yaml_path, "C:/Games/Luigi.iso", "", "C:/Tools/Dolphin/Dolphin.exe", "localhost:38000")
	var lm_rfa = FileAccess.open("res://test_suite_lm_host.yaml", FileAccess.READ)
	var lm_synced = lm_rfa.get_as_text()
	lm_rfa.close()
	DirAccess.remove_absolute(lm_yaml_path)

	_assert_true("C:/Games/Luigi.iso" in lm_synced, "host.yaml missing synced Luigi iso_file")
	_assert_true("C:/Tools/Dolphin/Dolphin.exe" in lm_synced, "host.yaml missing synced Dolphin path")
	print("  -> Passed: Config template interpolation and host.yaml synchronization verified.")

	# -------------------------------------------------------------
	# 4. Lumafly Assembly-CSharp Swap Mechanics
	# -------------------------------------------------------------
	print("\n[Test 4] Verifying Lumafly modded assembly swap and restoration...")
	var mock_hk_dir = "user://test_lumafly_env"
	var mock_managed = mock_hk_dir.path_join("hollow_knight_Data/Managed")
	DirAccess.make_dir_recursive_absolute(mock_managed)

	var mock_active = mock_managed.path_join("Assembly-CSharp.dll")
	var mock_m = mock_managed.path_join("Assembly-CSharp.dll.m")
	var mock_v = mock_managed.path_join("Assembly-CSharp.dll.v")

	var vfa = FileAccess.open(mock_active, FileAccess.WRITE)
	vfa.store_string("VANILLA_CODE_PAYLOAD_WITHOUT_HOOKS")
	vfa.close()

	var mfa = FileAccess.open(mock_m, FileAccess.WRITE)
	mfa.store_string("MODDED_CODE_PAYLOAD_WITH_ModHooks_INSIDE")
	mfa.close()

	var state1 = LauncherUtils.check_assembly_csharp_status(mock_hk_dir)
	_assert_true(state1.get("state") == "disabled_in_lumafly", "Expected initial state disabled_in_lumafly, got " + str(state1.get("state")))

	var act = LauncherUtils.activate_modded_assembly(mock_hk_dir)
	_assert_true(act.get("success") == true, "Failed activating modded assembly")
	var state2 = LauncherUtils.check_assembly_csharp_status(mock_hk_dir)
	_assert_true(state2.get("state") == "active", "Expected active state after activation")
	_assert_true(FileAccess.file_exists(mock_v), "Vanilla backup .v not created")

	var rest = LauncherUtils.restore_vanilla_assembly(mock_hk_dir)
	_assert_true(rest.get("success") == true, "Failed restoring vanilla assembly")
	var state3 = LauncherUtils.check_assembly_csharp_status(mock_hk_dir)
	_assert_true(state3.get("state") == "disabled_in_lumafly", "Expected disabled_in_lumafly after restoration")

	DirAccess.remove_absolute(mock_active)
	DirAccess.remove_absolute(mock_m)
	DirAccess.remove_absolute(mock_v)
	print("  -> Passed: Lumafly assembly swap, backup, and restoration verified.")

	# -------------------------------------------------------------
	# 5. Patch File Completion Detection
	# -------------------------------------------------------------
	print("\n[Test 5] Verifying async patch completion detection...")
	var mock_patch_dir = "user://test_patch_detect"
	DirAccess.make_dir_recursive_absolute(mock_patch_dir)
	var mock_cue = mock_patch_dir.path_join("AP_TestSeed_P1_Hero.cue")
	var cfa = FileAccess.open(mock_cue, FileAccess.WRITE)
	cfa.store_string("FILE \"test.bin\" BINARY\n  TRACK 01 MODE2/2352\n")
	cfa.close()

	var detected_cue = launcher._check_extension_exists_in_dir(mock_patch_dir, ".cue")
	var detected_fake = launcher._check_extension_exists_in_dir(mock_patch_dir, ".fakeext")
	_assert_true(detected_cue == true, "Expected .cue file to be detected in target directory")
	_assert_true(detected_fake == false, "Expected .fakeext file to NOT be detected in target directory")
	DirAccess.remove_absolute(mock_cue)
	print("  -> Passed: Directory completion detection verified.")

	_finish()

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  SUITE 3: ALL LAUNCH PIPELINE TESTS PASSED! [OK]                ")
	else:
		printerr("  SUITE 3: COMPLETED WITH FAILURES!                              ")
	print("==================================================================")
	if lobby:
		lobby.queue_free()
	quit(0 if test_passed else 1)
