extends SceneTree

const RomCatalogManager = preload("res://scripts/core/rom_catalog_manager.gd")

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("\n==================================================")
	print("       RUNNING ROM CATALOG SYSTEM TESTS           ")
	print("==================================================")
	
	test_url_derivation()
	test_save_and_load_catalog()
	test_load_from_local_file()
	test_game_launcher_integration()
	test_download_error_handling()
	test_main_menu_and_modal_ui()
	
	print("\n==================================================")
	print("     ALL ROM CATALOG SYSTEM TESTS PASSED! ✅       ")
	print("==================================================")
	quit(0)

func test_url_derivation() -> void:
	print("[Test 1] Testing default catalog URL generation...")
	var url1 = RomCatalogManager.get_default_catalog_url("wss://wayfinder.disaac1.com")
	assert(url1 == "https://wayfinder.disaac1.com/rom.json", "Expected https://wayfinder.disaac1.com/rom.json, got " + url1)
	
	var url2 = RomCatalogManager.get_default_catalog_url("ws://localhost:8080")
	assert(url2 == "http://localhost:8080/rom.json", "Expected http://localhost:8080/rom.json, got " + url2)
	
	var url3 = RomCatalogManager.get_default_catalog_url("")
	assert(url3 == "https://wayfinder.disaac1.com/rom.json", "Expected default url, got " + url3)
	
	var url4 = RomCatalogManager.get_default_catalog_url("wss://custom-archipelago.org:8443/ws")
	assert(url4 == "https://custom-archipelago.org:8443/rom.json", "Expected https://custom-archipelago.org:8443/rom.json, got " + url4)
	print("  -> Passed URL generation checks.")

func test_save_and_load_catalog() -> void:
	print("[Test 2] Testing save_catalog and load_catalog...")
	var sample_data = {
		"Pokemon - Emerald Version (USA).gba": "https://archive.org/download/pkmn_emerald.zip",
		"Super Mario 64 (USA).z64": {
			"url": "https://example.com/sm64.z64",
			"key": "test_passphrase",
			"encrypted": true
		},
		"Castlevania - Symphony of the Night (USA) (Track 1).bin": ""
	}
	
	var ok = RomCatalogManager.save_catalog(sample_data)
	assert(ok, "Failed to save sample catalog")
	
	assert(FileAccess.file_exists("user://rom.json"), "user://rom.json was not created")
	assert(FileAccess.file_exists("user://roms.json"), "user://roms.json was not created")
	
	var loaded = RomCatalogManager.load_catalog()
	assert(loaded.size() == 3, "Expected 3 entries in loaded catalog, got " + str(loaded.size()))
	assert(loaded.has("Pokemon - Emerald Version (USA).gba"), "Missing Pokemon Emerald")
	assert(loaded.has("Super Mario 64 (USA).z64"), "Missing SM64")
	assert(loaded.has("Castlevania - Symphony of the Night (USA) (Track 1).bin"), "Missing SOTN")
	
	var info = RomCatalogManager.get_catalog_info()
	assert(info.get("exists") == true, "info.exists should be true")
	assert(info.get("total_count") == 3, "Expected total_count = 3")
	assert(info.get("configured_count") == 2, "Expected configured_count = 2 (1 empty)")
	print("  -> Passed save, load, and info checks.")

func test_load_from_local_file() -> void:
	print("[Test 3] Testing load_from_local_file...")
	var test_file_path = "user://temp_test_local_catalog.json"
	var f = FileAccess.open(test_file_path, FileAccess.WRITE)
	var local_content = {
		"Metroid Fusion (USA).gba": "https://example.com/fusion.gba",
		"Legend of Zelda, The - A Link to the Past (USA).sfc": "https://example.com/alttp.sfc"
	}
	f.store_string(JSON.stringify(local_content))
	f.close()
	
	var res = RomCatalogManager.load_from_local_file(test_file_path)
	assert(res.get("success") == true, "load_from_local_file failed")
	assert(res.get("total_count") == 2, "Expected total_count = 2")
	assert(res.get("configured_count") == 2, "Expected configured_count = 2")
	
	var loaded = RomCatalogManager.load_catalog()
	assert(loaded.has("Metroid Fusion (USA).gba"), "Expected Metroid Fusion in loaded catalog")
	
	DirAccess.remove_absolute(test_file_path)
	print("  -> Passed local file import check.")

