extends PanelContainer

signal launch_pressed(game_name: String)
signal change_path_pressed(game_name: String)

@onready var banner_panel: PanelContainer = %BannerPanel
@onready var banner_background: TextureRect = %BannerBackground
@onready var banner_texture: TextureRect = %BannerTexture
@onready var fallback_banner: CenterContainer = %FallbackBanner
@onready var fallback_label: Label = %FallbackLabel
@onready var mini_progress_bar: ProgressBar = %MiniProgressBar
@onready var game_title_label: Label = %GameTitleLabel
@onready var mode_tag_label: Label = %ModeTagLabel
@onready var mode_tag_panel: PanelContainer = %ModeTagPanel
@onready var owner_badge: Label = %OwnerBadge
@onready var slot_val_label: Label = %SlotValLabel
@onready var copy_slot_btn: Button = %CopySlotBtn
@onready var checks_container: HBoxContainer = %ChecksContainer
@onready var status_pill_panel: PanelContainer = %StatusPillPanel
@onready var status_label: Label = %StatusLabel
@onready var circular_progress_bar: Control = %CircularProgressBar
@onready var checks_progress_label: Label = %ChecksProgressLabel
@onready var main_action_btn: Button = %MainActionBtn
@onready var config_gear_btn: Button = %ConfigGearBtn
@onready var change_path_btn: Button = %ChangePathBtn

var current_game_name: String = ""
var slot_name_str: String = ""
var current_owner_name: String = ""
var is_local_player: bool = true
var _is_currently_configured: bool = false

static var _memory_texture_cache: Dictionary = {}
static var _pending_requests: Dictionary = {}

func _ready() -> void:
	_ensure_nodes()
	if is_instance_valid(copy_slot_btn) and not copy_slot_btn.pressed.is_connected(_on_copy_slot_pressed):
		copy_slot_btn.pressed.connect(_on_copy_slot_pressed)
	if is_instance_valid(main_action_btn) and not main_action_btn.pressed.is_connected(_on_main_action_pressed):
		main_action_btn.pressed.connect(_on_main_action_pressed)
	if is_instance_valid(config_gear_btn) and not config_gear_btn.pressed.is_connected(_on_config_gear_pressed):
		config_gear_btn.pressed.connect(_on_config_gear_pressed)
	if is_instance_valid(change_path_btn) and not change_path_btn.pressed.is_connected(_on_config_gear_pressed):
		change_path_btn.pressed.connect(_on_config_gear_pressed)

func _ensure_nodes() -> void:
	if banner_panel == null:
		banner_panel = get_node_or_null("%BannerPanel")
	if banner_background == null:
		banner_background = get_node_or_null("%BannerBackground")
	if banner_texture == null:
		banner_texture = get_node_or_null("%BannerTexture")
	if fallback_banner == null:
		fallback_banner = get_node_or_null("%FallbackBanner")
	if fallback_label == null:
		fallback_label = get_node_or_null("%FallbackLabel")
	if mini_progress_bar == null:
		mini_progress_bar = get_node_or_null("%MiniProgressBar")
	if game_title_label == null:
		game_title_label = get_node_or_null("%GameTitleLabel")
	if mode_tag_label == null:
		mode_tag_label = get_node_or_null("%ModeTagLabel")
	if mode_tag_panel == null:
		mode_tag_panel = get_node_or_null("%ModeTagPanel")
	if owner_badge == null:
		owner_badge = get_node_or_null("%OwnerBadge")
	if slot_val_label == null:
		slot_val_label = get_node_or_null("%SlotValLabel")
	if copy_slot_btn == null:
		copy_slot_btn = get_node_or_null("%CopySlotBtn")
	if checks_container == null:
		checks_container = get_node_or_null("%ChecksContainer")
	if status_pill_panel == null:
		status_pill_panel = get_node_or_null("%StatusPillPanel")
	if status_label == null:
		status_label = get_node_or_null("%StatusLabel")
	if circular_progress_bar == null:
		circular_progress_bar = get_node_or_null("%CircularProgressBar")
	if checks_progress_label == null:
		checks_progress_label = get_node_or_null("%ChecksProgressLabel")
	if main_action_btn == null:
		main_action_btn = get_node_or_null("%MainActionBtn")
	if config_gear_btn == null:
		config_gear_btn = get_node_or_null("%ConfigGearBtn")
	if change_path_btn == null:
		change_path_btn = get_node_or_null("%ChangePathBtn")

