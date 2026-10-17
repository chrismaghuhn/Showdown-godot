extends "res://tests/test_case.gd"
## The app shell's tab lifecycle with a real Main (no server: leaving a room offline drops it
## locally, like the server's |deinit| would).

const MainScene := preload("res://src/app/main.tscn")
const Main := preload("res://src/app/main.gd")


func _main() -> Control:
	var main: Control = MainScene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	main.show_screen(&"home")
	return main


func _feed(frame: String) -> void:
	for msg in PSParser.parse_frame(frame):
		EventBus.message_received.emit(msg)


func _tab(room: String) -> StringName:
	return StringName("battle:" + room)


func _cleanup(main: Control, rooms: Array) -> void:
	main.free()
	for room: String in rooms:
		Rooms.battles.erase(room)
	Rooms.games.clear()


func test_battle_tabs_open_close_and_stay_when_the_server_drops_them() -> void:
	var main := _main()
	_feed(">battle-gen9randombattle-41\n|init|battle\n|player|p1|Ash|1|\n|player|p2|Misty|2|\n|turn|1")
	assert_eq(main.current, _tab("battle-gen9randombattle-41"), "a new battle comes to the front")
	EventBus.logged_in.emit("Ash")
	_feed('|updatesearch|{"searching":[],"games":{"battle-gen9randombattle-42":"[Gen 9] Random Battle"}}')
	_feed(">battle-gen9randombattle-42\n|init|battle\n|player|p2|Brock|2|\n|turn|3")
	assert_eq(main.current, _tab("battle-gen9randombattle-41"), "a battle from before the restart waits in its tab")
	assert_true(main.tabs.has_tab(_tab("battle-gen9randombattle-42")), "but it has a tab")

	main.show_screen(&"settings")
	_feed(">battle-gen9randombattle-43\n|init|battle\n|player|p2|Gary|2|\n|turn|1")
	var ids: Array[StringName] = main.tabs.ids()
	assert_true(ids.find(_tab("battle-gen9randombattle-43")) < ids.find(&"settings"), "battle tabs come before pages")

	_feed(">battle-gen9randombattle-42\n|deinit")
	assert_true(main.tabs.has_tab(_tab("battle-gen9randombattle-42")), "dropped by the server: the tab stays")
	assert_eq(main.battle_tab_spec((main._screens[_tab("battle-gen9randombattle-42")] as BattleScreen).battle)["meta"],
		"Random · ended", "shown as over")

	main.close_tab(_tab("battle-gen9randombattle-43"))
	assert_true(not main.tabs.has_tab(_tab("battle-gen9randombattle-43")), "watching: closes without asking")
	assert_eq(main.current, _tab("battle-gen9randombattle-42"), "the next battle tab takes over")
	main.close_tab(_tab("battle-gen9randombattle-42"))
	assert_eq(main.current, _tab("battle-gen9randombattle-41"), "then the remaining one")
	main.close_tab(&"home")
	assert_true(main.tabs.has_tab(&"home"), "Home can't be closed")
	main.show_screen(_tab("battle-gen9randombattle-99"))
	assert_eq(main.current, _tab("battle-gen9randombattle-41"), "an old notification of a gone battle opens nothing")
	_cleanup(main, ["battle-gen9randombattle-41", "battle-gen9randombattle-42", "battle-gen9randombattle-43"])


func test_running_battle_asks_before_closing() -> void:
	var main := _main()
	_feed(">battle-gen9randombattle-44\n|init|battle\n|player|p1|Ash|1|\n|player|p2|Misty|2|\n|turn|1")
	var battle := Rooms.get_battle("battle-gen9randombattle-44")
	battle.my_side = "p1"
	var was_state: int = Connection.state
	Connection.state = Connection.State.CONNECTED
	main.close_tab(_tab("battle-gen9randombattle-44"))
	Connection.state = was_state
	assert_true(main._close_dialog.visible, "forfeit prompt")
	main._close_dialog.hide()
	assert_true(main.tabs.has_tab(_tab("battle-gen9randombattle-44")), "nothing closed yet")
	_cleanup(main, ["battle-gen9randombattle-44"])


func test_sidebar_panels_follow_the_visible_battle_tab() -> void:
	var main := _main()
	_feed(">battle-gen9randombattle-51\n|init|battle\n|turn|1")
	_feed(">battle-gen9randombattle-52\n|init|battle\n|turn|1")
	var panel := Label.new()
	Plugins.register_panel("test-panel", &"sidebar", panel)
	var first: BattleScreen = main._screens[_tab("battle-gen9randombattle-51")]
	var second: BattleScreen = main._screens[_tab("battle-gen9randombattle-52")]
	assert_true(second.is_ancestor_of(panel), "the visible tab shows the panel")
	main.show_screen(_tab("battle-gen9randombattle-51"))
	assert_true(first.is_ancestor_of(panel), "it moves to the tab you open")
	main.close_tab(_tab("battle-gen9randombattle-51"))
	assert_true(is_instance_valid(panel) and second.is_ancestor_of(panel), "closing a tab hands the panel on")
	Plugins._panels = Plugins._panels.filter(func(p: Dictionary) -> bool: return p["control"] != panel)
	panel.get_parent().remove_child(panel)
	panel.free()
	_cleanup(main, ["battle-gen9randombattle-51", "battle-gen9randombattle-52"])


