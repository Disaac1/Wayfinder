extends SceneTree

# =====================================================================
#             FRESH INSTALL & UNIFIED GAME PATH TEST SUITE
# =====================================================================

var test_passed: bool = true
var lobby: Node

func _init() -> void:
	_run_fresh_install_test.call_deferred()

func _fail(reason: String) -> void:
	printerr("[Fresh Install Failure] ", reason)
	test_passed = false

func _run_fresh_install_test() -> void:
	print("==================================================================")
	print("  STARTING FRESH INSTALL & UNIFIED GAME PATH TEST SUITE           ")
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
	# Test 1: Fresh Boot & Directory Auto-Creation
	# -------------------------------------------------------------
	print("\n[Test 1] Verifying core directories and default config creation...")
	var games_dir = launcher.USER_GAMES_DIR
	var tools_dir = launcher.USER_TOOLS_DIR
	var saves_dir = launcher.USER_SAVES_DIR
	
	DirAccess.make_dir_recursive_absolute(games_dir)
	DirAccess.make_dir_recursive_absolute(tools_dir)
	DirAccess.make_dir_recursive_absolute(saves_dir)
	
	assert(DirAccess.dir_exists_absolute(games_dir), "games_dir does not exist")
	assert(DirAccess.dir_exists_absolute(tools_dir), "tools_dir does not exist")
	assert(DirAccess.dir_exists_absolute(saves_dir), "saves_dir does not exist")
	print("  -> Core directories exist: games/, tools/, saves/")
	
	# -------------------------------------------------------------
	# Test 2: Canonical Game Slugs & Unified Path Generation
	# -------------------------------------------------------------
	print("\n[Test 2] Testing canonical slug and unified path resolution for all focus games...")
	var test_cases = [
		{"name": "Metroid Fusion", "rom": "Metroid Fusion (USA).gba", "expected_slug": "metroid_fusion"},
		{"name": "Pokemon Emerald", "rom": "Pokemon - Emerald Version (USA).gba", "expected_slug": "pokemon_emerald"},
		{"name": "Symphony of the Night", "rom": "Castlevania - Symphony of the Night (USA) (Track 1).bin", "expected_slug": "symphony_of_the_night"},
		{"name": "Plants vs. Zombies", "rom": "", "expected_slug": "plants_vs_zombies"},
		{"name": "Hollow Knight", "rom": "", "expected_slug": "hollow_knight"}
	]
	
	for tc in test_cases:
		var slug = launcher.get_game_slug(tc["name"])
		assert(slug == tc["expected_slug"], "Slug mismatch for " + tc["name"] + ": got " + slug + ", expected " + tc["expected_slug"])
		var g_dir = launcher.get_game_dir(tc["name"])
		assert(g_dir == launcher.USER_GAMES_DIR.path_join(tc["expected_slug"]), "Game dir mismatch for " + tc["name"])
		assert(DirAccess.dir_exists_absolute(g_dir), "Game dir not created: " + g_dir)
		
		if tc["rom"] != "":
			var rom_slug = launcher.get_game_slug_for_rom(tc["rom"])
			assert(rom_slug == tc["expected_slug"], "ROM slug mismatch for " + tc["rom"] + ": " + rom_slug)
			var rom_dest = launcher.get_game_rom_path(tc["name"], tc["rom"])
			assert(rom_dest == g_dir.path_join(tc["rom"]), "ROM dest mismatch: " + rom_dest)
			
		print("  -> [PASS] " + tc["name"] + " -> " + slug + " (" + g_dir + ")")
		
	# -------------------------------------------------------------
	# Test 3: Flexible roms.json Multi-Key Resolution
	# -------------------------------------------------------------
	print("\n[Test 3] Testing multi-key catalog lookup (by slug, title, filename, or alias)...")
	launcher.roms_catalog = {
		"metroid_fusion": "https://example.com/fusion_by_slug.gba",
		"Pokemon - Emerald Version (USA).gba": "https://example.com/emerald_by_filename.gba",
		"Plants vs. Zombies": {
			"url": "https://example.com/pvz_by_title.zip",
			"key": "SecretPvZKey",
			"encrypted": true
		}
	}
	
	# Lookup Metroid Fusion by exact ROM filename when catalog only has slug
	var mf_entry = launcher.get_rom_download_entry("Metroid Fusion (USA).gba")
	assert(not mf_entry.is_empty(), "Failed to resolve Metroid Fusion by ROM filename from slug catalog entry")
	assert(mf_entry.get("url") == "https://example.com/fusion_by_slug.gba", "URL mismatch for Metroid Fusion")
	print("  -> Querying 'Metroid Fusion (USA).gba' resolved catalog key 'metroid_fusion'")
	
	# Lookup Pokemon Emerald by slug when catalog only has filename
	var emerald_entry = launcher.get_rom_download_entry("pokemon_emerald")
	assert(not emerald_entry.is_empty(), "Failed to resolve Pokemon Emerald by slug from filename catalog entry")
	assert(emerald_entry.get("url") == "https://example.com/emerald_by_filename.gba", "URL mismatch for Pokemon Emerald")
	print("  -> Querying 'pokemon_emerald' resolved catalog key 'Pokemon - Emerald Version (USA).gba'")
	
	# Lookup PvZ by slug when catalog has display title
	var pvz_entry = launcher.get_rom_download_entry("plants_vs_zombies")
	assert(not pvz_entry.is_empty(), "Failed to resolve PvZ by slug from title catalog entry")
	assert(pvz_entry.get("key") == "SecretPvZKey", "Decryption key mismatch for PvZ")
	print("  -> Querying 'plants_vs_zombies' resolved catalog key 'Plants vs. Zombies'")
	
	# -------------------------------------------------------------
	# Test 4: Supplemental ROM & Multi-Track Audio Colocation
	# -------------------------------------------------------------
	print("\n[Test 4] Testing multi-track CD-ROM colocation under user://games/symphony_of_the_night/...")
	var sotn_dir = launcher.get_game_dir("Symphony of the Night")
	var track1_name = "Castlevania - Symphony of the Night (USA) (Track 1).bin"
	var track2_name = "Castlevania - Symphony of the Night (USA) (Track 2).bin"
	var track1_path = sotn_dir.path_join(track1_name)
	var track2_path = sotn_dir.path_join(track2_name)
	
	# Write mock track 1 and track 2 in unified directory
	var fa1 = FileAccess.open(track1_path, FileAccess.WRITE)
	fa1.store_string("MOCK_TRACK_1_DATA_PAYLOAD_ABC")
	fa1.close()
	
	var fa2 = FileAccess.open(track2_path, FileAccess.WRITE)
	fa2.store_string("MOCK_TRACK_2_AUDIO_PAYLOAD_XYZ")
	fa2.close()
	
	var found_track2 = launcher._find_supplemental_rom_path(track1_path, track2_name)
	assert(found_track2 != "", "Failed to find colocated Track 2 in unified game directory")
	print("  -> Supplemental Track 2 found colocated at: ", found_track2)
	
	# -------------------------------------------------------------
	# Test 5: Legacy Base ROM Auto-Migration
	# -------------------------------------------------------------
	print("\n[Test 5] Testing automatic migration of legacy user://base_roms/ files...")
	var legacy_dir = launcher.USER_BASE_ROMS_DIR
	DirAccess.make_dir_recursive_absolute(legacy_dir)
	var legacy_rom_name = "Pokemon - Emerald Version (USA).gba"
	var legacy_rom_path = legacy_dir.path_join(legacy_rom_name)
	
	var em_dest_dir = launcher.get_game_dir("Pokemon Emerald")
	var em_unified_path = em_dest_dir.path_join(legacy_rom_name)
	if FileAccess.file_exists(em_unified_path):
		DirAccess.remove_absolute(em_unified_path)
		
	var fa_em = FileAccess.open(legacy_rom_path, FileAccess.WRITE)
	var dummy_rom_bytes = PackedByteArray()
	dummy_rom_bytes.resize(2048)
	dummy_rom_bytes.fill(65) # 'A'
	fa_em.store_buffer(dummy_rom_bytes)
	fa_em.close()
	
	var found_migrated = launcher.find_existing_base_rom(legacy_rom_name)
	assert(FileAccess.file_exists(em_unified_path), "Legacy ROM was not migrated to unified game directory: " + em_unified_path)
	assert(ProjectSettings.globalize_path(found_migrated) == ProjectSettings.globalize_path(em_unified_path), "find_existing_base_rom path mismatch: " + found_migrated + " vs " + em_unified_path)
	print("  -> Legacy ROM in base_roms successfully auto-migrated to: ", found_migrated)
	
	# Cleanup test files
	DirAccess.remove_absolute(track1_path)
	DirAccess.remove_absolute(track2_path)
	DirAccess.remove_absolute(legacy_rom_path)
	DirAccess.remove_absolute(em_unified_path)
	
	# -------------------------------------------------------------
	# Test 6: Missing Install Prompting & roms.json Download Button
	# -------------------------------------------------------------
	print("\n[Test 6] Testing missing install prompting & roms.json download option...")
	# Simulate unconfigured game with download link in roms.json
	launcher.launcher_presets["Mock Missing Game"] = {
		"game_name": "Mock Missing Game",
		"required_rom": "MockMissingROM.gba",
		"launch_mode": "patch_rom"
	}
	launcher.paths_config.erase("Mock Missing Game")
	launcher.roms_catalog = {"mockmissingrom.gba": "https://example.com/mock.gba"}
	lobby._setup_game_details_in_overlay("Mock Missing Game")
	
	assert(lobby.launch_download_btn.visible == true, "Download button should be visible when roms.json has entry")
	assert("Option 1" in lobby.launch_instructions.text, "Prompt should display Option 1 (Download Automatically)")
	assert("Browse" in lobby.launch_instructions.text, "Prompt should display Option 2 (Browse to locate)")
	print("  -> Game with roms.json link shows download button and browse options")
	
	# Simulate unconfigured game WITHOUT download link in roms.json
	launcher.paths_config.erase("Unknown Test Game")
	launcher.roms_catalog = {}
	lobby._setup_game_details_in_overlay("Unknown Test Game")
	
	assert(lobby.launch_download_btn.visible == false, "Download button should be hidden when roms.json has no entry")
	assert("Browse" in lobby.launch_instructions.text, "Prompt should instruct user to browse for existing install")
	print("  -> Game without roms.json link hides download button and prompts for file browse")
	
	_finish()

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  ALL FRESH INSTALL & UNIFIED GAME PATH TESTS PASSED!            ")
	else:
		printerr("  FRESH INSTALL & UNIFIED GAME PATH TESTS FAILED!                ")
	print("==================================================================")
	quit(0 if test_passed else 1)