func setup(game_name: String, slot_name: String, preset: Dictionary, status_info: Dictionary, checks_info: Dictionary, owner_name: String = "", is_local: bool = true) -> void:
	_ensure_nodes()
	current_game_name = game_name
	slot_name_str = slot_name
	current_owner_name = owner_name
	is_local_player = is_local

	print("[DashboardCard] Initializing card for: '%s' (Slot: '%s', Owner: '%s', Local: %s)" % [game_name, slot_name, owner_name, str(is_local)])

	# 1. Game Banner Image or Fallback
	var banner_tex: Texture2D = _load_game_banner(game_name)
	_set_banner_texture(banner_tex)
	if banner_tex == null:
		fallback_label.text = game_name.to_upper()
		_style_fallback_banner(game_name)

	# 2. Title & Single Platform Mode Tag
	game_title_label.text = game_name
	_resolve_platform_tag(game_name, preset)

	# 3. Ownership Badge & Slot Name
	if is_local:
		owner_badge.text = "(You)"
		owner_badge.add_theme_color_override("font_color", Color(0.22, 0.74, 0.97))
	else:
		owner_badge.text = "👤 " + (owner_name if owner_name != "" else "Player")
		owner_badge.add_theme_color_override("font_color", Color(0.67, 0.44, 0.98))

	slot_val_label.text = "Slot: " + slot_name_str
	copy_slot_btn.tooltip_text = "Copy slot name '" + slot_name_str + "' to clipboard"

	# 4. Checks Progress (Circular Ring + Mini Bar + Count)
	update_checks_progress(checks_info)

	# 5. Status Pill & Action Button with Gear
	var is_configured: bool = status_info.get("is_configured", false)
	_update_status_and_actions(is_configured, is_local, owner_name, status_info)

func update_launch_status(status_info: Dictionary) -> void:
	_ensure_nodes()
	var is_configured: bool = status_info.get("is_configured", false)
	_update_status_and_actions(is_configured, is_local_player, current_owner_name, status_info)

func update_checks_progress(checks_info: Dictionary) -> void:
	_ensure_nodes()
	var g_checked: int = 0
	var g_total: int = 0
	if not checks_info.is_empty():
		g_checked = int(checks_info.get("checked", 0))
		g_total = int(checks_info.get("total", 0))

	if g_total > 0:
		var pct: float = (float(g_checked) / float(g_total)) * 100.0
		checks_progress_label.text = "%d / %d Checks" % [g_checked, g_total]
		mini_progress_bar.max_value = g_total
		mini_progress_bar.value = g_checked
		if is_instance_valid(circular_progress_bar):
			circular_progress_bar.max_value = g_total
			circular_progress_bar.value = g_checked
			if g_checked >= g_total:
				circular_progress_bar.progress_color = Color(0.2, 0.85, 0.5)
			else:
				circular_progress_bar.progress_color = Color(0.67, 0.44, 0.98)
		print("[DashboardCard] Checks for '%s': %d / %d (%.1f%%)" % [current_game_name, g_checked, g_total, pct])
	else:
		checks_progress_label.text = "%d Checks" % g_checked
		mini_progress_bar.max_value = 100
		mini_progress_bar.value = 0
		if is_instance_valid(circular_progress_bar):
			circular_progress_bar.max_value = 100
			circular_progress_bar.value = 0

func _resolve_platform_tag(game_name: String, preset: Dictionary) -> void:
	var req_rom: String = str(preset.get("required_rom", "")).to_lower()
	var launch_mode: String = preset.get("launch_mode", "direct")
	var g_lower: String = game_name.to_lower()

	var tag: String = "PC"
	var col: Color = Color(0.4, 0.78, 0.98)

	if preset.has("platform"):
		tag = str(preset.get("platform")).to_upper()
	elif req_rom.ends_with(".gba") or g_lower.contains("emerald") or g_lower.contains("fusion"):
		tag = "GBA"
		col = Color(0.98, 0.75, 0.14)
	elif req_rom.ends_with(".sfc") or req_rom.ends_with(".smc") or g_lower.contains("super metroid") or g_lower.contains("past"):
		tag = "SNES"
		col = Color(0.75, 0.5, 0.98)
	elif req_rom.ends_with(".z64") or req_rom.ends_with(".n64") or g_lower.contains("mario 64"):
		tag = "N64"
		col = Color(0.9, 0.35, 0.35)
	elif req_rom.ends_with(".bin") or req_rom.ends_with(".cue") or g_lower.contains("symphony"):
		tag = "PS1"
		col = Color(0.85, 0.4, 0.7)
	elif g_lower.contains("hollow") or g_lower.contains("zombies") or g_lower.contains("stardew") or launch_mode == "direct":
		tag = "PC"
		col = Color(0.4, 0.78, 0.98)

	mode_tag_label.text = tag
	mode_tag_label.add_theme_color_override("font_color", col)
	print("[DashboardCard] '%s' assigned platform mode tag: %s" % [game_name, tag])

func _set_banner_texture(tex: Texture2D) -> void:
	if is_instance_valid(banner_texture):
		banner_texture.texture = tex
		banner_texture.visible = (tex != null)
	if is_instance_valid(banner_background):
		banner_background.texture = tex
		banner_background.visible = (tex != null)
	if is_instance_valid(fallback_banner):
		fallback_banner.visible = (tex == null)

