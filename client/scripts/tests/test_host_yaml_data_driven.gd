extends SceneTree

const ArchipelagoConfig = preload("res://scripts/core/archipelago_config.gd")

var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _fail(reason: String) -> void:
	print("TEST FAILED: ", reason)
	if lobby:
		lobby.queue_free()
	quit(1)

func _run_test() -> void:
	print("==================================================")
	print("  TESTING DATA-DRIVEN HOST.YAML PATCHING ENGINE   ")
	print("==================================================")

	var initial_yaml = """
pokemon_bw_settings:
  # File name of your Pokémon Black Version ROM
  black_rom: "PokemonBlack.nds"
  # File name of your Pokémon White Version ROM
  white_rom: "PokemonWhite.nds"
  # File name of your Pokémon Black or White Version ROM
  dynamic_rom: "PokemonBWDynamic.nds"
  # Path to the user's Pokémon Black and White Poptracker Pack.
  ut_pack_path: ""
  enable_encounter_plando: true
  enable_stats_plando: true
  enable_move_data_plando: true
  dump_patched_files: false
  enable_arm7_expansion_test: false
  extract_text: false
  extended_spoiler: false
  plugin_settings: {}
"""

	# Test 1: update_yaml_value on scalar types (string, bool, int, dictionary)
	print("[Test 1] Testing ArchipelagoConfig.update_yaml_value scalar & nested options...")
	var yaml = initial_yaml
	yaml = ArchipelagoConfig.update_yaml_value(yaml, "pokemon_bw_settings", "black_rom", "C:/ROMs/Pokemon - Black Version.nds")
	yaml = ArchipelagoConfig.update_yaml_value(yaml, "pokemon_bw_settings", "white_rom", "C:/ROMs/Pokemon - White Version.nds")
	yaml = ArchipelagoConfig.update_yaml_value(yaml, "pokemon_bw_settings", "dynamic_rom", "C:/ROMs/Pokemon - Black Version.nds")
	yaml = ArchipelagoConfig.update_yaml_value(yaml, "pokemon_bw_settings", "dump_patched_files", true)
	yaml = ArchipelagoConfig.update_yaml_value(yaml, "pokemon_bw_settings", "extended_spoiler", false)
	yaml = ArchipelagoConfig.update_yaml_value(yaml, "pokemon_bw_settings", "nested_plugin.custom_flag", "enabled")
	
	if not 'black_rom: "C:/ROMs/Pokemon - Black Version.nds"' in yaml:
		_fail("black_rom was not updated correctly")
		return
	if not 'white_rom: "C:/ROMs/Pokemon - White Version.nds"' in yaml:
		_fail("white_rom was not updated correctly")
		return
	if not 'dynamic_rom: "C:/ROMs/Pokemon - Black Version.nds"' in yaml:
		_fail("dynamic_rom was not updated correctly")
		return
	if not 'dump_patched_files: true' in yaml:
		_fail("dump_patched_files boolean was not updated correctly")
		return
	if not 'custom_flag: "enabled"' in yaml:
		_fail("nested option nested_plugin.custom_flag was not created")
		return
	print("  -> [PASS] update_yaml_value correctly patched existing keys and nested hierarchy.")

	# Test 2: patch_yaml_section batch dictionary
	print("[Test 2] Testing ArchipelagoConfig.patch_yaml_section batch patching...")
	var patches = {
		"extract_text": true,
		"ut_pack_path": "C:/Trackers/bw.zip",
		"enable_encounter_plando": false
	}
	yaml = ArchipelagoConfig.patch_yaml_section(yaml, "pokemon_bw_settings", patches)
	if not 'extract_text: true' in yaml:
		_fail("extract_text was not updated via batch patch")
		return
	if not 'ut_pack_path: "C:/Trackers/bw.zip"' in yaml:
		_fail("ut_pack_path was not updated via batch patch")
		return
	if not 'enable_encounter_plando: false' in yaml:
		_fail("enable_encounter_plando was not updated via batch patch")
		return
	print("  -> [PASS] patch_yaml_section batch patch succeeded cleanly.")

	# Test 3: End-to-end sync via GameLauncher _write_synced_host_yaml_file using data-driven mappings & template variables
	print("[Test 3] Testing GameLauncher end-to-end sync with data-driven mappings & variables...")
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	var launcher = lobby.launcher
	
	var test_yaml_path = "res://test_bw_host.yaml"
	var out_fa = FileAccess.open(test_yaml_path, FileAccess.WRITE)
	out_fa.store_string(initial_yaml)
	out_fa.close()

	launcher.launcher_presets["Pokemon Black and White"] = {
		"game_name": "Pokemon Black and White",
		"required_rom": "Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds",
		"rom_aliases": [
			"Pokemon - Black Version (USA, Europe).nds",
			"Pokemon - White Version (USA, Europe).nds",
			"Pokemon Black.nds",
			"Pokemon White.nds"
		],
		"host_yaml": {
			"section": "pokemon_bw_settings",
			"extra_sections": ["pokemon_bw_options"],
			"mappings": [
				{ "key": "dynamic_rom", "value": "{rom_path}" },
				{ "key": "black_rom", "value": "{rom_path}", "when_filename_matches": "*black*" },
				{ "key": "white_rom", "value": "{rom_path}", "when_filename_matches": "*white*" },
				{ "key": "server_destination", "value": "{server_address}" }
			],
			"options": {
				"dump_patched_files": false,
				"extract_text": true,
				"custom_setting": "{rom_path}"
			}
		}
	}

	var mock_black_path = "C:/BaseROMs/Pokemon Black.nds"
	var mock_bizhawk_path = "C:/Tools/BizHawk/EmuHawk.exe"
	var mock_server_url = "wss://ap.example.org:38281"
	launcher._write_synced_host_yaml_file(test_yaml_path, mock_black_path, mock_bizhawk_path, "", mock_server_url)

	var in_fa = FileAccess.open(test_yaml_path, FileAccess.READ)
	var synced = in_fa.get_as_text()
	in_fa.close()

	if not 'black_rom: "C:/BaseROMs/Pokemon Black.nds"' in synced:
		_fail("Synced host.yaml missing black_rom")
		return
	if not 'dynamic_rom: "C:/BaseROMs/Pokemon Black.nds"' in synced:
		_fail("Synced host.yaml missing dynamic_rom")
		return
	if not 'custom_setting: "C:/BaseROMs/Pokemon Black.nds"' in synced:
		_fail("Synced host.yaml missing custom_setting patch with {rom_path} placeholder")
		return
	if not 'server_destination: "ap.example.org:38281"' in synced:
		_fail("Synced host.yaml missing server_destination with {server_address} placeholder")
		return
	if not 'extract_text: true' in synced:
		_fail("Synced host.yaml missing extract_text option")
		return
	if not "pokemon_bw_options:" in synced:
		_fail("Synced host.yaml missing extra_sections entry pokemon_bw_options")
		return
	print("  -> [PASS] GameLauncher synced black_rom, dynamic_rom, server_address, custom options, and extra sections!")

	# Cleanup
	if FileAccess.file_exists(test_yaml_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_yaml_path))

	print("==================================================")
	print("  ALL HOST.YAML DATA-DRIVEN TESTS PASSED!         ")
	print("==================================================")
	if lobby:
		lobby.queue_free()
	quit(0)
