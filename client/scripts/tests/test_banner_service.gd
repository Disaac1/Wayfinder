extends SceneTree

# =====================================================================
#             TEST SUITE: BANNER LOADER SERVICE & CACHE
# =====================================================================

var test_passed: bool = true

const BannerService = preload("res://scripts/core/banner_service.gd")
const DashboardGameCardScript = preload("res://scripts/ui/components/dashboard_game_card.gd")

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
		print("\n  [SUCCESS] All BannerService tests passed!")
		quit(0)
	else:
		printerr("\n  [FAILURE] Some BannerService tests failed.")
		quit(1)

func _run_suite() -> void:
	print("==================================================================")
	print("  TEST SUITE: BANNER LOADER SERVICE & CACHE                      ")
	print("==================================================================")

	# -------------------------------------------------------------
	# 1. Static In-Memory Cache
	# -------------------------------------------------------------
	print("\n[Test 1] Verifying static in-memory cache operations...")
	BannerService.clear_cache()
	_assert_true(not BannerService.has_cached_texture("test_slug"), "Cache should be empty initially")

	# Create a dummy 16x16 image and texture
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var dummy_tex: ImageTexture = ImageTexture.create_from_image(img)

	BannerService.set_cached_texture("test_slug", dummy_tex)
	_assert_true(BannerService.has_cached_texture("test_slug"), "Cache should contain test_slug")
	_assert_true(BannerService.get_cached_texture("test_slug") == dummy_tex, "Cached texture should match")

	BannerService.clear_cache()
	_assert_true(not BannerService.has_cached_texture("test_slug"), "Cache should be cleared")
	print("  -> Passed: Static memory cache verified.")

	# -------------------------------------------------------------
	# 2. Slug Resolution & URL Generation
	# -------------------------------------------------------------
	print("\n[Test 2] Verifying slug resolution and candidate URLs...")
	var slug = BannerService.get_game_slug("Super Metroid", {})
	_assert_true(slug != "", "Slug should not be empty")

	var urls = BannerService.get_candidate_urls("super_metroid")
	_assert_true(urls.size() == 3, "Expected 3 candidate URLs, got: " + str(urls.size()))
	_assert_true(urls[0].ends_with("/data/games/super_metroid/icon.png"), "URL 0 pattern mismatch: " + urls[0])
	_assert_true(urls[1].ends_with("/api/games/super_metroid/icon"), "URL 1 pattern mismatch: " + urls[1])
	_assert_true(urls[2].ends_with("/data/super_metroid/icon.png"), "URL 2 pattern mismatch: " + urls[2])
	print("  -> Passed: Slug and URL candidates verified.")

	# -------------------------------------------------------------
	# 3. Disk Cache Loading
	# -------------------------------------------------------------
	print("\n[Test 3] Verifying disk cache loading...")
	DirAccess.make_dir_recursive_absolute("user://cache/banners")
	var disk_cache_path = "user://cache/banners/disk_test_game.png"
	var test_img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	test_img.fill(Color.GREEN)
	test_img.save_png(ProjectSettings.globalize_path(disk_cache_path))

	BannerService.clear_cache()
	var loaded_tex = BannerService.load_banner_by_slug("disk_test_game")
	_assert_true(loaded_tex != null, "Failed to load banner from disk cache")
	_assert_true(BannerService.has_cached_texture("disk_test_game"), "Banner should be cached in memory after disk load")
	print("  -> Passed: Disk cache loaded and promoted to memory cache.")

	# -------------------------------------------------------------
	# 4. User Drop-in Directory Lookup
	# -------------------------------------------------------------
	print("\n[Test 4] Verifying user drop-in directory lookup...")
	DirAccess.make_dir_recursive_absolute("user://banners")
	var user_path = "user://banners/dropin_test_game.png"
	var dropin_img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	dropin_img.fill(Color.BLUE)
	dropin_img.save_png(ProjectSettings.globalize_path(user_path))

	BannerService.clear_cache()
	var dropin_tex = BannerService.load_banner_by_slug("dropin_test_game")
	_assert_true(dropin_tex != null, "Failed to load banner from user dropin directory")
	_assert_true(BannerService.has_cached_texture("dropin_test_game"), "Dropin banner should be cached in memory")
	print("  -> Passed: User drop-in lookup verified.")

	# -------------------------------------------------------------
	# 5. Exhausted URLs Fallback Handling
	# -------------------------------------------------------------
	print("\n[Test 5] Verifying exhausted URLs callback...")
	var callback_data: Dictionary = {"called": false, "result": "uncalled"}
	BannerService.fetch_banner_from_backend("exhausted_test_slug", null, func(_s: String, tex: Texture2D):
		callback_data["called"] = true
		callback_data["result"] = tex
	)
	# Trigger end of candidate URLs
	BannerService.try_fetch_next_url("exhausted_test_slug", [], 0)
	_assert_true(callback_data["called"], "Callback should be called when URLs exhausted")
	_assert_true(callback_data["result"] == null, "Result should be null when exhausted")
	_assert_true(not BannerService.is_request_pending("exhausted_test_slug"), "Pending request should be erased")
	print("  -> Passed: Exhausted URLs handling verified.")

	# -------------------------------------------------------------
	# 6. DashboardGameCard Integration
	# -------------------------------------------------------------
	print("\n[Test 6] Verifying DashboardGameCard delegation to BannerService...")
	var card_scene = load("res://scenes/components/dashboard_game_card.tscn") as PackedScene
	_assert_true(card_scene != null, "Failed to load dashboard_game_card.tscn")
	var card = card_scene.instantiate()
	_assert_true(card != null, "Failed to instantiate dashboard_game_card")

	# Set a memory cache item and check if card._load_game_banner returns it
	BannerService.set_cached_texture("card_delegation_game", dummy_tex)
	var card_banner = card._load_game_banner("card_delegation_game")
	_assert_true(card_banner == dummy_tex, "Card delegation to BannerService._load_game_banner failed")

	card.queue_free()
	print("  -> Passed: DashboardGameCard delegation verified.")

	_finish()
