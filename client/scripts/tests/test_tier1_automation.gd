extends SceneTree

var lobby: Node

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================================")
	print("  STARTING TIER 1 AUTOMATION & ENCRYPTED DISTRIBUTION TEST       ")
	print("==================================================================")
	
	var lobby_scene = load("res://scenes/lobby.tscn")
	assert(lobby_scene != null, "Failed to load lobby.tscn")
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	var launcher = lobby.launcher
	assert(launcher != null, "Launcher must be instantiated on lobby")
	
	# -------------------------------------------------------------
	# Test 1: Google Drive URL Resolution
	# -------------------------------------------------------------
	print("\n[Test 1] Testing Google Drive link resolution...")
	var gdrive_share = "https://drive.google.com/file/d/1AbC_dEfG-9876543210/view?usp=sharing"
	var resolved_share = launcher.resolve_download_url(gdrive_share)
	assert(resolved_share == "https://drive.usercontent.google.com/download?id=1AbC_dEfG-9876543210&export=download&confirm=t", "Failed share URL: " + resolved_share)
	print("  -> Share URL resolved correctly: ", resolved_share)
	
	var gdrive_open = "https://drive.google.com/open?id=XYZ_123-ABC"
	var resolved_open = launcher.resolve_download_url(gdrive_open)
	assert(resolved_open == "https://drive.usercontent.google.com/download?id=XYZ_123-ABC&export=download&confirm=t", "Failed open URL: " + resolved_open)
	print("  -> Open URL resolved correctly: ", resolved_open)
	
	var direct_url = "https://example.com/games/sotn.zip"
	var resolved_direct = launcher.resolve_download_url(direct_url)
	assert(resolved_direct == direct_url, "Direct URL altered: " + resolved_direct)
	print("  -> Direct URL preserved untouched: ", resolved_direct)
	
	# -------------------------------------------------------------
	# Test 2: ROMs Catalog Flexible Loading & Decryption Keys
	# -------------------------------------------------------------
	print("\n[Test 2] Testing roms.json catalog parsing & key inheritance...")
	launcher.roms_catalog = {
		"default_key": "SharedSecretPassphrase99",
		"Metroid Fusion (USA).gba": "https://drive.google.com/file/d/12345/view",
		"Plants vs. Zombies": {
			"url": "https://drive.google.com/file/d/67890/view",
			"key": "CustomPvZKey",
			"encrypted": true
		},
		"Hollow Knight": "https://example.com/hk.zip.enc"
	}
	
	var fusion_entry = launcher.get_rom_download_entry("Metroid Fusion (USA).gba")
	assert(fusion_entry.get("key") == "SharedSecretPassphrase99", "Failed default key inheritance")
	assert(fusion_entry.get("encrypted") == true, "Expected encrypted=true via default key")
	print("  -> Metroid Fusion inherited default key: ", fusion_entry.get("key"))
	
	var pvz_entry = launcher.get_rom_download_entry("Plants vs. Zombies")
	assert(pvz_entry.get("key") == "CustomPvZKey", "Failed custom key override")
	assert(pvz_entry.get("encrypted") == true, "Expected encrypted=true for PvZ")
	print("  -> Plants vs. Zombies used custom key: ", pvz_entry.get("key"))
	
	# Case-insensitive lookup test
	var hk_entry = launcher.get_rom_download_entry("hollow knight")
	assert(not hk_entry.is_empty(), "Failed case-insensitive lookup")
	assert(hk_entry.get("encrypted") == true, "Expected .enc detection")
	print("  -> Case-insensitive lookup succeeded for Hollow Knight.")
	
	# -------------------------------------------------------------
	# Test 3: Cross-Platform AES-256 Decryption
	# -------------------------------------------------------------
	print("\n[Test 3] Testing AES-256 Decryption with Python-generated ciphertext...")
	var tool_script: String = ProjectSettings.globalize_path("res://../tools/encrypt_game_file.py").replace("\\", "/")
	var global_raw: String = ProjectSettings.globalize_path("user://test_raw.txt").replace("\\", "/")
	var global_enc: String = ProjectSettings.globalize_path("user://test_raw.txt.enc").replace("\\", "/")
	var global_dec: String = ProjectSettings.globalize_path("user://test_raw_decrypted.txt").replace("\\", "/")
	
	# Write raw file
	var raw_file = FileAccess.open("user://test_raw.txt", FileAccess.WRITE)
	raw_file.store_string("PK_TEST_ENCRYPTED_GAME_PAYLOAD_12345")
	raw_file.close()
	
	var py_output: Array = []
	var exit_code = OS.execute("py", ["-3.12", tool_script, "--input", global_raw, "--output", global_enc, "--key", "TestKey456"], py_output)
	if exit_code != 0:
		print("Python execution error output: ", py_output)
	assert(exit_code == 0, "Python encryption failed with exit code: " + str(exit_code))
	
	var dec_ok = launcher.decrypt_file_aes256(global_enc, global_dec, "TestKey456")
	assert(dec_ok == true, "Godot AES-256 decryption returned false")
	
	var dec_file = FileAccess.open(global_dec, FileAccess.READ)
	assert(dec_file != null, "Could not open decrypted file")
	var dec_text = dec_file.get_as_text()
	dec_file.close()
	assert(dec_text == "PK_TEST_ENCRYPTED_GAME_PAYLOAD_12345", "Decrypted content mismatch: " + dec_text)
	print("  -> Decrypted content verified byte-for-byte: ", dec_text)
	
	# Clean up test files
	DirAccess.remove_absolute(global_raw)
	DirAccess.remove_absolute(global_enc)
	DirAccess.remove_absolute(global_dec)
	
	# -------------------------------------------------------------
	# Test 4: All 4 Games Tier 1 Presets Verification
	# -------------------------------------------------------------
	print("\n[Test 4] Verifying Tier 1 Automation Configuration for all 4 games...")
	await launcher.load_launcher_config()
	
	# 1. Hollow Knight
	var hk_preset = launcher.get_preset("Hollow Knight")
	assert(not hk_preset.is_empty(), "Hollow Knight preset missing")
	assert(hk_preset.get("support_tier") == 1, "HK must be Tier 1")
	assert(hk_preset.has("packages"), "HK must have packages array")
	assert(hk_preset.get("packages").size() >= 2, "HK must have Modding API & AP mods packages")
	assert(hk_preset.has("config_writer"), "HK must have config_writer")
	print("  -> [PASS] Hollow Knight: Tier 1 (Modding API, Archipelago Mods, GlobalSettings.json auto-writer)")
	
	# 2. Symphony of the Night
	var sotn_preset = launcher.get_preset("Symphony of the Night")
	assert(not sotn_preset.is_empty(), "SotN preset missing")
	assert(sotn_preset.get("support_tier") == 1, "SotN must be Tier 1")
	assert(sotn_preset.get("launch_mode") == "ap_client", "SotN must use ap_client")
	assert(sotn_preset.get("required_rom") != "", "SotN must specify Track 1 ROM")
	assert(sotn_preset.get("required_audio_rom") != "", "SotN must specify Track 2 ROM")
	assert(sotn_preset.has("patch_progress_tracking"), "SotN must have disc sector tracking")
	print("  -> [PASS] Symphony of the Night: Tier 1 (Dual-track ROMs, BizHawk Client, Disc sector modding)")
	
	# 3. Plants vs. Zombies
	var pvz_preset = launcher.get_preset("Plants vs. Zombies")
	assert(not pvz_preset.is_empty(), "PvZ preset missing")
	assert(pvz_preset.get("support_tier") == 1, "PvZ must be Tier 1")
	assert(pvz_preset.get("launch_mode") == "direct", "PvZ must use direct launch")
	assert(pvz_preset.has("packages"), "PvZ must have packages array")
	assert(pvz_preset.get("packages").size() >= 2, "PvZ must have MelonLoader & Replanted mod packages")
	assert(pvz_preset.has("config_writer"), "PvZ must have config_writer")
	print("  -> [PASS] Plants vs. Zombies: Tier 1 (MelonLoader, Replanted AP Mod, MelonPreferences.cfg auto-writer)")
	
	# 4. Metroid Fusion
	var fusion_preset = launcher.get_preset("Metroid Fusion")
	assert(not fusion_preset.is_empty(), "Metroid Fusion preset missing")
	assert(fusion_preset.get("support_tier") == 1, "Metroid Fusion must be Tier 1")
	assert(fusion_preset.get("launch_mode") == "ap_client", "Fusion must use ap_client")
	assert(fusion_preset.get("required_rom") == "Metroid Fusion (USA).gba", "Fusion must require GBA ROM")
	assert(fusion_preset.get("auto_connect") == true, "Fusion must auto-connect")
	print("  -> [PASS] Metroid Fusion: Tier 1 (GBA ROM, BizHawk Client, .apmetfus auto-connect)")
	
	print("\n==================================================================")
	print("  ALL TIER 1 AUTOMATION & ENCRYPTION TESTS PASSED!               ")
	print("==================================================================")
	quit()
