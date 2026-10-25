extends Control
class_name ModalDialog

signal confirmed
signal cancelled

@onready var title_label: Label = $CenterContainer/PanelContainer/Margin/VBox/TitleLabel
@onready var message_label: Label = $CenterContainer/PanelContainer/Margin/VBox/MessageLabel
@onready var cancel_button: Button = $CenterContainer/PanelContainer/Margin/VBox/ButtonHBox/CancelButton
@onready var confirm_button: Button = $CenterContainer/PanelContainer/Margin/VBox/ButtonHBox/ConfirmButton

var _on_confirm_callback: Callable

func _ready() -> void:
	visible = false
	cancel_button.pressed.connect(_on_cancel)
	confirm_button.pressed.connect(_on_confirm)

func open(title: String, message: String, confirm_text: String = "Confirm", cancel_text: String = "Cancel", on_confirm: Callable = Callable()) -> void:
	title_label.text = title
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	_on_confirm_callback = on_confirm

	visible = true
	confirm_button.grab_focus()

func _on_confirm() -> void:
	visible = false
	if _on_confirm_callback.is_valid():
		_on_confirm_callback.call()
	confirmed.emit()

func _on_cancel() -> void:
	visible = false
	cancelled.emit()
