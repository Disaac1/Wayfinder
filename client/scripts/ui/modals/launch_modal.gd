extends Control

signal closed()
signal confirmed(game_name: String, game_path: String, emu_path: String)
signal download_auto_pressed()
signal game_selected(game_name: String)
signal steam_btn_pressed()
signal recheck_btn_pressed()

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

func show_error_actions(error_text: String) -> void:
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
	WayfinderLogger.send_logs_to_server(self, s_url, err_summary, func(ok: bool, msg: String):
		if is_instance_valid(error_status_feedback):
			error_status_feedback.visible = true
			error_status_feedback.text = "✅ Logs successfully transmitted to host!" if ok else ("❌ " + msg)
			error_status_feedback.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5) if ok else Color(1.0, 0.3, 0.3))
		if is_instance_valid(send_logs_btn):
			send_logs_btn.text = "📤 Sent!" if ok else "📤 Retry Send Logs"
			send_logs_btn.disabled = ok
	)

func _on_copy_diag_pressed() -> void:
	var report: String = WayfinderLogger.generate_diagnostic_report({
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

func update_download_progress(pct: float, dl_bytes: int, total_bytes: int, speed: float) -> void:
	if is_instance_valid(download_progress_card):
		download_progress_card.visible = true
		download_progress_card.update_progress(pct, dl_bytes, total_bytes, speed)
	if is_instance_valid(launch_instructions):
		launch_instructions.visible = false
	if is_instance_valid(launch_progress_bar):
		launch_progress_bar.visible = false

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
