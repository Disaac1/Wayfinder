extends SceneTree

var test_passed: bool = true

func _init() -> void:
	_run_test.call_deferred()

func _fail(reason: String) -> void:
	printerr("[Launcher Services Failure] ", reason)
	test_passed = false

func _run_test() -> void:
	print("\n============================================================")
	print("  STARTING LAUNCHER SERVICES TEST SUITE")
	print("============================================================")

	var resolver_script = load("res://scripts/core/game_identity_resolver.gd")
	var resolver = resolver_script.new({
		"Example Game": {
			"game_name": "Example Game",
			"slug": "example_game",
			"aliases": ["Example", "Example Classic"],
			"required_rom": "Example (USA).rom",
			"rom_aliases": ["ExampleGame.rom"]
		}
	})

	assert(resolver.normalize("Example-Game") == "examplegame", "Normalization should remove separators")
	assert(resolver.get_slug("Example Classic") == "example_game", "Alias should resolve to configured slug")
	assert(resolver.has_preset("example game"), "Canonical name should resolve case-insensitively")
	assert(resolver.has_preset("Example"), "Alias should resolve to a preset")
	assert(resolver.get_preset("unknown game").get("launch_mode") == "ap_client", "Unknown games should receive AP client fallback")
	assert(resolver.game_slug_for_rom("ExampleGame.rom") == "example_game", "ROM alias should resolve to configured slug")
	assert(resolver.game_slug_for_rom("Example Game (USA).rom") == "example_game", "ROM title should resolve to configured slug")
	assert(resolver.get_slug("New Community Game") == "new_community_game", "Unknown names should use the canonical fallback slug")
	print("  -> Identity resolution and fallback behavior passed.")

	var store_script = load("res://scripts/core/launcher_config_store.gd")
	var store = store_script.new()
	store.tools["example_tool"] = {"name": "Example Tool"}
	store.games["Example Game"] = {"game_name": "Example Game", "slug": "example_game"}
	assert(store.tools.has("example_tool"), "Config store should expose tool records")
	assert(store.games.has("Example Game"), "Config store should expose game records")
	store.tools.clear()
	store.games.clear()
	assert(store.tools.is_empty() and store.games.is_empty(), "Config store dictionaries should be mutable by the owner")
	print("  -> Configuration store ownership behavior passed.")

	var tool_manager_script = load("res://scripts/core/tool_manager.gd")
	var tool_manager = tool_manager_script.new({}, null, Callable())
	assert(tool_manager.resolve_download_url("/api/tools/example") == "https://wayfinder.disaac1.com/api/tools/example", "Relative tool URL should use the backend URL")
	assert(tool_manager.get_temp_download_path("Example Tool", "https://example.com/tool.zip").ends_with("temp_Example Tool.zip"), "ZIP temporary path should preserve the expected extension")

	var valid_zip_path := "user://launcher_service_test.zip"
	var valid_zip := FileAccess.open(valid_zip_path, FileAccess.WRITE)
	var zip_bytes := PackedByteArray()
	zip_bytes.resize(1024)
	zip_bytes[0] = 0x50
	zip_bytes[1] = 0x4B
	valid_zip.store_buffer(zip_bytes)
	valid_zip.close()
	var validation: Dictionary = tool_manager.validate_download_file(valid_zip_path)
	assert(validation.get("valid", false), "ZIP header should pass tool download validation")
	assert(validation.get("format") == "zip", "ZIP header should be classified as zip")
	DirAccess.remove_absolute(valid_zip_path)
	print("  -> Tool URL and download validation behavior passed.")

	print("\n============================================================")
	if test_passed:
		print("  ALL LAUNCHER SERVICES TESTS PASSED! [OK]")
	else:
		print("  LAUNCHER SERVICES TESTS FAILED")
		quit(1)
		return
	quit(0)
