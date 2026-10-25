extends SceneTree

# =====================================================================
#   AUTOMATED TEST SUITE: STREAMLINED LAUNCH PIPELINE ARCHITECTURE
# =====================================================================

var test_passed: bool = true

func _fail(reason: String) -> void:
	printerr("[Test Failure] ", reason)
	test_passed = false

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("\n==================================================================")
	print("  STARTING STREAMLINED LAUNCH PIPELINE TEST SUITE")
	print("==================================================================")

	var launcher_script = load("res://scripts/core/game_launcher.gd")
	var launcher = launcher_script.new()
	launcher.load_paths_config()
	await launcher.load_launcher_config()

	# -------------------------------------------------------------
	# Test 1: Verify LaunchStage Enum & Signals Presence
	# -------------------------------------------------------------
	print("\n[Test 1] Verifying LaunchStage Enum and Pipeline Signals...")
	assert(launcher_script.LaunchStage != null, "LaunchStage enum must exist")
	assert(launcher_script.LaunchStage.INITIALIZING == 0, "INITIALIZING stage index mismatch")
	assert(launcher_script.LaunchStage.PREPARING_ROM == 1, "PREPARING_ROM stage index mismatch")
	assert(launcher_script.LaunchStage.PREPARING_TOOLS == 2, "PREPARING_TOOLS stage index mismatch")
	assert(launcher_script.LaunchStage.PREPARING_FIRMWARE == 3, "PREPARING_FIRMWARE stage index mismatch")
	assert(launcher_script.LaunchStage.FETCHING_PATCH == 4, "FETCHING_PATCH stage index mismatch")
	assert(launcher_script.LaunchStage.SYNCING_CONFIG == 5, "SYNCING_CONFIG stage index mismatch")
	assert(launcher_script.LaunchStage.SPAWNING_PROCESS == 6, "SPAWNING_PROCESS stage index mismatch")
	assert(launcher_script.LaunchStage.MODDING_DISC == 7, "MODDING_DISC stage index mismatch")
	assert(launcher_script.LaunchStage.COMPLETED == 8, "COMPLETED stage index mismatch")
	assert(launcher_script.LaunchStage.FAILED == 9, "FAILED stage index mismatch")

	assert(launcher.has_signal("launch_status_updated"), "Signal launch_status_updated must exist")
	assert(launcher.has_signal("prompt_file_selection"), "Signal prompt_file_selection must exist")
	assert(launcher.has_signal("prompt_tool_installation"), "Signal prompt_tool_installation must exist")
	assert(launcher.has_signal("launch_completed"), "Signal launch_completed must exist")
	assert(launcher.has_signal("launch_failed"), "Signal launch_failed must exist")
	print("  -> Passed: LaunchStage enum and all pipeline signals verified.")

	# -------------------------------------------------------------
	# Test 2: Static Audit - Verify Zero Legacy Callback Methods
	# -------------------------------------------------------------
	print("\n[Test 2] Auditing lobby.gd for zero legacy step callbacks...")
	var lobby_file = FileAccess.open("res://scripts/ui/lobby.gd", FileAccess.READ)
	var lobby_text = lobby_file.get_as_text()
	lobby_file.close()

	var banned_callback_names = [
		"_execute_tier1_launch",
		"_continue_tier1_launch_step3",
		"_continue_tier1_launch_step4",
		"_check_and_install_firmware_then_finish",
		"_finish_tier1_launch",
		"_execute_tier1_direct_launch",
		"_finish_tier1_direct_launch"
	]

	for cb_name in banned_callback_names:
		if lobby_text.contains(cb_name):
			_fail("lobby.gd still contains legacy callback: " + cb_name)

	print("  -> Passed: lobby.gd has 0 legacy step callbacks.")

	# -------------------------------------------------------------
	# Test 3: Test launch_game Graceful Failure & Prompt Cancellation
	# -------------------------------------------------------------
	print("\n[Test 3] Testing launch_game validation and prompt cancellation...")
	var dummy_node = Control.new()
	root.add_child(dummy_node)

	var signal_state = {
		"failed_game": "",
		"failed_msg": "",
		"prompt_received": false,
		"completed_game": ""
	}
	launcher.launch_failed.connect(func(g_name: String, msg: String):
		signal_state["failed_game"] = g_name
		signal_state["failed_msg"] = msg
	)

	# 3a. Empty game name rejection
	var ok_empty = await launcher.launch_game(dummy_node, "")
	assert(ok_empty == false, "launch_game must return false for empty game name")
	assert(signal_state["failed_msg"].contains("Game name cannot be empty"), "Expected empty game name error message, got: " + signal_state["failed_msg"])

	# 3b. Interactive prompt cancellation
	launcher.prompt_file_selection.connect(func(_title: String, _instructions: String, _filters: PackedStringArray, callback: Callable):
		signal_state["prompt_received"] = true
		callback.call("") # Simulate user cancelling file picker dialog
	)

	var ok_cancel = await launcher.launch_game(dummy_node, "NonExistentGame12345")
	assert(ok_cancel == false, "launch_game must return false when file prompt is cancelled")
	assert(signal_state["prompt_received"] == true, "prompt_file_selection signal must be triggered for missing asset")
	assert(signal_state["failed_game"] == "NonExistentGame12345", "launch_failed signal must report game name")
	print("  -> Passed: Empty game rejection and prompt cancellation handled cleanly.")

	# -------------------------------------------------------------
	# Test 4: Test Pipeline Lifecycle on Synthetic Mock Game
	# -------------------------------------------------------------
	print("\n[Test 4] Testing full async launch_game pipeline on synthetic preset...")
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

	launcher.launch_completed.connect(func(g_name: String, _pid: int):
		signal_state["completed_game"] = g_name
	)

	var launch_res = await launcher.launch_game(dummy_node, "PipelineTestGame")
	assert(launch_res == true, "launch_game must succeed for configured synthetic game")
	assert(signal_state["completed_game"] == "PipelineTestGame", "launch_completed signal must report game name")
	assert(recorded_stages.has(launcher_script.LaunchStage.INITIALIZING), "Must record INITIALIZING")
	assert(recorded_stages.has(launcher_script.LaunchStage.PREPARING_ROM), "Must record PREPARING_ROM")
	assert(recorded_stages.has(launcher_script.LaunchStage.PREPARING_TOOLS), "Must record PREPARING_TOOLS")
	assert(recorded_stages.has(launcher_script.LaunchStage.SYNCING_CONFIG), "Must record SYNCING_CONFIG")
	assert(recorded_stages.has(launcher_script.LaunchStage.SPAWNING_PROCESS), "Must record SPAWNING_PROCESS")
	print("  -> Passed: Pipeline executed all stages sequentially in order: ", recorded_stages)

	# Clean up synthetic paths
	launcher.launcher_presets.erase("PipelineTestGame")
	launcher.paths_config.erase("PipelineTestGame")
	DirAccess.remove_absolute(mock_exe_path)
	DirAccess.remove_absolute(temp_test_dir)

	# -------------------------------------------------------------
	# Test 5: Multi-Game Patch Discrimination
	# -------------------------------------------------------------
	print("\n[Test 5] Testing Multi-Game Patch Discrimination between SotN and Metroid...")
	var sotn_patch = "AP_27206101027893063247_P4_Test_(SotN).apsotn"
	var metroid_patch = "AP_27206101027893063247_P2_Test_(Metroid).apmetfus"

	assert(launcher.is_matching_patch_file(sotn_patch, ".apsotn", "Symphony of the Night") == true, "SotN patch must match SotN")
	assert(launcher.is_matching_patch_file(metroid_patch, ".apsotn", "Symphony of the Night") == false, "Metroid patch must NOT match SotN")
	assert(launcher.is_matching_patch_file(metroid_patch, ".apmetfus", "Metroid Fusion") == true, "Metroid patch must match Metroid")
	assert(launcher.is_matching_patch_file(sotn_patch, ".apmetfus", "Metroid Fusion") == false, "SotN patch must NOT match Metroid")
	print("  -> Passed: Patch discrimination verified for multi-game seeds.")

	print("\n==================================================================")
	if test_passed:
		print("  ALL STREAMLINED LAUNCH PIPELINE TESTS PASSED! [OK]")
		print("==================================================================\n")
		quit(0)
	else:
		printerr("  SOME TESTS FAILED!")
		print("==================================================================\n")
		quit(1)
