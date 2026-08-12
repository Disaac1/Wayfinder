class_name PokemonEmeraldGuidedSetup
extends BaseGuidedSetup

const BaseGuidedSetup = preload("res://scripts/base_guided_setup.gd")

const EMERALD_DEFAULT_CONFIG = {
	"goal": "champion",
	"norman_count": 4,
	"norman_requirement": "badges",
	"elite_four_count": 8,
	"elite_four_requirement": "badges",
	"legendary_hunt_count": 3,
	"legendary_hunt_catch": false,
	
	"badges": "completely_random",
	"hms": "completely_random",
	"key_items": true,
	"bikes": true,
	"event_tickets": false,
	"rods": false,
	"overworld_items": true,
	"hidden_items": false,
	"npc_gifts": false,
	"berry_trees": false,
	"dexsanity": false,
	"trainersanity": false,
	"require_flash": "both",
	"remove_roadblocks": [],
	
	"wild_pokemon": "vanilla",
	"starters": "vanilla",
	"trainer_parties": "vanilla",
	"legendary_encounters": "vanilla",
	"misc_pokemon": "vanilla",
	"types": "vanilla",
	"abilities": "vanilla",
	
	"exp_modifier": 100,
	"min_catch_rate": 3,
	"guaranteed_catch": false,
	"reusable_tms_tutors": true,
	"level_up_moves": "vanilla",
	"tm_tutor_moves": false,
	"move_match_type_bias": 0,
	"match_trainer_levels": "off",
	
	"turbo_a": true,
	"better_shops": true,
	"music": false,
	"fanfares": false,
	"death_link": false,
	"enable_wonder_trading": true
}

func _get_game_title() -> String:
	return "Pokémon Emerald"

func _get_default_config() -> Dictionary:
	return EMERALD_DEFAULT_CONFIG

func _get_steps_data() -> Array:
	return [
		{"num": 1, "title": "1. Goal & Pace"},
		{"num": 2, "title": "2. World & Items"},
		{"num": 3, "title": "3. Pokémon & Trainers"},
		{"num": 4, "title": "4. Battle & Leveling"},
		{"num": 5, "title": "5. QoL & Extras"}
	]

func _get_required_schema_keys() -> Array:
	return [
		"goal", "norman_count", "elite_four_count", "badges", "hms", "key_items",
		"overworld_items", "wild_pokemon", "starters", "trainer_parties",
		"exp_modifier", "reusable_tms_tutors", "turbo_a", "better_shops"
	]

static func validate_schema(schema: Dictionary) -> Dictionary:
	var req_keys = [
		"goal", "norman_count", "elite_four_count", "badges", "hms", "key_items",
		"overworld_items", "wild_pokemon", "starters", "trainer_parties",
		"exp_modifier", "reusable_tms_tutors", "turbo_a", "better_shops"
	]
	return validate_schema_for_keys(schema, req_keys)

func _build_step_content(step_num: int, container: VBoxContainer) -> void:
	match step_num:
		1: _build_step_1_goal(container)
		2: _build_step_2_items(container)
		3: _build_step_3_pokemon(container)
		4: _build_step_4_battle(container)
		5: _build_step_5_qol(container)

# --- STEP 1: GOAL & PACE ---
func _build_step_1_goal(container: VBoxContainer) -> void:
	add_step_description(container, "Step 1: Choose your Win Condition and Game Length")
	
	var goals_data = [
		{"id": "champion", "val": 0, "title": "🏆 Become Champion", "desc": "Defeat the Elite Four & Champion in the Hall of Fame. Standard full game."},
		{"id": "steven", "val": 1, "title": "🏔️ Defeat Steven", "desc": "Defeat Steven Stone in Meteor Falls after completing the main game."},
		{"id": "norman", "val": 2, "title": "🥊 Defeat Norman", "desc": "Short game goal! Beat Norman at Petalburg Gym to win early."},
		{"id": "legendary_hunt", "val": 3, "title": "🐉 Legendary Hunt", "desc": "Defeat or catch a specified number of legendary Pokémon across Hoenn."}
	]
	
	var current_g = current_config.get("goal", "champion")
	add_card_grid(container, goals_data, 2, current_g, func(item_id, item_data):
		set_option_value("goal", item_id)
	)
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	add_slider_option(container, "Norman Gym Requirements (Badges required):", "norman_count", 0, 7, 1, " Badges")
	add_slider_option(container, "Elite Four Requirements (Badges required):", "elite_four_count", 0, 8, 1, " Badges")

# --- STEP 2: ITEM SHUFFLE & WORLD ---
func _build_step_2_items(container: VBoxContainer) -> void:
	add_step_description(container, "Step 2: Item Locations & World Access Presets")
	
	var presets = [
		{"id": "standard", "name": "🔑 Standard", "desc": "Shuffles Key Items, Badges, HMs & Overworld items. Great default!"},
		{"id": "full", "name": "🎁 Full Shuffle", "desc": "Adds Hidden Items, NPC Gifts, Berry Trees, Rods & Tickets to the pool."},
		{"id": "chaos", "name": "🌀 Max Chaos", "desc": "Enables Trainersanity & Dexsanity! Adds 300+ item locations."}
	]
	
	add_card_grid(container, presets, 3, "", func(item_id, _data):
		if item_id == "standard":
			set_option_value("badges", "completely_random")
			set_option_value("hms", "completely_random")
			set_option_value("key_items", true)
			set_option_value("overworld_items", true)
			set_option_value("hidden_items", false)
			set_option_value("npc_gifts", false)
			set_option_value("dexsanity", false)
			set_option_value("trainersanity", false)
		elif item_id == "full":
			set_option_value("badges", "completely_random")
			set_option_value("hms", "completely_random")
			set_option_value("key_items", true)
			set_option_value("overworld_items", true)
			set_option_value("hidden_items", true)
			set_option_value("npc_gifts", true)
			set_option_value("berry_trees", true)
			set_option_value("rods", true)
			set_option_value("event_tickets", true)
			set_option_value("dexsanity", false)
			set_option_value("trainersanity", false)
		elif item_id == "chaos":
			set_option_value("badges", "completely_random")
			set_option_value("hms", "completely_random")
			set_option_value("key_items", true)
			set_option_value("overworld_items", true)
			set_option_value("hidden_items", true)
			set_option_value("npc_gifts", true)
			set_option_value("dexsanity", true)
			set_option_value("trainersanity", true)
	)
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	add_toggle_option(container, "Randomize Key Items (Scope, Letter, Basement Key, etc.)", "key_items")
	add_toggle_option(container, "Randomize Overworld Pokéballs", "overworld_items")
	add_toggle_option(container, "Randomize Hidden Items", "hidden_items")
	add_toggle_option(container, "Randomize NPC Gifts", "npc_gifts")
	add_toggle_option(container, "Trainersanity (Defeating trainers awards items)", "trainersanity")
	add_toggle_option(container, "Dexsanity (Catching Pokémon species awards items)", "dexsanity")