func _load_game_banner(game_name: String) -> Texture2D:
	var slug: String = _get_game_slug(game_name)

	# 1. Check in-memory cache
	if _memory_texture_cache.has(slug):
		print("[DashboardCard] Using in-memory banner cache for: %s" % slug)
		return _memory_texture_cache[slug]

	# 2. Check local disk cache (previously downloaded from backend)
	var cache_path: String = "user://cache/banners/" + slug + ".png"
	if FileAccess.file_exists(cache_path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(cache_path))
		if img and not img.is_empty():
			var tex: ImageTexture = ImageTexture.create_from_image(img)
			_memory_texture_cache[slug] = tex
			print("[DashboardCard] Loaded banner from local disk cache: %s" % cache_path)
			return tex

	# 3. Check user runtime drop-in directory
	var user_path: String = "user://banners/" + slug + ".png"
	if FileAccess.file_exists(user_path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(user_path))
		if img and not img.is_empty():
			var tex: ImageTexture = ImageTexture.create_from_image(img)
			_memory_texture_cache[slug] = tex
			print("[DashboardCard] Loaded banner from user drop-in: %s" % user_path)
			return tex

	# 4. Initiate asynchronous backend fetch
	_fetch_banner_from_backend(slug)

	# 5. Check bundled resources as immediate temporary fallback while downloading
	var res_path: String = "res://assets/banners/" + slug + ".png"
	if ResourceLoader.exists(res_path):
		var bundled_tex = load(res_path) as Texture2D
		if bundled_tex:
			print("[DashboardCard] Using bundled banner resource as temporary view: %s" % res_path)
			return bundled_tex

	return null

func _fetch_banner_from_backend(slug: String) -> void:
	if not is_inside_tree():
		await tree_entered

	# Check again in case another card downloaded it during the await
	if _memory_texture_cache.has(slug):
		var cached_tex = _memory_texture_cache[slug]
		if _get_game_slug(current_game_name) == slug:
			_set_banner_texture(cached_tex)
		return

	if _pending_requests.has(slug):
		print("[BannerLoader] Fetch already pending for '%s'; waiting for response." % slug)
		return
	_pending_requests[slug] = true

	var net_mgr = get_node_or_null("/root/NetworkManager")
	var base_url: String = "https://wayfinder.disaac1.com"
	if is_instance_valid(net_mgr) and net_mgr.has_method("get_http_url"):
		base_url = net_mgr.get_http_url()

	var urls_to_try: Array[String] = [
		base_url + "/data/games/" + slug + "/icon.png",
		base_url + "/api/games/" + slug + "/icon",
		base_url + "/data/" + slug + "/icon.png"
	]

	print("[BannerLoader] Requesting banner for '%s' from backend: %s" % [slug, urls_to_try[0]])
	_try_fetch_next_url(slug, urls_to_try, 0)

func _try_fetch_next_url(slug: String, urls: Array[String], index: int) -> void:
	if index >= urls.size():
		_pending_requests.erase(slug)
		print("[BannerLoader] No banner found on backend for '%s' across %d endpoint(s). Using procedural banner." % [slug, urls.size()])
		return

	var url: String = urls[index]
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 0:
			_pending_requests.erase(slug)
			print("[BannerLoader] Successfully downloaded banner for '%s' (%d bytes) from: %s" % [slug, body.size(), url])
			var img: Image = Image.new()
			var err = img.load_png_from_buffer(body)
			if err != OK:
				err = img.load_jpg_from_buffer(body)
			if err != OK:
				err = img.load_webp_from_buffer(body)
			if err == OK:
				var tex: ImageTexture = ImageTexture.create_from_image(img)
				_memory_texture_cache[slug] = tex

				# Write to disk cache
				DirAccess.make_dir_recursive_absolute("user://cache/banners")
				var cache_path: String = "user://cache/banners/" + slug + ".png"
				var f: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
				if f:
					f.store_buffer(body)
					f.close()
					print("[BannerLoader] Successfully saved banner to disk cache: %s" % cache_path)

				if _get_game_slug(current_game_name) == slug:
					_set_banner_texture(tex)
			else:
				printerr("[BannerLoader Error] Could not decode image data for '%s' (Format Error: %d)" % [slug, err])
		else:
			print("[BannerLoader] Endpoint %s returned %d (result: %d). Trying next candidate..." % [url, response_code, result])
			_try_fetch_next_url(slug, urls, index + 1)
	)

	var req_err: Error = http.request(url)
	if req_err != OK:
		print("[BannerLoader Error] HTTP request failed to start for '%s' -> %s (Error code: %d)" % [slug, url, req_err])
		http.queue_free()
		_try_fetch_next_url(slug, urls, index + 1)

