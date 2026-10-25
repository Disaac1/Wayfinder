extends PanelContainer

@onready var task_title_label: Label = %TaskTitleLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_detail_label: Label = %StatusDetailLabel
@onready var speed_badge: Label = %SpeedBadge
@onready var eta_badge: Label = %EtaBadge

const BYTES_PER_MB: float = 1024.0 * 1024.0

func _ready() -> void:
	reset()

func reset() -> void:
	if is_instance_valid(task_title_label):
		task_title_label.text = "Preparing..."
	if is_instance_valid(progress_bar):
		progress_bar.value = 0.0
	if is_instance_valid(status_detail_label):
		status_detail_label.text = ""
	if is_instance_valid(speed_badge):
		speed_badge.text = ""
		speed_badge.visible = false
	if is_instance_valid(eta_badge):
		eta_badge.text = ""
		eta_badge.visible = false

func set_task(title: String) -> void:
	if is_instance_valid(task_title_label):
		task_title_label.text = title

func set_message(msg: String) -> void:
	if is_instance_valid(status_detail_label):
		status_detail_label.text = msg

func update_progress(pct: float, downloaded_bytes: int = 0, total_bytes: int = 0, speed_bps: float = 0.0) -> void:
	if is_instance_valid(progress_bar):
		progress_bar.value = clamp(pct, 0.0, 100.0)

	if speed_bps > 0.0 and is_instance_valid(speed_badge):
		var speed_mb: float = speed_bps / BYTES_PER_MB
		speed_badge.text = "⚡ " + String.num(speed_mb, 1) + " MB/s"
		speed_badge.visible = true
	elif is_instance_valid(speed_badge):
		speed_badge.visible = false

	if total_bytes > 0:
		var dl_mb: float = float(downloaded_bytes) / BYTES_PER_MB
		var total_mb: float = float(total_bytes) / BYTES_PER_MB
		if is_instance_valid(status_detail_label):
			status_detail_label.text = String.num(dl_mb, 1) + " MB / " + String.num(total_mb, 1) + " MB (" + str(int(pct)) + "%)"

		if speed_bps > 50000.0 and total_bytes > downloaded_bytes and is_instance_valid(eta_badge):
			var remaining_bytes = total_bytes - downloaded_bytes
			var seconds_left = int(float(remaining_bytes) / speed_bps)
			if seconds_left < 60:
				eta_badge.text = "⏱ ~" + str(seconds_left) + "s left"
			else:
				var mins = int(seconds_left / 60)
				var secs = seconds_left % 60
				eta_badge.text = "⏱ ~" + str(mins) + "m " + str(secs) + "s"
			eta_badge.visible = true
		elif is_instance_valid(eta_badge):
			eta_badge.visible = false
	elif downloaded_bytes > 0:
		var dl_mb: float = float(downloaded_bytes) / BYTES_PER_MB
		if is_instance_valid(status_detail_label):
			status_detail_label.text = String.num(dl_mb, 1) + " MB (" + str(int(pct)) + "%)"
		if is_instance_valid(eta_badge):
			eta_badge.visible = false