# --- STEP 3: POKEMON & TRAINERS ---
func _build_step_3_pokemon(container: VBoxContainer) -> void:
	add_step_description(container, "Step 3: Pokémon Species & Trainer Party Randomization")
	
	var rando_presets = [
		{"id": "vanilla", "name": "🌿 Vanilla", "desc": "Original GBA Pokémon encounters, starters & trainer teams."},
		{"id": "balanced", "name": "⚖️ Balanced", "desc": "Randomized species matched by Base Stat Total & Type!"},
		{"id": "chaos", "name": "🤪 Total Chaos", "desc": "Wilds, Starters, Trainers, Types & Abilities completely random!"}
	]
	
	add_card_grid(container, rando_presets, 3, "", func(item_id, _data):
		if item_id == "vanilla":
			set_option_value("wild_pokemon", "vanilla")
			set_option_value("starters", "vanilla")
			set_option_value("trainer_parties", "vanilla")
			set_option_value("types", "vanilla")
			set_option_value("abilities", "vanilla")
		elif item_id == "balanced":
			set_option_value("wild_pokemon", "match_base_stats_and_type")
			set_option_value("starters", "match_base_stats_and_type")
			set_option_value("trainer_parties", "match_base_stats")
			set_option_value("types", "vanilla")
			set_option_value("abilities", "vanilla")
		elif item_id == "chaos":
			set_option_value("wild_pokemon", "completely_random")
			set_option_value("starters", "completely_random")
			set_option_value("trainer_parties", "completely_random")
			set_option_value("types", "completely_random")
			set_option_value("abilities", "completely_random")
	)
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	var wild_choices = [
		{"id": "vanilla", "title": "Vanilla"},
		{"id": "match_base_stats", "title": "Match Base Stats"},
		{"id": "match_type", "title": "Match Type"},
		{"id": "match_base_stats_and_type", "title": "Match Base Stats & Type"},
		{"id": "completely_random", "title": "Completely Random"}
	]
	add_dropdown_option(container, "Wild Pokémon Encounters:", "wild_pokemon", wild_choices)
	add_toggle_option(container, "Randomize Pokémon Types", "types")
	add_toggle_option(container, "Randomize Pokémon Abilities", "abilities")

# --- STEP 4: BATTLE & LEVELING ---
func _build_step_4_battle(container: VBoxContainer) -> void:
	add_step_description(container, "Step 4: Movesets, Battle Mechanics & EXP Multipliers")
	
	# Moveset Randomization
	var move_choices = [
		{"id": "vanilla", "title": "Vanilla Movesets"},
		{"id": "randomized", "title": "Randomized Level-Up Moves"},
		{"id": "start_with_four_moves", "title": "Randomized (Start with 4 Moves)"}
	]
	add_dropdown_option(container, "Level-Up Movesets:", "level_up_moves", move_choices)
	
	var current_moves = str(current_config.get("level_up_moves", "vanilla"))
	if current_moves != "vanilla":
		add_slider_option(container, "Move Match Type Bias (Probability learned move matches Pokémon type):", "move_match_type_bias", 0, 100, 5, "%")
		
	add_toggle_option(container, "Randomize TM & Move Tutor Moves", "tm_tutor_moves")
	
	var sep = HSeparator.new()
	container.add_child(sep)
	
	# EXP & Catching
	add_slider_option(container, "EXP Gain Multiplier:", "exp_modifier", 50, 500, 25, "%")
	add_toggle_option(container, "Reusable TMs & Infinite Move Tutors", "reusable_tms_tutors")
	add_toggle_option(container, "Guaranteed Catch (Every Pokéball succeeds)", "guaranteed_catch")

# --- STEP 5: QOL & EXTRAS ---
func _build_step_5_qol(container: VBoxContainer) -> void:
	add_step_description(container, "Step 5: Quality of Life & Multiplayer Extras")
	
	add_toggle_option(container, "⚡ Turbo A (Hold A to auto-advance dialogue)", "turbo_a")
	add_toggle_option(container, "🏪 Better Shops (Pokémarts sell all TMs & Stones)", "better_shops")
	add_toggle_option(container, "🎵 Randomize Music Tracks", "music")
	add_toggle_option(container, "🎺 Randomize Pickups & Fanfares", "fanfares")
	add_toggle_option(container, "💀 DeathLink (Fainting triggers death for partners)", "death_link")
	add_toggle_option(container, "🤝 Wonder Trading (Trade Pokémon online in Pokénav/Center)", "enable_wonder_trading")
