extends Control

# --- DEPENDENCIES ---
const YamlBuilder = preload("res://scripts/core/yaml_builder.gd")

signal closed()
signal confirmed(game_name: String, game_path: String, emu_path: String)
signal download_auto_pressed()
signal game_selected(game_name: String)
signal steam_btn_pressed()
signal recheck_btn_pressed()
signal cancellation_requested()

@onready var launch_title: Label = %LaunchTitle
@onready var launch_close_btn: Button = %LaunchCloseBtn
@onready var launch_instructions: RichTextLabel = %LaunchInstructions
@onready var launch_progress_bar: ProgressBar = %LaunchProgressBar
@onready var game_selection_section: VBoxContainer = %GameSelectionSection
@onready var game_selection_label: Label = %GameSelectionLabel
@onready var game_selection_buttons: VBoxContainer = %GameSelectionButtons
@onready var path_section: VBoxContainer = %PathSection
@onready var path_label: Label = %PathLabel
@onready var launch_path_input: LineEdit = %LaunchPathInput
@onready var launch_path_browse_btn: Button = %LaunchPathBrowseBtn
@onready var launch_download_btn: Button = %LaunchDownloadBtn
@onready var launch_steam_btn: Button = %LaunchSteamBtn
@onready var launch_recheck_btn: Button = %LaunchRecheckBtn
@onready var emulator_path_section: VBoxContainer = %EmulatorPathSection
@onready var emulator_path_label: Label = %EmulatorPathLabel
@onready var launch_emulator_path_input: LineEdit = %LaunchEmulatorPathInput
@onready var launch_emulator_path_browse_btn: Button = %LaunchEmulatorPathBrowseBtn
@onready var launch_cancel_btn: Button = %LaunchCancelBtn
@onready var launch_confirm_btn: Button = %LaunchConfirmBtn
@onready var launch_file_dialog: FileDialog = %LaunchFileDialog
@onready var download_progress_card: PanelContainer = %DownloadProgressCard
@onready var error_action_section: VBoxContainer = %ErrorActionSection
@onready var send_logs_btn: Button = %SendLogsBtn
@onready var copy_diag_btn: Button = %CopyDiagBtn
@onready var error_status_feedback: Label = %ErrorStatusFeedback

var active_game_name: String = ""
var current_browse_target: String = "" # "game" or "emulator"

func _ready() -> void:
	launch_close_btn.pressed.connect(close)
	launch_cancel_btn.pressed.connect(close)
	launch_confirm_btn.pressed.connect(_on_confirm_pressed)
	launch_download_btn.pressed.connect(func(): download_auto_pressed.emit())
	launch_path_browse_btn.pressed.connect(func(): _open_file_browse("game"))
	launch_emulator_path_browse_btn.pressed.connect(func(): _open_file_browse("emulator"))
	launch_file_dialog.file_selected.connect(_on_file_selected)
	launch_instructions.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.pressed.connect(func(): steam_btn_pressed.emit())
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.pressed.connect(func(): recheck_btn_pressed.emit())
	if is_instance_valid(send_logs_btn):
		send_logs_btn.pressed.connect(_on_send_logs_pressed)
	if is_instance_valid(copy_diag_btn):
		copy_diag_btn.pressed.connect(_on_copy_diag_pressed)

func open() -> void:
	visible = true

func close() -> void:
	cancellation_requested.emit()
	visible = false
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = false
		download_progress_card.reset()
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	if is_instance_valid(launch_instructions):
		launch_instructions.visible = true
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.visible = false
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.visible = false
	if is_instance_valid(error_action_section):
		error_action_section.visible = false
	if is_instance_valid(error_status_feedback):
		error_status_feedback.visible = false
	closed.emit()

# =====================================================================
#                      PUBLIC PRESENTATION METHODS
# =====================================================================