func test_next_tab_after_closing() -> void:
	var ids: Array[StringName] = [&"home", &"teambuilder", &"battle:a", &"battle:b", &"settings"]
	assert_eq(Main.next_tab_after_closing(ids, &"battle:a"), &"battle:b", "next battle")
	assert_eq(Main.next_tab_after_closing(ids, &"battle:b"), &"battle:a", "last battle: the one before")
	assert_eq(Main.next_tab_after_closing([&"home", &"teambuilder", &"battle:a"] as Array[StringName], &"battle:a"), &"home", "no battles left")
	assert_eq(Main.next_tab_after_closing(ids, &"settings"), &"battle:b", "a page: the tab to its left")


func test_attention_after_rejoin_and_rejected_choice() -> void:
	_feed(">battle-gen9randombattle-61\n|init|battle\n|player|p1|Ash|1|\n|turn|2")
	_feed('>battle-gen9randombattle-61\n|request|{"active":[{"moves":[]}],"side":{"id":"p1","name":"Ash","pokemon":[]},"rqid":4}\n|sentchoice|move 1')
	var battle := Rooms.get_battle("battle-gen9randombattle-61")
	assert_true(not battle.awaiting_choice, "rejoined after choosing: not your move")
	_feed(">battle-gen9randombattle-61\n|error|[Invalid choice] Can't move: Pikachu's Thunderbolt is disabled")
	assert_true(battle.awaiting_choice, "a rejected choice: your move again")
	assert_eq([battle.opponent_name(), battle.display_format()], ["", "gen9randombattle"], "helpers before |tier|")
	Rooms.battles.erase("battle-gen9randombattle-61")


func test_dismissed_sign_in_drops_the_pending_search() -> void:
	var main := _main()
	var overlay: ConnectionOverlay = main.connection_overlay
	overlay.preview({"state": Connection.State.CONNECTED, "session_up": true, "signed_in": false,
		"signing_in": false, "reconnecting": false, "server_host": "sim3.psim.us"}, {})
	assert_eq(overlay.current_card(), &"sign_in", "Battle! while signed out asks for a name")
	Rooms._pending_search = "gen9randombattle"
	assert_true(Rooms.is_searching(), "the search waits for the name")
	overlay._sign_in.dismissed.emit()
	assert_true(not Rooms.is_searching(), "Not now: no search later")
	main.free()


func test_a_battle_you_played_that_expired_reads_ended() -> void:
	var main := _main()
	_feed(">battle-gen9randombattle-71\n|init|battle\n|player|p1|Ash|1|\n|player|p2|Misty|2|\n|turn|5")
	Rooms.get_battle("battle-gen9randombattle-71").my_side = "p1"
	_feed(">battle-gen9randombattle-71\n|deinit")
	var battle := (main._screens[_tab("battle-gen9randombattle-71")] as BattleScreen).battle
	assert_eq(main.battle_tab_spec(battle)["meta"], "Random · ended", "not a tie")
	_cleanup(main, ["battle-gen9randombattle-71"])


func test_lobby_rebuilds_battle_cards_once_per_frame() -> void:
	var main := _main()
	var home: HomeScreen = main._screens[&"home"]
	main.show_screen(&"settings")
	_feed(">battle-gen9randombattle-81\n|init|battle\n|player|p1|Ash|1|\n|player|p2|Misty|2|\n|turn|1")
	main.show_screen(&"home")
	for turn in range(2, 40):
		_feed(">battle-gen9randombattle-81\n|switch|p2a: Pikachu|Pikachu, L88|50/100\n|-damage|p2a: Pikachu|40/100\n|turn|%d" % turn)
	assert_true(home._battles_dirty, "many messages: one pending rebuild")
	home._refresh_battles()
	assert_eq(home._battles.get_child_count(), 1, "one card")
	assert_true(not home._battles_dirty, "done")
	_cleanup(main, ["battle-gen9randombattle-81"])


func test_server_popups_become_toasts() -> void:
	var main := _main()
	var toasts: Array[Dictionary] = []
	var on_toast := func(toast: Dictionary) -> void: toasts.append(toast)
	EventBus.toast_requested.connect(on_toast)
	EventBus.popup.emit("The user 'nobody' was not found.")
	EventBus.popup.emit("|html|<b>Team rejected</b>: Pikachu is banned.")
	assert_eq(toasts.map(func(t: Dictionary) -> String: return t["body"]),
		["The user 'nobody' was not found.", "Team rejected : Pikachu is banned."], "plain text")
	EventBus.toast_requested.disconnect(on_toast)
	_cleanup(main, [])
