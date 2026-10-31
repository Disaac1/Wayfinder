extends Control

const Updater = preload("res://scripts/core/updater.gd")

signal manual_download_requested(url: String)
signal update_completed(success: bool, message: String)
signal update_started(update_info: Dictionary)

@onready var message_label: Label = %MessageLabel
@onready var download_button: Button = %DownloadButton
@onready var update_spinner: Control = %UpdateSpinner

var _current_update_info: Dictionary = {}

# Aliases for convenience / backward compatibility
var message: Label:
	get:
		return message_label
var download_btn: Button:
	get:
		return download_button
var spinner: Control:
	get:
		return update_spinner

func _ready() -> void:
	if is_instance_valid(download_button):
		if not download_button.pressed.is_connected(_on_download_button_pressed):
			download_button.pressed.connect(_on_download_button_pressed)

func reset() -> void:
	_current_update_info.clear()
	if is_instance_valid(message_label):
		message_label.text = ""
	if is_instance_valid(download_button):
		download_button.visible = false
		download_button.disabled = false
	if is_instance_valid(update_spinner):
		update_spinner.visible = false
	visible = false

func open() -> void:
	visible = true

func close() -> void:
	visible = false

func set_message(text: String) -> void:
	if is_instance_valid(message_label):
		message_label.text = text

func get_message() -> String:
	return message_label.text if is_instance_valid(message_label) else ""

func start_manual_update(update_info: Dictionary) -> void:
	_current_update_info = update_info
	if is_instance_valid(update_spinner):
		update_spinner.visible = false
	if is_instance_valid(download_button):
		download_button.visible = true
		download_button.text = "Download latest version"
		download_button.disabled = false
	if is_instance_valid(message_label):
		var target_ver: String = str(update_info.get("version", ""))
		message_label.text = "Update required\n\nThis version of Wayfinder must be updated manually.\nInstall v" + target_ver + " to continue."
	open()

func start_forced_update_failure(failure_message: String) -> void:
	_current_update_info.clear()
	if is_instance_valid(update_spinner):
		update_spinner.visible = false
	if is_instance_valid(download_button):
		download_button.visible = false
	if is_instance_valid(message_label):
		message_label.text = "Update required\n" + failure_message + "\nPlease restart Wayfinder and try again."
	open()

func start_forced_update(update_info: Dictionary) -> void:
	_current_update_info = update_info
	Updater.log_message("UPDATER", "Forced update download started: " + str(update_info))
	update_started.emit(update_info)
	if is_instance_valid(download_button):
		download_button.visible = false
	if is_instance_valid(update_spinner):
		update_spinner.visible = true
	if is_instance_valid(message_label):
		message_label.text = "Updating Wayfinder...\nDownloading required update..."
	open()

	Updater.apply_update(self, update_info, Callable(), func(success: bool, error_message: String):
		Updater.log_message("UPDATER", "Forced update download completed: success=" + str(success) + " message=" + error_message)
		if not success:
			if is_instance_valid(update_spinner):
				update_spinner.visible = false
			if is_instance_valid(message_label):
				message_label.text = "Update failed:\n" + error_message
			update_completed.emit(false, error_message)
			return
		
		var tree: SceneTree = get_tree()
		if tree:
			for seconds in range(5, 0, -1):
				if is_instance_valid(message_label):
					message_label.text = "Updating Wayfinder...\nRestarting in " + str(seconds) + "..."
				await tree.create_timer(1.0).timeout
		
		if not Updater.restart_application(self):
			if is_instance_valid(update_spinner):
				update_spinner.visible = false
			if is_instance_valid(message_label):
				message_label.text = "Update staged, but automatic restart failed.\nPlease close and reopen Wayfinder."
			update_completed.emit(true, "Update staged, but automatic restart failed.")
		else:
			update_completed.emit(true, "Restarting...")
	)

func _on_download_button_pressed() -> void:
	var rel_url: String = str(_current_update_info.get("download_url", "/api/client/download-client"))
	var url: String = Updater.get_server_base_url(self) + rel_url
	manual_download_requested.emit(url)
	OS.shell_open(url)

# Aliases matching private names in main_menu for drop-in flexibility
func _start_manual_update(update_info: Dictionary) -> void:
	start_manual_update(update_info)

func _start_forced_update_failure(failure_message: String) -> void:
	start_forced_update_failure(failure_message)

func _start_forced_update(update_info: Dictionary) -> void:
	start_forced_update(update_info)

