extends "res://tests/test_case.gd"
## The developer console: where the command box sends to, and which battle actions it offers
## (no server: rooms are fed as protocol frames, like test_main_tabs).

const DevConsoleScene := preload("res://src/ui/screens/dev_console/dev_console.tscn")


func _console() -> Control:
	var console: Control = DevConsoleScene.instantiate()
	Engine.get_main_loop().root.add_child(console)
	return console


func _feed(frame: String) -> void:
	for msg in PSParser.parse_frame(frame):
		EventBus.message_received.emit(msg)


func _cleanup(console: Control, rooms: Array) -> void:
	console.free()
	for room: String in rooms:
		Rooms.battles.erase(room)


func test_commands_go_global_after_leaving_the_battle() -> void:
	var console := _console()
	_feed(">battle-gen9randombattle-51\n|init|battle\n|player|p1|Ash|1|\n|player|p2|Misty|2|\n|turn|1")
	assert_eq(console._current_battle, "battle-gen9randombattle-51", "commands go to the battle")
	_feed(">battle-gen9randombattle-51\n|win|Ash")
	assert_eq(console._current_battle, "battle-gen9randombattle-51", "an ended battle's room still takes chat")
	_feed(">battle-gen9randombattle-99\n|deinit")
	assert_eq(console._current_battle, "battle-gen9randombattle-51", "leaving another room changes nothing")
	_feed(">battle-gen9randombattle-51\n|deinit")
	assert_eq(console._current_battle, "", "after leaving, commands are sent globally")
	_cleanup(console, ["battle-gen9randombattle-51", "battle-gen9randombattle-99"])


## A request for our lead Pawmot, with a healthy and a fainted Pokémon on the bench.
func _request(active: Dictionary, reviving := false) -> Dictionary:
	var request := {"rqid": 7, "side": {"id": "p1", "name": "Ash", "pokemon": [
		{"ident": "p1: Pawmot", "details": "Pawmot, L84, F", "condition": "250/250", "active": true},
		{"ident": "p1: Garchomp", "details": "Garchomp, L79, M", "condition": "300/300", "active": false},
		{"ident": "p1: Gholdengo", "details": "Gholdengo, L80", "condition": "0 fnt", "active": false},
	]}}
	if reviving:
		request["forceSwitch"] = [true]
		request["side"]["pokemon"][0]["reviving"] = true
	else:
		request["active"] = [active]
	return request


## Text of each offered switch action (move buttons left out).
func _switch_actions(request: Dictionary) -> Array[String]:
	var console := _console()
	console._on_battle_request(BattleState.new("battle-gen9randombattle-67"), request)
	var texts: Array[String] = []
	for button: Button in console._actions.get_children():
		if not button.text.begins_with("Tackle"):
			texts.append(button.text)
	console.free()
	return texts


func test_maybe_trapped_still_offers_switches() -> void:
	var moves := [{"move": "Tackle", "id": "tackle", "pp": 35, "maxpp": 35}]
	var garchomp: Array[String] = ["Switch to Garchomp (300/300)"]
	assert_eq(_switch_actions(_request({"moves": moves})), garchomp, "free")
	assert_eq(_switch_actions(_request({"moves": moves, "maybeTrapped": true})), garchomp, "maybe trapped")
	assert_eq(_switch_actions(_request({"moves": moves, "trapped": true})), [] as Array[String], "trapped")


func test_revival_blessing_offers_the_fainted_bench_pokemon() -> void:
	assert_eq(_switch_actions(_request({}, true)), ["Revive Gholdengo (0 fnt)"] as Array[String], "only the fainted one")
