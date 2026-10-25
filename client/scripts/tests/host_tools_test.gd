extends SceneTree

var lobby: Node
var net_mgr: Node

func _init() -> void:
	_run_test.call_deferred()

func _run_test() -> void:
	print("==================================================")
	print("  Starting Host Tools & Command Suite Test")
	print("==================================================")
	
	# Load network manager script
	net_mgr = root.get_node_or_null("NetworkManager")
	if not net_mgr:
		var net_script = load("res://scripts/core/network_manager.gd")
		if not net_script:
			_fail("Could not load network_manager.gd")
			return
		net_mgr = net_script.new()
		net_mgr.name = "NetworkManager"
		root.add_child(net_mgr)
		
	# Instantiate Lobby scene
	var lobby_scene = load("res://scenes/lobby.tscn")
	if not lobby_scene:
		_fail("Failed to load lobby.tscn")
		return
		
	lobby = lobby_scene.instantiate()
	root.add_child(lobby)
	
	print("[Test] 1. Validating Host Tools nodes in Lobby...")
	var host_btn: Button = lobby.get_node("%HostToolsBtn")
	var host_modal: Control = lobby.get_node("%HostToolsModal")
	
	if not host_btn or not host_modal:
		_fail("HostToolsBtn or HostToolsModal node missing in lobby.tscn")
		return
	print("[Test] HostToolsBtn and HostToolsModal verified present.")
	
	# Test 2: Host button visibility logic
	print("[Test] 2. Testing Host button visibility conditions...")
	net_mgr.user_id = "test-host-id"
	net_mgr.players = [{
		"userId": "test-host-id",
		"name": "HostPlayer",
		"games": ["Pokemon Emerald"],
		"isHost": true
	}]
	net_mgr.seed_status = "idle"
	lobby._update_lock_status_display(net_mgr.players)
	
	if host_btn.visible:
		_fail("HostToolsBtn should not be visible when seed_status is idle")
		return
		
	net_mgr.seed_status = "done"
	lobby._update_lock_status_display(net_mgr.players)
	if not host_btn.visible:
		_fail("HostToolsBtn should be visible when seed_status is done and player is host")
		return
	print("[Test] HostToolsBtn visibility verified (visible only when host + seed done).")
	
	# Test 3: Opening Modal & Tab Hierarchy
	print("[Test] 3. Testing HostToolsModal open and tab navigation...")
	host_modal.open()
	if not host_modal.visible:
		_fail("HostToolsModal failed to become visible on open()")
		return
		
	var tab_container: TabContainer = host_modal.get_node("%HostTabContainer")
	if not tab_container or tab_container.get_tab_count() != 3:
		_fail("Expected 3 tabs in HostTabContainer, found: " + str(tab_container.get_tab_count() if tab_container else 0))
		return
	print("[Test] Verified 3 Host Tools tabs: Quick Actions, Dispatcher, Console.")
	
	# Test 4: Seed Data Dispatcher Population & Filtering
	print("[Test] 4. Testing Location & Item Dispatcher population...")
	var mock_seed_data = {
		"players": ["Alice", "Bob"],
		"locations": {
			"Alice": [
				"Dewford Gym - Brawly Badge",
				"Petalburg City - Norman Badge",
				"Rustboro City - Roxanne Badge"
			],
			"Bob": [
				"Forgotten Crossroads - Grub",
				"City of Tears - Nailsmith Upgrade"
			]
		},
		"items": {
			"Alice": ["Knuckle Badge", "Balance Badge"],
			"Bob": ["Mothwing Cloak", "Lumafly Lantern"]
		},
		"allItems": ["Knuckle Badge", "Balance Badge", "Mothwing Cloak", "Lumafly Lantern"]
	}
	host_modal.seed_data = mock_seed_data
	host_modal._populate_dispatcher_slots()
	
	var slot_opt: OptionButton = host_modal.get_node("%SlotOption")
	if slot_opt.item_count != 2:
		_fail("Expected 2 player slots in SlotOption, found: " + str(slot_opt.item_count))
		return
		
	var loc_list: ItemList = host_modal.get_node("%LocItemList")
	if loc_list.item_count != 3:
		_fail("Expected 3 locations for Alice, found: " + str(loc_list.item_count))
		return
		
	# Test live search filtering
	var loc_search: LineEdit = host_modal.get_node("%LocSearchInput")
	loc_search.text = "Norman"
	host_modal._filter_locations()
	if loc_list.item_count != 1 or loc_list.get_item_text(0) != "Petalburg City - Norman Badge":
		_fail("Location search filter failed. Expected 'Petalburg City - Norman Badge', found item count: " + str(loc_list.item_count))
		return
	print("[Test] Location Dispatcher slot population and instant search filter verified.")
	
	# Test 5: Live Console & Command History
	print("[Test] 5. Testing Live Console terminal and history buffer...")
	var console_out: RichTextLabel = host_modal.get_node("%ConsoleOutput")
	var console_inp: LineEdit = host_modal.get_node("%ConsoleInput")
	
	# Simulate server log line
	net_mgr.server_log_received.emit("[AP Server URK2LU]: Player Isaac checked Main Deck (1/126)")
	await create_timer(0.05).timeout
	var out_text = console_out.get_parsed_text()
	if not "checked Main Deck" in out_text and not "checked Main Deck" in console_out.text:
		_fail("Console output did not render received server log line. Got: " + out_text + " | text: " + console_out.text)
		return
	print("[Test] Real-time server log streaming to Console output verified.")
	
	# Test command history input
	host_modal.command_history.clear()
	host_modal.command_history.append("/status")
	host_modal.command_history.append("/countdown 10")
	host_modal.history_index = 2
	
	# Simulate UP key
	var key_event = InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_UP
	host_modal._on_console_gui_input(key_event)
	
	if console_inp.text != "/countdown 10":
		_fail("Command history UP arrow navigation failed. Found: " + console_inp.text)
		return
	print("[Test] Command history buffer navigation verified.")
	
	# Cleanup
	host_modal.close()
	lobby.queue_free()
	net_mgr.queue_free()
	
	print("\n==================================================")
	print("  HOST TOOLS & COMMAND SUITE TEST PASSED!")
	print("==================================================")
	quit(0)

func _fail(reason: String) -> void:
	printerr("[Test FAIL] ", reason)
	if lobby:
		lobby.queue_free()
	if net_mgr:
		net_mgr.queue_free()
	quit(1)