func _update_status_and_actions(is_configured: bool, is_local: bool, owner_name: String, status_info: Dictionary = {}) -> void:
	_is_currently_configured = is_configured
	var pill_style: StyleBoxFlat = StyleBoxFlat.new()
	pill_style.set_corner_radius_all(4)
	pill_style.content_margin_left = 7.0
	pill_style.content_margin_top = 2.0
	pill_style.content_margin_right = 7.0
	pill_style.content_margin_bottom = 2.0
	pill_style.border_width_left = 1
	pill_style.border_width_top = 1
	pill_style.border_width_right = 1
	pill_style.border_width_bottom = 1

	if is_local:
		config_gear_btn.visible = true
		config_gear_btn.disabled = false
		main_action_btn.disabled = false

		var steam_chk: Dictionary = status_info.get("steam_beta_status", {})
		if is_configured and steam_chk.get("needs_downgrade", false):
			status_label.text = "Beta Needed"
			status_label.add_theme_color_override("font_color", Color(0.98, 0.75, 0.14))
			pill_style.bg_color = Color(0.2, 0.15, 0.05, 0.8)
			pill_style.border_color = Color(0.8, 0.55, 0.1, 0.7)

			main_action_btn.text = "Steam Beta Required"
			main_action_btn.add_theme_color_override("font_color", Color(0.98, 0.75, 0.14))
		elif is_configured:
			status_label.text = "Ready"
			status_label.add_theme_color_override("font_color", Color(0.2, 0.85, 0.5))
			pill_style.bg_color = Color(0.08, 0.18, 0.13, 0.8)
			pill_style.border_color = Color(0.16, 0.65, 0.38, 0.7)

			main_action_btn.text = "Launch"
			main_action_btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
		else:
			status_label.text = "Setup Required"
			status_label.add_theme_color_override("font_color", Color(0.98, 0.75, 0.14))
			pill_style.bg_color = Color(0.2, 0.15, 0.05, 0.8)
			pill_style.border_color = Color(0.8, 0.55, 0.1, 0.7)

			main_action_btn.text = "Download / Setup"
			main_action_btn.add_theme_color_override("font_color", Color(0.35, 0.8, 1.0))
		print("[DashboardCard] Local status for '%s': Configured=%s, Action='%s'" % [current_game_name, str(is_configured), main_action_btn.text])
	else:
		config_gear_btn.visible = false
		main_action_btn.disabled = true
		main_action_btn.text = (owner_name if owner_name != "" else "PLAYER").to_upper() + "'S SLOT"
		main_action_btn.add_theme_color_override("font_color", Color(0.67, 0.44, 0.98))

		status_label.text = "Active Slot"
		status_label.add_theme_color_override("font_color", Color(0.67, 0.44, 0.98))
		pill_style.bg_color = Color(0.14, 0.1, 0.22, 0.8)
		pill_style.border_color = Color(0.55, 0.35, 0.85, 0.7)

	if is_instance_valid(status_pill_panel):
		status_pill_panel.add_theme_stylebox_override("panel", pill_style)

func _get_game_slug(name: String) -> String:
	return name.to_lower().replace(" ", "_").replace("'", "").replace(".", "").replace(":", "").replace("-", "_")

func _style_fallback_banner(game_name: String) -> void:
	var fallback_style: StyleBoxFlat = StyleBoxFlat.new()
	fallback_style.corner_radius_top_left = 7
	fallback_style.corner_radius_top_right = 7
	
	var h: int = abs(game_name.hash())
	var hue: float = fmod(float(h % 360) / 360.0, 1.0)
	var col: Color = Color.from_hsv(hue, 0.45, 0.18)
	fallback_style.bg_color = col
	if is_instance_valid(banner_panel):
		banner_panel.add_theme_stylebox_override("panel", fallback_style)

func _on_main_action_pressed() -> void:
	if is_local_player:
		print("[DashboardCard] Main action button pressed for '%s' (is_configured=%s)" % [current_game_name, str(_is_currently_configured)])
		if _is_currently_configured:
			launch_pressed.emit(current_game_name)
		else:
			change_path_pressed.emit(current_game_name)

func _on_config_gear_pressed() -> void:
	if is_local_player:
		print("[DashboardCard] Config gear button pressed for '%s'" % current_game_name)
		change_path_pressed.emit(current_game_name)

func _on_copy_slot_pressed() -> void:
	if slot_name_str != "":
		DisplayServer.clipboard_set(slot_name_str)
		print("[DashboardCard] Copied slot name to clipboard: '%s'" % slot_name_str)
		copy_slot_btn.text = "Copied!"
		var tree = get_tree()
		if tree:
			await tree.create_timer(1.2).timeout
			if is_instance_valid(copy_slot_btn):
				copy_slot_btn.text = "Copy"
