extends SceneTree

# =====================================================================
#             TEST SUITE: UPDATE OVERLAY MODAL & MAIN MENU
# =====================================================================

var test_passed: bool = true

func _init() -> void:
	_run_suite.call_deferred()

func _fail(reason: String) -> void:
	printerr("  ❌ [FAIL] ", reason)
	test_passed = false

func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)

func _finish() -> void:
	if test_passed:
		print("\n  [SUCCESS] All UpdateOverlay tests passed!")
		quit(0)
	else:
		printerr("\n  [FAILURE] Some UpdateOverlay tests failed.")
		quit(1)

func _run_suite() -> void:
	print("==================================================================")
	print("  TEST SUITE: UPDATE OVERLAY MODAL & INTEGRATION                  ")
	print("==================================================================")

	var tree_root: Window = get_root()

	# -------------------------------------------------------------
	# 1. UpdateOverlay Scene Loading & Component Hierarchy
	# -------------------------------------------------------------
	print("\n[Test 1] Verifying update_overlay.tscn loading and hierarchy...")
	var scene = load("res://scenes/modals/update_overlay.tscn") as PackedScene
	_assert_true(scene != null, "Failed to load res://scenes/modals/update_overlay.tscn")

	var overlay = scene.instantiate()
	_assert_true(overlay != null, "Failed to instantiate update_overlay.tscn")
	tree_root.add_child(overlay)

	var message_label: Label = overlay.get_node_or_null("%MessageLabel")
	var download_button: Button = overlay.get_node_or_null("%DownloadButton")
	var update_spinner: Control = overlay.get_node_or_null("%UpdateSpinner")

	_assert_true(message_label != null, "Missing %MessageLabel node")
	_assert_true(download_button != null, "Missing %DownloadButton node")
	_assert_true(update_spinner != null, "Missing %UpdateSpinner node")
	print("  -> Passed: UpdateOverlay scene and nodes loaded successfully.")

	# -------------------------------------------------------------
	# 2. Manual Update Flow
	# -------------------------------------------------------------
	print("\n[Test 2] Verifying manual update mode...")
	overlay.start_manual_update({"version": "1.2.3", "download_url": "/api/client/download-client"})
	_assert_true(overlay.visible, "Overlay should be visible after start_manual_update")
	_assert_true(download_button.visible, "Download button should be visible in manual update mode")
	_assert_true(not update_spinner.visible, "Update spinner should be hidden in manual update mode")
	_assert_true("Install v1.2.3 to continue." in message_label.text, "Message should contain version string")
	print("  -> Passed: Manual update state verified.")

	# -------------------------------------------------------------
	# 3. Forced Update Failure Flow
	# -------------------------------------------------------------
	print("\n[Test 3] Verifying forced update failure mode...")
	overlay.start_forced_update_failure("Network timeout occurred.")
	_assert_true(overlay.visible, "Overlay should be visible after start_forced_update_failure")
	_assert_true(not download_button.visible, "Download button should be hidden in failure mode")
	_assert_true(not update_spinner.visible, "Update spinner should be hidden in failure mode")
	_assert_true("Network timeout occurred." in message_label.text, "Message should display failure reason")
	print("  -> Passed: Forced update failure state verified.")

	# -------------------------------------------------------------
	# 4. Reset & Close
	# -------------------------------------------------------------
	print("\n[Test 4] Verifying reset and close behavior...")
	overlay.reset()
	_assert_true(not overlay.visible, "Overlay should not be visible after reset")
	_assert_true(not download_button.visible, "Download button should be hidden after reset")
	_assert_true(not update_spinner.visible, "Update spinner should be hidden after reset")
	print("  -> Passed: Reset and close behavior verified.")

	overlay.queue_free()

	# -------------------------------------------------------------
	# 5. Main Menu Integration
	# -------------------------------------------------------------
	print("\n[Test 5] Verifying MainMenu scene with UpdateOverlay...")
	var main_menu_scene = load("res://scenes/main_menu.tscn") as PackedScene
	_assert_true(main_menu_scene != null, "Failed to load res://scenes/main_menu.tscn")
	var main_menu = main_menu_scene.instantiate()
	_assert_true(main_menu != null, "Failed to instantiate main_menu.tscn")
	tree_root.add_child(main_menu)

	var menu_overlay = main_menu.get_node_or_null("%UpdateOverlay")
	_assert_true(menu_overlay != null, "MainMenu should contain %UpdateOverlay child")

	main_menu._start_manual_update({"version": "9.9.9"})
	var menu_msg: Label = menu_overlay.get_node_or_null("%MessageLabel")
	_assert_true(menu_overlay.visible, "UpdateOverlay should be visible after main_menu._start_manual_update")
	_assert_true("Install v9.9.9 to continue." in menu_msg.text, "MainMenu delegation to UpdateOverlay failed")

	main_menu.queue_free()
	print("  -> Passed: MainMenu integration verified.")

	_finish()