func present_game_setup(game_name: String, preset: Dictionary, launcher: RefCounted, instructions_override: String = "", total_games_count: int = 1, player_name: String = "") -> void:
	active_game_name = game_name
	
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = false
	if is_instance_valid(error_action_section):
		error_action_section.visible = false
	if is_instance_valid(error_status_feedback):
		error_status_feedback.visible = false
		
	game_selection_section.visible = false
	path_section.visible = true
	launch_confirm_btn.visible = true
	launch_confirm_btn.text = "Confirm & Launch"
	
	var support_tier_level: int = preset.get("support_tier", 2)
	launch_title.text = "Setup: " + game_name + " [Tier " + str(support_tier_level) + "]"
	
	var launch_mode: String = preset.get("launch_mode", "")
	var required_rom: String = preset.get("required_rom", "")
	var is_rom_game: bool = (required_rom != "" or launch_mode == "patch_rom" or preset.get("is_rom", false))
	
	var default_instructions: String = preset.get("install_instructions", "")
	if default_instructions == "":
		if is_rom_game:
			default_instructions = "Select your clean base ROM file (" + required_rom + ") to configure launch. Wayfinder will handle Archipelago tools and emulator configuration automatically."
		else:
			default_instructions = "Select your installed game executable to configure launch."
	
	var games_count: int = maxi(total_games_count, 1)
	var p_name: String = player_name if player_name != "" else NetworkManager.player_name
	var custom_tag_instr: String = preset.get("short_tag", "")
	var slot_name_str: String = YamlBuilder.get_slot_name(p_name, game_name, games_count, custom_tag_instr)
	var slot_prefix: String = "[color=#6ee7b7]• Multiworld Slot:[/color] [b]" + slot_name_str + "[/b]\n\n"
	
	var stored_path: String = launcher.get_saved_path(game_name, preset) if launcher else ""
	if is_rom_game and required_rom != "" and stored_path.to_lower().ends_with(".exe"):
		stored_path = ""
		
	if is_rom_game and required_rom != "":
		var rom_label: String = required_rom
		path_label.text = "Base ROM File (" + rom_label + "):"
		launch_path_input.placeholder_text = "Select path to " + rom_label + "..."
		if stored_path == "" and launcher:
			stored_path = launcher.find_existing_base_rom(required_rom)
			if stored_path != "":
				launcher.paths_config[game_name] = stored_path
				launcher.save_paths_config()
	else:
		path_label.text = "Executable Path (" + preset.get("default_executable", "game.exe") + "):"
		launch_path_input.placeholder_text = "Select path to game executable..."
		if stored_path == "" and launcher:
			var auto_detected: String = launcher.find_game_executable(preset.get("default_executable", ""), preset.get("common_folders", []))
			if auto_detected != "":
				stored_path = auto_detected
				launcher.paths_config[game_name] = stored_path
				launcher.save_paths_config()
				
	launch_path_input.text = stored_path
	
	# Check if download catalog has an entry (ROM or PC game)
	var rom_download_entry: Dictionary = {}
	if launcher:
		var dl_identifier: String = required_rom if required_rom != "" else game_name
		rom_download_entry = launcher.get_rom_download_entry(dl_identifier)
		if rom_download_entry.is_empty():
			rom_download_entry = launcher.get_rom_download_entry(game_name)
			
	if not rom_download_entry.is_empty():
		launch_download_btn.visible = true
		launch_download_btn.disabled = false
		var dl_label: String = "Base ROM" if is_rom_game else "Game"
		launch_download_btn.text = "📥 Download " + dl_label + " Automatically"
		default_instructions = "Setup required for " + game_name + ".\n\nOption 1: Click Download " + dl_label + " Automatically below.\nOption 2: Browse to locate your existing " + ("base ROM file." if is_rom_game else "game executable.")
	else:
		launch_download_btn.visible = false
		if is_rom_game:
			default_instructions = "Please Browse to locate your existing clean base ROM file (" + (required_rom if required_rom != "" else "ROM") + ")."
		else:
			default_instructions = "Please Browse to locate your existing game executable."
		
	if launch_mode == "patch_rom":
		emulator_path_section.visible = true
		var emulator_preset: String = preset.get("emulator", "snes9x")
		emulator_path_label.text = "Emulator (" + emulator_preset.to_upper() + "):"
		var stored_emu_path: String = launcher.paths_config.get(emulator_preset, "") if launcher else ""
		if stored_emu_path == "" and launcher:
			var default_emu_exe: String = emulator_preset + ".exe"
			var auto_emu: String = launcher.find_game_executable(default_emu_exe, [emulator_preset, "emulators"])
			if auto_emu != "":
				stored_emu_path = auto_emu
				launcher.paths_config[emulator_preset] = stored_emu_path
				launcher.save_paths_config()
		launch_emulator_path_input.text = stored_emu_path
	else:
		emulator_path_section.visible = false
		
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.visible = false
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.visible = false

	if preset.has("required_steam_beta"):
		var steam_id: String = str(preset.get("steam_appid", "")).strip_edges()
		var beta_cfg: Dictionary = preset.get("required_steam_beta", {})
		if steam_id != "" and not beta_cfg.is_empty():
			var steam_res: Dictionary = LauncherUtils.check_steam_beta_status(stored_path, steam_id, beta_cfg, game_name)
			if steam_res.get("needs_downgrade", false):
				if is_instance_valid(launch_steam_btn):
					launch_steam_btn.visible = true
					launch_steam_btn.text = "🎮 Open Steam Game Properties (Betas Tab)"
				if is_instance_valid(launch_recheck_btn):
					launch_recheck_btn.visible = true
					launch_recheck_btn.text = "🔄 Re-check Steam Beta Status"
				default_instructions = steam_res.get("guidance_text", "")
				launch_confirm_btn.text = "Select Steam Beta First"
			else:
				if preset.has("mod_activation"):
					var act_cfg: Dictionary = preset.get("mod_activation", {})
					var act_info: Dictionary = LauncherUtils.check_mod_activation_status(stored_path, act_cfg)
					if act_info.get("state", "") == "disabled_in_lumafly":
						default_instructions = "[color=#34d399]✔ Steam Beta branch verified![/color]\n[color=#38bdf8]• Dormant modded files detected[/color]\nWayfinder will automatically activate your mod files upon launch."
				launch_confirm_btn.text = "Confirm & Launch"

	launch_instructions.text = slot_prefix + (instructions_override if instructions_override != "" else default_instructions)
	open()

