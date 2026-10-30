extends SceneTree

# =====================================================================
#             HOST YAML EDITOR & CONFIG SYNC TEST SUITE
# =====================================================================
# Validates the dedicated HostYamlEditor engine:
# - Comment & whitespace preservation
# - Arbitrary depth traversal & insertion
# - Native type formatting (bool, int, float, string, list, dict)
# - Nested dictionary application & dot-path resolution
# - ArchipelagoConfig delegation APIs
# =====================================================================

const HostYamlEditorScript = preload("res://scripts/core/host_yaml_editor.gd")
const ArchipelagoConfigScript = preload("res://scripts/core/archipelago_config.gd")

var test_passed: bool = true

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
	print("  SUITE: HOST YAML EDITOR & SPECIFICATION TESTS                   ")
	print("==================================================================")

	var sample_yaml: String = """# Global Archipelago Options
general_options:
  # Where to place output files
  output_path: "output"

# Various Luigi Mansion Settings
luigismansion_options:
  # Locate your Luigi's Mansion ISO
  iso_file: "None"
  # Various Emulator specific settings (such as Dolphin)
  dolphin_settings:
    path: "" # path to dolphin
    additional_args: []
    auto_start: false

server_options:
  port: 38281
  disable_save: false
"""

	# -------------------------------------------------------------
	# Test 1: Updating existing scalars at arbitrary depth
	# -------------------------------------------------------------
	print("\n[Test 1] Verifying updates to existing keys across depth levels...")
	var editor = HostYamlEditorScript.new(sample_yaml)
	editor.set_value_at_path("general_options.output_path", "custom_dir")
	editor.set_value_at_path("luigismansion_options.iso_file", "C:/Games/LM.iso")
	editor.set_value_at_path("luigismansion_options.dolphin_settings.path", "C:/Emulators/Dolphin.exe")
	editor.set_value_at_path("luigismansion_options.dolphin_settings.auto_start", true)
	editor.set_value_at_path("server_options.port", 39000)

	var res1: String = editor.to_string_content()
	_assert_true("output_path: \"custom_dir\"" in res1, "output_path not updated")
	_assert_true("iso_file: \"C:/Games/LM.iso\"" in res1, "iso_file not updated")
	_assert_true("path: \"C:/Emulators/Dolphin.exe\" # path to dolphin" in res1, "path not updated or inline comment lost")
	_assert_true("auto_start: true" in res1, "auto_start boolean not updated")
	_assert_true("port: 39000" in res1, "port int not updated")
	print("  -> Passed: Scalars updated with inline comments preserved.")

	# -------------------------------------------------------------
	# Test 2: Inserting new subkeys and new subsections
	# -------------------------------------------------------------
	print("\n[Test 2] Verifying insertion of new subkeys and new subsections...")
	editor.set_value_at_path("luigismansion_options.dolphin_settings.fullscreen", true)
	editor.set_value_at_path("luigismansion_options.custom_cheats.infinite_health", false)
	editor.set_value_at_path("brand_new_game.options.debug_level", 3)

	var res2: String = editor.to_string_content()
	_assert_true("fullscreen: true" in res2, "Missing newly inserted fullscreen subkey")
	_assert_true("custom_cheats:" in res2, "Missing newly inserted custom_cheats subsection")
	_assert_true("infinite_health: false" in res2, "Missing newly inserted infinite_health key")
	_assert_true("brand_new_game:" in res2, "Missing newly inserted root section")
	_assert_true("debug_level: 3" in res2, "Missing newly inserted deep key")
	print("  -> Passed: Arbitrary insertions into existing and new sections verified.")

	# -------------------------------------------------------------
	# Test 3: Comment and structural preservation
	# -------------------------------------------------------------
	print("\n[Test 3] Verifying comments and untouched sections preservation...")
	_assert_true("# Global Archipelago Options" in res2, "Header comment missing")
	_assert_true("# Where to place output files" in res2, "Section comment missing")
	_assert_true("# Various Luigi Mansion Settings" in res2, "Luigi comment missing")
	_assert_true("disable_save: false" in res2, "Untouched key server_options.disable_save missing")
	print("  -> Passed: Original comments and untouched sections preserved.")

	# -------------------------------------------------------------
	# Test 4: Recursive Dictionary Application
	# -------------------------------------------------------------
	print("\n[Test 4] Verifying apply_dictionary with nested and dot-notation keys...")
	var editor2 = HostYamlEditorScript.new(sample_yaml)
	var patch_dict: Dictionary = {
		"luigismansion_options": {
			"iso_file": "C:/Games/Luigi.iso",
			"dolphin_settings": {
				"path": "C:/Dolphin/Dolphin.exe",
				"auto_start": true
			}
		},
		"bizhawkclient_options.emuhawk_path": "C:/BizHawk/EmuHawk.exe",
		"bizhawkclient_options.rom_start": true
	}
	editor2.apply_dictionary(patch_dict)
	var res4: String = editor2.to_string_content()
	_assert_true("iso_file: \"C:/Games/Luigi.iso\"" in res4, "iso_file missing from apply_dictionary")
	_assert_true("path: \"C:/Dolphin/Dolphin.exe\"" in res4, "dolphin path missing from apply_dictionary")
	_assert_true("auto_start: true" in res4, "auto_start missing from apply_dictionary")
	_assert_true("emuhawk_path: \"C:/BizHawk/EmuHawk.exe\"" in res4, "emuhawk_path missing from apply_dictionary")
	print("  -> Passed: apply_dictionary verified successfully.")

	# -------------------------------------------------------------
	# Test 5: ArchipelagoConfig Delegation Compatibility
	# -------------------------------------------------------------
	print("\n[Test 5] Verifying ArchipelagoConfig backward-compatible wrappers...")
	var res5: String = ArchipelagoConfigScript.update_yaml_bizhawk_block(sample_yaml, "C:/Emu/EmuHawk.exe")
	_assert_true("emuhawk_path: \"C:/Emu/EmuHawk.exe\"" in res5, "ArchipelagoConfig.update_yaml_bizhawk_block failed")
	_assert_true("rom_start: true" in res5, "ArchipelagoConfig.update_yaml_bizhawk_block rom_start failed")

	var res6: String = ArchipelagoConfigScript.update_yaml_dolphin_block(sample_yaml, "C:/Dolphin/Dolphin.exe")
	_assert_true("path: \"C:/Dolphin/Dolphin.exe\"" in res6, "ArchipelagoConfig.update_yaml_dolphin_block failed")
	print("  -> Passed: ArchipelagoConfig delegation wrappers verified.")

	_finish()

func _finish() -> void:
	print("\n==================================================================")
	if test_passed:
		print("  SUITE: ALL HOST YAML EDITOR TESTS PASSED! [OK]                 ")
	else:
		printerr("  SUITE: HOST YAML EDITOR TESTS FAILED!                          ")
	print("==================================================================")
	quit(0 if test_passed else 1)
