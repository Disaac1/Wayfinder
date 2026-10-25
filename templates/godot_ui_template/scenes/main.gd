extends Control

# Reference UI components
@onready var nav_dashboard_btn: Button = %NavDashboardBtn
@onready var nav_inputs_btn: Button = %NavInputsBtn
@onready var nav_data_btn: Button = %NavDataBtn
@onready var nav_logs_btn: Button = %NavLogsBtn

@onready var tab_container: TabContainer = %ContentTabs

# Inputs tab references
@onready var sample_input: LineEdit = %SampleInput
@onready var sample_slider: HSlider = %SampleSlider
@onready var slider_val_label: Label = %SliderValueLabel
@onready var sample_check: CheckBox = %SampleCheck
@onready var sample_option: OptionButton = %SampleOption

# Data tab references
@onready var item_tree: Tree = %ItemTree
@onready var add_item_btn: Button = %AddItemBtn
@onready var delete_item_btn: Button = %DeleteItemBtn
@onready var item_name_input: LineEdit = %ItemNameInput

# Logs tab references
@onready var log_console: RichTextLabel = %LogConsole
@onready var clear_logs_btn: Button = %ClearLogsBtn

const ModalDialogScript = preload("res://scenes/components/modal_dialog.gd")
const ToastNotificationScript = preload("res://scenes/components/toast_notification.gd")

# Global components
@onready var modal_dialog = %ModalDialog
@onready var toast = %ToastNotification
@onready var fps_label: Label = %FPSLabel
@onready var status_label: Label = %StatusLabel

var _item_counter: int = 1

func _ready() -> void:
	_setup_navigation()
	_setup_inputs_page()
	_setup_data_tree()
	_setup_logs_page()
	_setup_status_bar()

	log_message("[color=green]App initialized successfully.[/color] Running in pure UI mode (Low Processor Mode active).")
	toast.show_toast("Welcome to the Pure UI Template!", 3.5)

func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d (Low Power Mode)" % Engine.get_frames_drawn()

# --- Navigation ---
func _setup_navigation() -> void:
	nav_dashboard_btn.pressed.connect(func(): _switch_tab(0, nav_dashboard_btn))
	nav_inputs_btn.pressed.connect(func(): _switch_tab(1, nav_inputs_btn))
	nav_data_btn.pressed.connect(func(): _switch_tab(2, nav_data_btn))
	nav_logs_btn.pressed.connect(func(): _switch_tab(3, nav_logs_btn))
	_switch_tab(0, nav_dashboard_btn)

func _switch_tab(index: int, active_button: Button) -> void:
	tab_container.current_tab = index
	for btn in [nav_dashboard_btn, nav_inputs_btn, nav_data_btn, nav_logs_btn]:
		btn.button_pressed = (btn == active_button)

# --- Inputs & Form ---
func _setup_inputs_page() -> void:
	sample_slider.value_changed.connect(func(v): slider_val_label.text = str(int(v)) + "%")
	sample_option.add_item("Option A: Standard")
	sample_option.add_item("Option B: Optimized")
	sample_option.add_item("Option C: Headless")

	%ShowToastBtn.pressed.connect(func():
		toast.show_toast("Action executed from inputs panel!", 2.5)
		log_message("User pressed 'Show Toast'")
	)

	%ShowModalBtn.pressed.connect(func():
		modal_dialog.open(
			"Confirm Reset",
			"Are you sure you want to reset all input values to defaults?",
			"Reset",
			"Cancel",
			_reset_inputs
		)
	)

func _reset_inputs() -> void:
	sample_input.text = ""
	sample_slider.value = 50
	sample_check.button_pressed = false
	sample_option.selected = 0
	toast.show_toast("Inputs reset to defaults.", 2.5)
	log_message("[color=yellow]Inputs reset to default values.[/color]")

# --- Data / Tree ---
func _setup_data_tree() -> void:
	item_tree.columns = 3
	item_tree.set_column_title(0, "ID")
	item_tree.set_column_title(1, "Name")
	item_tree.set_column_title(2, "Status")
	item_tree.column_titles_visible = true

	var root = item_tree.create_item()
	_add_tree_row(root, "001", "Core Engine", "Active")
	_add_tree_row(root, "002", "Control Nodes", "Loaded")
	_add_tree_row(root, "003", "Low Power Thread", "Running")

	add_item_btn.pressed.connect(_on_add_item)
	delete_item_btn.pressed.connect(_on_delete_selected_item)

func _add_tree_row(root: TreeItem, id_str: String, name_str: String, status_str: String) -> TreeItem:
	var item = item_tree.create_item(root)
	item.set_text(0, id_str)
	item.set_text(1, name_str)
	item.set_text(2, status_str)
	return item

func _on_add_item() -> void:
	var name_text = item_name_input.text.strip_edges()
	if name_text.is_empty():
		name_text = "Item %03d" % _item_counter

	var root = item_tree.get_root()
	_add_tree_row(root, "%03d" % (_item_counter + 3), name_text, "Ready")
	_item_counter += 1
	item_name_input.text = ""
	toast.show_toast("Added '%s' to table" % name_text, 2.0)
	log_message("Added tree item: " + name_text)

func _on_delete_selected_item() -> void:
	var selected = item_tree.get_selected()
	if selected and selected != item_tree.get_root():
		var item_name = selected.get_text(1)
		selected.free()
		toast.show_toast("Deleted '%s'" % item_name, 2.0)
		log_message("Deleted tree item: " + item_name)
	else:
		toast.show_toast("No item selected", 2.0, true)

# --- Logging Console ---
func _setup_logs_page() -> void:
	clear_logs_btn.pressed.connect(func():
		log_console.clear()
		log_message("[color=gray]Logs cleared.[/color]")
	)

func log_message(msg: String) -> void:
	var time = Time.get_time_string_from_system()
	log_console.append_text("[color=gray][%s][/color] %s\n" % [time, msg])

# --- Status Bar ---
func _setup_status_bar() -> void:
	status_label.text = "Template Ready | 2D/3D stripped | UI-only profile loaded"