func present_multi_game_selector(games_list: Array) -> void:
	launch_title.text = "Select Game to Launch"
	launch_instructions.text = "Select game to launch:"
	path_section.visible = false
	emulator_path_section.visible = false
	launch_confirm_btn.visible = false
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = false
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.visible = false
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.visible = false
	
	for child in game_selection_buttons.get_children():
		child.queue_free()
	for game_name in games_list:
		var selection_btn: Button = Button.new()
		selection_btn.text = game_name
		selection_btn.custom_minimum_size = Vector2(180, 40)
		selection_btn.pressed.connect(func():
			game_selected.emit(game_name)
		)
		game_selection_buttons.add_child(selection_btn)
		
	game_selection_section.visible = true
	open()

func present_game_selection(games_list: Array) -> void:
	present_multi_game_selector(games_list)

func present_file_prompt(title_text: String, instructions_text: String, current_path: String = "", _filters: PackedStringArray = PackedStringArray()) -> void:
	launch_title.text = title_text
	launch_instructions.text = instructions_text
	path_section.visible = true
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = true
	launch_confirm_btn.text = "Confirm Selection"
	launch_download_btn.visible = false
	launch_path_input.text = current_path
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = false
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.visible = false
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.visible = false
	open()

func present_tool_installation(tool_name: String) -> void:
	launch_title.text = "Installing " + tool_name
	launch_instructions.text = "Wayfinder is automatically downloading and configuring " + tool_name + "..."
	path_section.visible = false
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = false
	launch_download_btn.visible = false
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.visible = false
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.visible = false
	show_download_card("Installing " + tool_name)
	open()

