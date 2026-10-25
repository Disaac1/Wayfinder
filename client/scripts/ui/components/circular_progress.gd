@tool
class_name CircularProgress
extends Control

@export var value: float = 0.0:
	set(v):
		value = v
		queue_redraw()

@export var max_value: float = 100.0:
	set(v):
		max_value = max(v, 1.0)
		queue_redraw()

@export var track_color: Color = Color(0.18, 0.22, 0.3, 0.7):
	set(c):
		track_color = c
		queue_redraw()

@export var progress_color: Color = Color(0.67, 0.44, 0.98, 1.0):
	set(c):
		progress_color = c
		queue_redraw()

@export var ring_width: float = 2.5:
	set(w):
		ring_width = w
		queue_redraw()

func _draw() -> void:
	var r: float = min(size.x, size.y) * 0.5 - (ring_width * 0.5)
	if r <= 0:
		return
	var center: Vector2 = size * 0.5
	
	# Draw background circle
	draw_arc(center, r, 0, TAU, 32, track_color, ring_width, true)
	
	# Draw progress arc (clockwise starting from top: -PI/2)
	var pct: float = clamp(value / max(max_value, 1.0), 0.0, 1.0)
	if pct > 0.0:
		var end_angle: float = -PI * 0.5 + (pct * TAU)
		draw_arc(center, r, -PI * 0.5, end_angle, 32, progress_color, ring_width, true)
