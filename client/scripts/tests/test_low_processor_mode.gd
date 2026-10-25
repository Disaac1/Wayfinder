extends SceneTree

func _init() -> void:
	print("--- Running Low Processor Mode Tests ---")
	
	# 1. Verify ProjectSettings
	var lpm_setting = ProjectSettings.get_setting("application/run/low_processor_mode")
	var sleep_setting = ProjectSettings.get_setting("application/run/low_processor_mode_sleep_usec")
	
	print("Project setting low_processor_mode: ", lpm_setting)
	print("Project setting low_processor_mode_sleep_usec: ", sleep_setting)
	assert(lpm_setting == true, "application/run/low_processor_mode should be true")
	assert(sleep_setting == 6900, "application/run/low_processor_mode_sleep_usec should be 6900")
	
	# 2. Verify OS low processor usage mode
	print("OS.low_processor_usage_mode: ", OS.low_processor_usage_mode)
	print("OS.low_processor_usage_mode_sleep_usec: ", OS.low_processor_usage_mode_sleep_usec)
	assert(OS.low_processor_usage_mode == true, "OS.low_processor_usage_mode should be true")
	assert(OS.low_processor_usage_mode_sleep_usec == 6900, "OS.low_processor_usage_mode_sleep_usec should be 6900")
	
	# 3. Test LoadingSpinner process loop throttling
	var spinner_script = load("res://scripts/ui/components/loading_spinner.gd")
	assert(spinner_script != null, "Failed to load loading_spinner.gd")
	var spinner = spinner_script.new()
	root.add_child(spinner)
	
	# Initially visible is true by default for Control, but let's test hiding it
	spinner.visible = false
	spinner.notification(Control.NOTIFICATION_VISIBILITY_CHANGED)
	assert(spinner.is_processing() == false, "LoadingSpinner should not be processing when invisible")
	
	# Now make it visible
	spinner.visible = true
	spinner.notification(Control.NOTIFICATION_VISIBILITY_CHANGED)
	assert(spinner.is_processing() == true, "LoadingSpinner should be processing when visible")
	
	# Cleanup
	spinner.queue_free()
	
	print("All Low Processor Mode checks passed successfully!")
	quit(0)