func present_task_status(title_text: String, instructions_text: String, task_card_title: String = "") -> void:
	launch_title.text = title_text
	launch_instructions.text = instructions_text
	path_section.visible = false
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = false
	launch_download_btn.visible = false
	launch_cancel_btn.visible = true
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.visible = false
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.visible = false
	if task_card_title != "":
		show_download_card(task_card_title)
	open()

func present_task_failed(title_text: String, error_msg: String) -> void:
	launch_title.text = title_text
	launch_instructions.text = "[color=#f87171]" + error_msg + "[/color]"
	path_section.visible = false
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = false
	launch_download_btn.visible = false
	launch_cancel_btn.visible = true
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = false
	if is_instance_valid(launch_instructions):
		launch_instructions.visible = true
	open()

func present_launch_failure(game_name: String, error_msg: String) -> void:
	launch_title.text = "Launch Failed: " + game_name
	launch_instructions.text = "[color=#f87171]" + error_msg + "[/color]\n\nPlease check your game files or settings."
	path_section.visible = false
	emulator_path_section.visible = false
	launch_confirm_btn.visible = false
	launch_download_btn.visible = false
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false
	if is_instance_valid(launch_steam_btn):
		launch_steam_btn.visible = false
	if is_instance_valid(launch_recheck_btn):
		launch_recheck_btn.visible = false
	show_error_actions(error_msg)
	open()

func set_download_button_disabled(p_disabled: bool) -> void:
	if is_instance_valid(launch_download_btn):
		launch_download_btn.disabled = p_disabled

func set_path_input_text(path_text: String) -> void:
	if is_instance_valid(launch_path_input):
		launch_path_input.text = path_text

func set_instructions_text(text: String) -> void:
	if is_instance_valid(launch_instructions):
		launch_instructions.text = text

func get_path_input_text() -> String:
	return launch_path_input.text.strip_edges() if is_instance_valid(launch_path_input) else ""

func get_emulator_path_input_text() -> String:
	return launch_emulator_path_input.text.strip_edges() if is_instance_valid(launch_emulator_path_input) else ""

# =====================================================================
#                      INTERNAL MODAL LOGIC
# =====================================================================

func show_error_actions(_error_text: String) -> void:
	if is_instance_valid(error_action_section):
		error_action_section.visible = true
	if is_instance_valid(error_status_feedback):
		error_status_feedback.visible = false
	if is_instance_valid(send_logs_btn):
		send_logs_btn.disabled = false
		send_logs_btn.text = "📤 Send Error Logs to Host"

func _on_send_logs_pressed() -> void:
	if is_instance_valid(send_logs_btn):
		send_logs_btn.disabled = true
		send_logs_btn.text = "Sending..."
	var s_url: String = NetworkManager.get_http_url()
	var err_summary: String = launch_instructions.text
	Updater.send_logs_to_server(self, s_url, err_summary, func(ok: bool, msg: String):
		if is_instance_valid(error_status_feedback):
			error_status_feedback.visible = true
			error_status_feedback.text = "✅ Logs successfully transmitted to host!" if ok else ("❌ " + msg)
			error_status_feedback.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5) if ok else Color(1.0, 0.3, 0.3))
		if is_instance_valid(send_logs_btn):
			send_logs_btn.text = "📤 Sent!" if ok else "📤 Retry Send Logs"
			send_logs_btn.disabled = ok
	)

func _on_copy_diag_pressed() -> void:
	var report: String = Updater.generate_diagnostic_report({
		"active_game": active_game_name,
		"last_error": launch_instructions.text
	})
	DisplayServer.clipboard_set(report)
	if is_instance_valid(error_status_feedback):
		error_status_feedback.visible = true
		error_status_feedback.text = "📋 Diagnostic report copied to clipboard!"
		error_status_feedback.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))

func show_download_card(task_title: String) -> void:
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = true
		download_progress_card.set_task(task_title)
	if is_instance_valid(launch_instructions):
		launch_instructions.visible = false
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false

