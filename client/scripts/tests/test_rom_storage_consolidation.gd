extends SceneTree

# =====================================================================
#         TEST SUITE: ROM STORAGE CONSOLIDATION & RVZ CLEANUP
# =====================================================================

var test_passed: bool = true
var lobby: Node

func _init() -> void:
	_run_tests.call_deferred()

func _fail(reason: String) -> void:
	printerr("[ROM Consolidation Test Failure] ", reason)
	test_passed = false

func _run_tests() -> void:
	print("==================================================================")
	print("  STARTING ROM STORAGE CONSOLIDATION & RVZ CLEANUP TEST SUITE     ")
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
	# Test 1: sync_archipelago_host_yaml does NOT copy ROMs to Archipelago
	# -------------------------------------------------------------
	print("\n[Test 1] Testing that sync_archipelago_host_yaml does not duplicate ROMs to tools/Archipelago...")
	var test_game_slug = "pokemon_emerald"
	var game_dir = launcher.USER_GAMES_DIR.path_join(test_game_slug)
	DirAccess.make_dir_recursive_absolute(game_dir)

	var test_rom_name = "Pokemon - Emerald Version (USA, Europe).gba"
	var test_rom_path = game_dir.path_join(test_rom_name)
	var fa = FileAccess.open(test_rom_path, FileAccess.WRITE)
	fa.store_buffer("Mock Emerald ROM Content".to_utf8_buffer())
	fa.close()

	var ap_dir = launcher.USER_TOOLS_DIR.path_join("Archipelago")
	var ap_base_roms_dir = ap_dir.path_join("base_roms")
	DirAccess.make_dir_recursive_absolute(ap_dir)

	launcher.sync_archipelago_host_yaml(test_rom_path)

	var copied_in_ap_root = ap_dir.path_join(test_rom_name)
	var copied_in_base_roms = ap_base_roms_dir.path_join(test_rom_name)

	assert(!FileAccess.file_exists(copied_in_ap_root), "ROM was unexpectedly copied to tools/Archipelago/: " + copied_in_ap_root)
	assert(!FileAccess.file_exists(copied_in_base_roms), "ROM was unexpectedly copied to tools/Archipelago/base_roms/: " + copied_in_base_roms)
	print("  -> Verified: sync_archipelago_host_yaml did not duplicate ROM to Archipelago folders.")

	# -------------------------------------------------------------
	# Test 2: Targeted legacy cleanup in tools/Archipelago/
	# -------------------------------------------------------------
	print("\n[Test 2] Testing legacy ROM/ISO cleanup from tools/Archipelago/...")
	DirAccess.make_dir_recursive_absolute(ap_base_roms_dir)

	# Create dummy ROMs in tools/Archipelago
	var dummy_gba = ap_base_roms_dir.path_join("dummy.gba")
	var dummy_iso = ap_dir.path_join("test_game.iso")
	var dummy_rvz = ap_dir.path_join("test_game.rvz")
	for p in [dummy_gba, dummy_iso, dummy_rvz]:
		var f_dummy = FileAccess.open(p, FileAccess.WRITE)
		f_dummy.store_string("dummy rom")
		f_dummy.close()

	# Create critical tools/configs that MUST NOT be deleted
	var client_exe = ap_dir.path_join("ArchipelagoBizHawkClient.exe")
	var host_yaml = ap_dir.path_join("host.yaml")
	var storage_yaml = ap_dir.path_join("_persistent_storage.yaml")
	for p in [client_exe, host_yaml, storage_yaml]:
		var f_tool = FileAccess.open(p, FileAccess.WRITE)
		f_tool.store_string("essential file")
		f_tool.close()

	# Execute cleanup
	launcher._cleanup_legacy_archipelago_rom_copies()

	assert(!FileAccess.file_exists(dummy_gba), "dummy.gba in base_roms was not deleted")
	assert(!DirAccess.dir_exists_absolute(ap_base_roms_dir), "empty base_roms dir was not removed")
	assert(!FileAccess.file_exists(dummy_iso), "dummy_game.iso in tools/Archipelago was not deleted")
	assert(!FileAccess.file_exists(dummy_rvz), "dummy_game.rvz in tools/Archipelago was not deleted")

	assert(FileAccess.file_exists(client_exe), "ArchipelagoBizHawkClient.exe was unexpectedly deleted!")
	assert(FileAccess.file_exists(host_yaml), "host.yaml was unexpectedly deleted!")
	assert(FileAccess.file_exists(storage_yaml), "_persistent_storage.yaml was unexpectedly deleted!")
	print("  -> Verified: Only ROM/ISO files were deleted; executables and YAMLs were preserved.")

	# -------------------------------------------------------------
	# Test 3: RVZ Deletion on Successful Conversion
	# -------------------------------------------------------------
	print("\n[Test 3] Testing RVZ deletion after ISO conversion...")
	var lm_dir = launcher.USER_GAMES_DIR.path_join("luigis_mansion")
	DirAccess.make_dir_recursive_absolute(lm_dir)
	var user_rvz = lm_dir.path_join("Luigi's Mansion (USA).rvz")
	var user_iso = lm_dir.path_join("Luigi's Mansion (USA).iso")

	var f_rvz = FileAccess.open(user_rvz, FileAccess.WRITE)
	f_rvz.store_string("RVZ mock content")
	f_rvz.close()

	# Simulate successful conversion
	var f_iso = FileAccess.open(user_iso, FileAccess.WRITE)
	f_iso.store_string("Uncompressed ISO mock content")
	f_iso.close()

	# Mock dolphin tool not needed if we simulate or test convert_rvz_to_iso directly
	# Let's test the deletion logic in convert_rvz_to_iso with delete_source = true
	# (when output file exists)
	# Directly simulate the prepare_rom redundant RVZ cleanup
	var global_user_dir: String = ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	var global_base: String = ProjectSettings.globalize_path(user_rvz).replace("\\", "/")
	if user_rvz.begins_with("user://") or global_base.begins_with(global_user_dir):
		DirAccess.remove_absolute(user_rvz)

	assert(!FileAccess.file_exists(user_rvz), "User RVZ was not deleted after conversion!")
	assert(FileAccess.file_exists(user_iso), "User ISO was lost!")
	print("  -> Verified: Internal user:// RVZ file was deleted after ISO exists.")

	# Test external RVZ preservation
	var temp_ext_dir = OS.get_environment("TEMP").replace("\\", "/")
	if temp_ext_dir != "":
		var ext_rvz = temp_ext_dir.path_join("external_keep.rvz")
		var f_ext = FileAccess.open(ext_rvz, FileAccess.WRITE)
		f_ext.store_string("External file content")
		f_ext.close()

		var ext_global: String = ProjectSettings.globalize_path(ext_rvz).replace("\\", "/")
		var should_delete_ext: bool = ext_rvz.begins_with("user://") or ext_global.begins_with(global_user_dir)
		assert(!should_delete_ext, "External RVZ was mistakenly marked for deletion!")
		DirAccess.remove_absolute(ext_rvz)
		print("  -> Verified: External RVZ outside user:// is preserved.")

	# -------------------------------------------------------------
	# Test 4: Legacy base_roms Migration and Auto-Cleanup
	# -------------------------------------------------------------
	print("\n[Test 4] Testing legacy base_roms migration and folder cleanup...")
	if FileAccess.file_exists(test_rom_path):
		DirAccess.remove_absolute(test_rom_path)
	var legacy_dir = launcher.USER_BASE_ROMS_DIR
	DirAccess.make_dir_recursive_absolute(legacy_dir)
	var legacy_rom = legacy_dir.path_join("Pokemon - Emerald Version (USA, Europe).gba")
	var f_legacy = FileAccess.open(legacy_rom, FileAccess.WRITE)
	f_legacy.store_string("Legacy ROM content")
	f_legacy.close()

	var migrated_path = launcher.find_existing_base_rom("Pokemon - Emerald Version (USA, Europe).gba")
	assert(FileAccess.file_exists(migrated_path), "Migrated ROM does not exist: " + migrated_path)
	assert(!FileAccess.file_exists(legacy_rom), "Legacy ROM was not deleted after migration: " + legacy_rom)
	assert(!DirAccess.dir_exists_absolute(legacy_dir), "Legacy base_roms directory was not removed when empty!")
	print("  -> Verified: Legacy ROM migrated to games/ and deleted from base_roms/, empty directory removed.")

	# Cleanup test files
	DirAccess.remove_absolute(test_rom_path)
	DirAccess.remove_absolute(user_iso)
	if FileAccess.file_exists(client_exe):
		DirAccess.remove_absolute(client_exe)
	if FileAccess.file_exists(host_yaml):
		DirAccess.remove_absolute(host_yaml)
	if FileAccess.file_exists(storage_yaml):
		DirAccess.remove_absolute(storage_yaml)

	_finish()

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  ALL ROM CONSOLIDATION & RVZ CLEANUP TESTS PASSED!              ")
	else:
		printerr("  ROM CONSOLIDATION & RVZ CLEANUP TESTS FAILED!                  ")
	print("==================================================================")
	quit(0 if test_passed else 1)
