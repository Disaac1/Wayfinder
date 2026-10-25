extends Control

@onready var generating_spinner: Control = %GeneratingSpinner
@onready var generating_title: Label = %GeneratingTitle
@onready var generating_status_label: Label = %GeneratingStatusLabel
@onready var log_scroll: ScrollContainer = %LogScroll
@onready var log_container: VBoxContainer = %LogContainer

func _ready() -> void:
	reset()

func reset() -> void:
	if is_instance_valid(generating_title):
		generating_title.text = "Generating Archipelago Multiworld..."
	if is_instance_valid(generating_status_label):
		generating_status_label.text = "Preparing generation pipeline..."
	if is_instance_valid(log_container):
		for child in log_container.get_children():
			child.queue_free()

func open(title: String = "Generating Archipelago Multiworld...") -> void:
	reset()
	if is_instance_valid(generating_title):
		generating_title.text = title
	visible = true

func close() -> void:
	visible = false

func set_status(status_text: String) -> void:
	if is_instance_valid(generating_status_label):
		generating_status_label.text = status_text

func add_log(line: String) -> void:
	if not is_instance_valid(log_container):
		return
	var label = Label.new()
	label.text = line
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_container.add_child(label)
	
	# Auto-scroll to bottom
	if is_instance_valid(log_scroll):
		var v_bar = log_scroll.get_v_scroll_bar()
		if v_bar:
			v_bar.value = v_bar.max_value