func update_download_progress(task_or_pct, pct_or_dl_bytes = 0.0, dl_bytes_or_total = 0, total_bytes_or_speed = 0, speed = 0.0) -> void:
	var task: String = ""
	var pct: float = 0.0
	var dl_bytes: int = 0
	var total_bytes: int = 0
	var speed_val: float = 0.0

	if task_or_pct is String:
		task = str(task_or_pct)
		pct = float(pct_or_dl_bytes)
		dl_bytes = int(dl_bytes_or_total)
		total_bytes = int(total_bytes_or_speed)
		speed_val = float(speed)
	else:
		pct = float(task_or_pct)
		dl_bytes = int(pct_or_dl_bytes)
		total_bytes = int(dl_bytes_or_total)
		speed_val = float(total_bytes_or_speed)

	open()
	if is_instance_valid(path_section):
		path_section.visible = false
	if is_instance_valid(emulator_path_section):
		emulator_path_section.visible = false
	if is_instance_valid(game_selection_section):
		game_selection_section.visible = false
	if is_instance_valid(launch_confirm_btn):
		launch_confirm_btn.visible = false
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = true
		if task != "":
			var display_task = task
			if not display_task.begins_with("Installing") and not display_task.begins_with("Downloading") and not display_task.begins_with("Decrypting"):
				display_task = "Downloading " + display_task
			download_progress_card.set_task(display_task)
		download_progress_card.update_progress(pct, dl_bytes, total_bytes, speed_val)
	if is_instance_valid(launch_instructions):
		launch_instructions.visible = false
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false

func on_download_progress_updated(task: String, pct: float, dl_bytes: int, total_bytes: int, speed: float) -> void:
	update_download_progress(task, pct, dl_bytes, total_bytes, speed)

func on_modding_status_updated(msg: String, pct: int) -> void:
	set_modding_status(msg, pct)

func on_overlay_dismiss_requested() -> void:
	close()

func bind_launcher(launcher: RefCounted) -> void:
	if not is_instance_valid(launcher):
		return
	if launcher.has_signal("download_progress_updated") and not launcher.download_progress_updated.is_connected(on_download_progress_updated):
		launcher.download_progress_updated.connect(on_download_progress_updated)
	if launcher.has_signal("modding_status_updated") and not launcher.modding_status_updated.is_connected(on_modding_status_updated):
		launcher.modding_status_updated.connect(on_modding_status_updated)
	if launcher.has_signal("overlay_dismiss_requested") and not launcher.overlay_dismiss_requested.is_connected(on_overlay_dismiss_requested):
		launcher.overlay_dismiss_requested.connect(on_overlay_dismiss_requested)

func set_modding_status(message: String, pct: int) -> void:
	visible = true
	path_section.visible = false
	emulator_path_section.visible = false
	game_selection_section.visible = false
	launch_confirm_btn.visible = false
	
	launch_title.text = "Modding & Launching Game"
	
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = true
		download_progress_card.set_task("Modding & Launching Game")
		download_progress_card.set_message(message)
		download_progress_card.update_progress(pct)
		if is_instance_valid(launch_instructions):
			launch_instructions.visible = false
		if is_instance_valid(launch_progress_bar):
			launch_progress_bar.visible = false
	else:
		if is_instance_valid(launch_instructions):
			launch_instructions.visible = true
			launch_instructions.text = message
		if is_instance_valid(launch_progress_bar):
			launch_progress_bar.visible = true
			launch_progress_bar.value = pct

func _open_file_browse(target: String) -> void:
	current_browse_target = target
	launch_file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	if current_browse_target == "game":
		launch_path_input.text = path
	elif current_browse_target == "emulator":
		launch_emulator_path_input.text = path

func _on_confirm_pressed() -> void:
	var g_path = launch_path_input.text.strip_edges()
	var emu_path = launch_emulator_path_input.text.strip_edges()
	confirmed.emit(active_game_name, g_path, emu_path)