func test_game_launcher_integration() -> void:
	print("[Test 4] Testing GameLauncher integration with RomCatalogManager...")
	var test_data = {
		"Pokemon - Emerald Version (USA).gba": "https://archive.org/download/emerald_test.gba"
	}
	RomCatalogManager.save_catalog(test_data)
	
	var launcher_script = load("res://scripts/core/game_launcher.gd")
	assert(launcher_script != null, "Failed to load game_launcher.gd")
	var launcher = launcher_script.new()
	launcher.load_roms_catalog()
	
	var entry = launcher.get_rom_download_entry("Pokemon - Emerald Version (USA).gba")
	assert(not entry.is_empty(), "Launcher could not resolve entry for Pokemon Emerald")
	assert(entry.get("url") == "https://archive.org/download/emerald_test.gba", "Entry URL mismatch: " + str(entry))
	print("  -> Passed GameLauncher integration check.")

func test_download_error_handling() -> void:
	print("[Test 4b] Testing download_catalog_from_url error handling...")
	var dummy_node = Node.new()
	root.add_child(dummy_node)
	
	var state = {"called": false, "success": true}
	RomCatalogManager.download_catalog_from_url(dummy_node, "not_a_valid_url", func(success, _msg, _count, _data):
		state.called = true
		state.success = success
	)
	assert(state.called, "Callback was not called for invalid URL")
	assert(!state.success, "Should have failed on invalid URL")
	dummy_node.queue_free()
	print("  -> Passed download error handling check.")

func test_main_menu_and_modal_ui() -> void:
	print("[Test 5] Testing MainMenu scene and RomCatalogModal instantiations...")
	var menu_scene = load("res://scenes/main_menu.tscn") as PackedScene
	assert(menu_scene != null, "Could not load main_menu.tscn")
	
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	
	# Verify UI nodes exist in MainMenu
	assert(menu.get_node("%RomStatusBadge") != null, "Missing %RomStatusBadge")
	assert(menu.get_node("%RomUrlInput") != null, "Missing %RomUrlInput")
	assert(menu.get_node("%RomDownloadBtn") != null, "Missing %RomDownloadBtn")
	assert(menu.get_node("%RomLoadFileBtn") != null, "Missing %RomLoadFileBtn")
	assert(menu.get_node("%RomManageBtn") != null, "Missing %RomManageBtn")
	assert(menu.get_node("%RomFolderBtn") != null, "Missing %RomFolderBtn")
	assert(menu.get_node("%RomCatalogModal") != null, "Missing %RomCatalogModal")
	assert(menu.get_node("%RomFileDialog") != null, "Missing %RomFileDialog")
	
	# Verify status badge text is populated
	var badge: Label = menu.get_node("%RomStatusBadge") as Label
	assert(badge.text != "", "Badge text was empty")
	
	# Test opening RomCatalogModal
	var modal = menu.get_node("%RomCatalogModal")
	assert(modal.visible == false, "Modal should initially be hidden")
	modal.open("https://wayfinder.disaac1.com/rom.json")
	assert(modal.visible == true, "Modal should be visible after open()")
	
	var url_in: LineEdit = modal.get_node("%UrlInput") as LineEdit
	assert(url_in.text == "https://wayfinder.disaac1.com/rom.json", "UrlInput in modal mismatch")
	
	modal.close()
	assert(modal.visible == false, "Modal should be hidden after close()")
	
	menu.queue_free()
	print("  -> Passed MainMenu and modal UI instantiations.")
