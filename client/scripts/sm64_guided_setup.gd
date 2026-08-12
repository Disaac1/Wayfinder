class_name SM64GuidedSetup
extends BaseGuidedSetup

const BaseGuidedSetup = preload("res://scripts/base_guided_setup.gd")

const SM64_DEFAULT_CONFIG = {
	"completion_type": 0,
	"amount_of_stars": 120,
	"stars_to_finish": 58,
	"first_bowser_star_door_cost": 7,
	"basement_star_door_cost": 25,
	"second_floor_star_door_cost": 42,
	"mips1_cost": 12,
	"mips2_cost": 42,
	
	"area_rando": 0,
	"enable_locked_paintings": false,
	"progressive_keys": true,
	
	"enable_coin_stars": 0,
	"buddy_checks": false,
	"exclamation_boxes": false,
	
	"enable_move_rando": false,
	"strict_cap_requirements": true,
	"strict_cannon_requirements": true,
	"strict_move_requirements": true,
	
	"death_link": false
}

func _get_game_title() -> String:
	return "Super Mario 64"

func _get_default_config() -> Dictionary:
	return SM64_DEFAULT_CONFIG

func _get_steps_data() -> Array:
	return [
		{"num": 1, "title": "1. Goal & Stars"},
		{"num": 2, "title": "2. World & Entrances"},
		{"num": 3, "title": "3. Location Pools"},
		{"num": 4, "title": "4. Mario Moves"},
		{"num": 5, "title": "5. QoL & Extras"}
	]

func _get_required_schema_keys() -> Array:
	return [
		"completion_type", "amount_of_stars", "stars_to_finish",
		"area_rando", "progressive_keys", "enable_move_rando"
	]

static func validate_schema(schema: Dictionary) -> Dictionary:
	var req_keys = [
		"completion_type", "amount_of_stars", "stars_to_finish",
		"area_rando", "progressive_keys", "enable_move_rando"
	]
	return validate_schema_for_keys(schema, req_keys)

func _build_step_content(step_num: int, container: VBoxContainer) -> void:
	match step_num:
		1: _build_step_1_goal(container)
		2: _build_step_2_world(container)
		3: _build_step_3_locations(container)
		4: _build_step_4_moves(container)
		5: _build_step_5_qol(container)

# --- STEP 1: GOAL & STARS ---
func _build_step_1_goal(container: VBoxContainer) -> void:
	add_step_description(container, "Step 1: Choose Victory Goal, Star Pool & Star Door Costs")
	
	var goals_data = [
		{"id": 0, "title": "👑 Beat Final Bowser", "desc": "Defeat Bowser in the Sky (Bowser 3) to clear the game."},
		{"id": 1, "title": "🏰 Defeat All Bowser Stages", "desc": "Defeat Bowser in Dark World, Fire Sea & Sky to win."}
	]
	
	var current_g = current_config.get("completion_type", 0)
	add_card_grid(container, goals_data, 2, current_g, func(item_id, _data):
		set_option_value("completion_type", int(item_id))
	)
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	add_slider_option(container, "Total Power Stars in Pool:", "amount_of_stars", 35, 120, 5, " Stars")
	add_slider_option(container, "Endless Stairs Requirement:", "stars_to_finish", 0, 90, 5, "% of Stars")
	add_slider_option(container, "First Star Door (Bowser 1):", "first_bowser_star_door_cost", 0, 40, 1, "%")
	add_slider_option(container, "Basement Star Door (Bowser 2):", "basement_star_door_cost", 0, 50, 1, "%")
	add_slider_option(container, "Second Floor Star Door:", "second_floor_star_door_cost", 0, 70, 1, "%")

# --- STEP 2: WORLD & ENTRANCES ---
func _build_step_2_world(container: VBoxContainer) -> void:
	add_step_description(container, "Step 2: Entrance Randomizer & Castle Access")
	
	var rando_presets = [
		{"id": 0, "name": "🚪 Vanilla Entrances", "desc": "Paintings & levels lead to their original destinations."},
		{"id": 1, "name": "🌀 Course Shuffle", "desc": "Randomize course painting destinations (Secrets stay vanilla)."},
		{"id": 3, "name": "🌌 Full Entrance Rando", "desc": "Randomize all course paintings & secret level entrances!"}
	]
	
	var current_area = current_config.get("area_rando", 0)
	add_card_grid(container, rando_presets, 3, current_area, func(item_id, _data):
		set_option_value("area_rando", int(item_id))
	)
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	add_toggle_option(container, "🖼️ Enable Locked Paintings (Requires finding painting keys to enter)", "enable_locked_paintings")
	add_toggle_option(container, "🔑 Progressive Keys (1st Key = Basement, 2nd Key = Upper Floor)", "progressive_keys")

# --- STEP 3: LOCATION POOLS ---
func _build_step_3_locations(container: VBoxContainer) -> void:
	add_step_description(container, "Step 3: Extra Location Checks & Coin Stars")
	
	var coin_choices = [
		{"id": 0, "title": "Off (100 Coin Stars removed from pool)"},
		{"id": 1, "title": "On (100 Coin Stars in pool & randomized)"},
		{"id": 2, "title": "Vanilla (100 Coin Stars in pool, non-randomized)"}
	]
	add_dropdown_option(container, "100 Coin Stars Pool:", "enable_coin_stars", coin_choices)
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	add_toggle_option(container, "💣 Bob-omb Buddy Checks (Buddies hold items & unlock cannons)", "buddy_checks")
	add_toggle_option(container, "🎁 Randomize 1Up !-Blocks (Adds 29 1Up box locations)", "exclamation_boxes")

# --- STEP 4: MARIO MOVES ---
func _build_step_4_moves(container: VBoxContainer) -> void:
	add_step_description(container, "Step 4: Mario Move Randomizer & Logic Requirements")
	
	add_toggle_option(container, "🏃 Enable Move Randomizer (Mario unlocks Long Jump, Wall Kick, Triple Jump as items!)", "enable_move_rando")
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	add_toggle_option(container, "🧢 Strict Cap Requirements (Stars expecting Metal/Wing/Vanish cap logically require caps)", "strict_cap_requirements")
	add_toggle_option(container, "💣 Strict Cannon Requirements", "strict_cannon_requirements")
	add_toggle_option(container, "🤸 Strict Move Requirements (If move rando on, stars expecting long jump require it in logic)", "strict_move_requirements")

# --- STEP 5: QOL & EXTRAS ---
func _build_step_5_qol(container: VBoxContainer) -> void:
	add_step_description(container, "Step 5: Quality of Life & Multiplayer Extras")
	
	add_toggle_option(container, "💀 DeathLink (Mario dying triggers a death for your multiworld team)", "death_link")
