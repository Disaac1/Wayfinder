extends Control

@export var color: Color = Color(0.67, 0.44, 0.98) # purple to match RoomLabel
@export var thickness: float = 3.0
@export var speed: float = 6.0

func _ready() -> void:
	# Set anchor to center
	custom_minimum_size = Vector2(32, 32)
	size_flags_horizontal = SIZE_SHRINK_CENTER
	size_flags_vertical = SIZE_SHRINK_CENTER
	# Pivot in center for rotation
	pivot_offset = custom_minimum_size / 2.0
	_update_process_state()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_process_state()

func _update_process_state() -> void:
	var active = is_visible_in_tree() if is_inside_tree() else visible
	set_process(active)
	if active:
		queue_redraw()

func _process(delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()
		rotation += speed * delta

func _draw() -> void:
	var radius = min(size.x, size.y) / 2.0 - thickness
	var center = size / 2.0
	# Draw a 270-degree arc for a modern spinner look
	draw_arc(center, radius, 0, PI * 1.5, 32, color, thickness, true)
