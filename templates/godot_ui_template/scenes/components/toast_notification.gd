extends Control
class_name ToastNotification

@onready var panel: PanelContainer = $PanelContainer
@onready var message_label: Label = $PanelContainer/Margin/HBox/MessageLabel
@onready var timer: Timer = $Timer

var _tween: Tween

func _ready() -> void:
	visible = false
	modulate.a = 0.0
	timer.timeout.connect(_on_timeout)

func show_toast(text: String, duration: float = 3.0, is_error: bool = false) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	message_label.text = text
	if is_error:
		panel.self_modulate = Color(0.9, 0.3, 0.3, 1.0)
	else:
		panel.self_modulate = Color(0.2, 0.8, 0.4, 1.0)

	visible = true
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "position:y", 0.0, 0.2).from(10.0)

	timer.start(duration)

func _on_timeout() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): visible = false)
