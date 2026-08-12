class_name GuidedSetupRegistry
extends RefCounted

# Central registry mapping game names to their Guided Setup GDScript resource paths
static var REGISTRY: Dictionary = {
	"Pokemon Emerald": "res://scripts/pokemon_emerald_guided_setup.gd",
	"Super Mario 64": "res://scripts/sm64_guided_setup.gd"
}

# Checks if a guided setup wizard is registered for the specified game
static func has_guided_setup(game_name: String) -> bool:
	return REGISTRY.has(game_name)

# Validates backend schema and instantiates the wizard if valid
static func validate_and_create(game_name: String, schema: Dictionary) -> Dictionary:
	if not has_guided_setup(game_name):
		return {"valid": false, "reason": "No guided setup registered for " + game_name, "wizard": null}
		
	var script_path = REGISTRY[game_name]
	var wizard_script = load(script_path)
	if not wizard_script:
		return {"valid": false, "reason": "Failed to load script at " + script_path, "wizard": null}
		
	# Check if wizard class provides static validate_schema
	if wizard_script.has_method("validate_schema"):
		var val_res = wizard_script.validate_schema(schema)
		if not val_res.get("valid", false):
			return {"valid": false, "reason": val_res.get("reason", "Incompatible schema"), "wizard": null}
			
	var wizard_instance = wizard_script.new()
	return {"valid": true, "reason": "", "wizard": wizard_instance}

# Register a new game wizard dynamically at runtime
static func register_game_wizard(game_name: String, script_path: String) -> void:
	REGISTRY[game_name] = script_path
