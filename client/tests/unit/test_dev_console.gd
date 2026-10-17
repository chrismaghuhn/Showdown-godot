extends "res://tests/test_case.gd"
## The developer console: where the command box sends to, and which battle actions it offers
## (no server: rooms are fed as protocol frames, like test_main_tabs).

const DevConsoleScene := preload("res://src/ui/screens/dev_console/dev_console.tscn")
const MOVE_REQUEST := '{"active":[{"moves":[{"move":"Tackle","id":"tackle","pp":35,"maxpp":35}]}],' \
	+ '"side":{"id":"p1","name":"Ash","pokemon":[{"ident":"p1: Pikachu","details":"Pikachu, L50",' \
	+ '"condition":"100/100","active":true}]},"rqid":3}'

# Feeding battles posts notifications; the tests put the history back.
var _history: Array[Dictionary] = []
var _unread := 0


func _console() -> Control:
	_history = Notifier.history.duplicate()
	_unread = Notifier.unread
	var console: Control = DevConsoleScene.instantiate()
	Engine.get_main_loop().root.add_child(console)
	return console


func _feed(frame: String) -> void:
	for msg in PSParser.parse_frame(frame):
		EventBus.message_received.emit(msg)


## A running battle of Ash's: `room` + |init|, a Pikachu out, optionally our move request.
func _start(room: String, with_request := false) -> void:
	_feed(">%s\n|init|battle\n|player|p1|Ash|1|\n|player|p2|Misty|2|\n|switch|p1a: Pikachu|Pikachu, L50|100/100\n|turn|1" % room)
	if with_request:
		_feed(">%s\n|request|%s" % [room, MOVE_REQUEST])


## Action buttons still shown (cleared ones are only queued for deletion within the frame).
func _live(container: Node) -> Array[Node]:
	var live: Array[Node] = []
	live.assign(container.get_children().filter(func(child: Node) -> bool: return not child.is_queued_for_deletion()))
	return live


func _cleanup(console: Control, rooms: Array) -> void:
	console.free()
	for room: String in rooms:
		Rooms.battles.erase(room)
		Notifier._notified_rqid.erase(room)
	Notifier.history = _history
	Notifier.unread = _unread


func test_commands_go_global_after_leaving_the_battle() -> void:
	var console := _console()
	_start("battle-gen9randombattle-51")
	assert_eq(console._current_battle, "battle-gen9randombattle-51", "commands go to the battle")
	_feed(">battle-gen9randombattle-51\n|win|Ash")
	assert_eq(console._current_battle, "battle-gen9randombattle-51", "an ended battle's room still takes chat")
	_feed(">battle-gen9randombattle-99\n|deinit")
	assert_eq(console._current_battle, "battle-gen9randombattle-51", "leaving another room changes nothing")
	_feed(">battle-gen9randombattle-51\n|deinit")
	assert_eq(console._current_battle, "", "after leaving, commands are sent globally")
	_cleanup(console, ["battle-gen9randombattle-51", "battle-gen9randombattle-99"])


func test_leaving_a_running_battle_clears_its_view_and_actions() -> void:
	var console := _console()
	_start("battle-gen9randombattle-52", true)
	assert_eq(_live(console._actions).size(), 1, "the move is offered")
	assert_true(not console._battle_info.text.is_empty(), "battle info shown")
	assert_eq(_live(console._sprite_row).size(), 2, "a sprite slot per side")
	_feed(">battle-gen9randombattle-52\n|deinit")
	assert_eq(_live(console._actions).size(), 0, "no actions for the left room")
	assert_eq(console._battle_info.text, "", "battle info cleared")
	assert_eq(_live(console._sprite_row).size(), 0, "sprites cleared")
	assert_eq([console._sprites.size(), console._sprite_keys.size()], [0, 0], "sprite bookkeeping cleared")
	_cleanup(console, ["battle-gen9randombattle-52"])


func test_leaving_follows_another_running_battle() -> void:
	var console := _console()
	_start("battle-gen9randombattle-53")  # running, not our move
	_start("battle-gen9randombattle-54", true)  # waiting for our choice
	_start("battle-gen9randombattle-55")
	_feed(">battle-gen9randombattle-55\n|win|Misty")  # over, but not left
	_start("battle-gen9randombattle-56")
	assert_eq(console._current_battle, "battle-gen9randombattle-56", "the newest battle is shown")
	_feed(">battle-gen9randombattle-56\n|deinit")
	assert_eq(console._current_battle, "battle-gen9randombattle-54", "the battle waiting for us comes first")
	var actions := _live(console._actions)
	assert_eq(actions.map(func(b: Node) -> String: return b.get_meta(&"choice")), ["move 1"], "its move is offered")
	assert_true(not console._battle_info.text.is_empty(), "its info is shown")
	_feed(">battle-gen9randombattle-54\n|deinit")
	assert_eq(console._current_battle, "battle-gen9randombattle-53", "then any running battle")
	assert_eq(_live(console._actions).size(), 0, "not our move there")
	_feed(">battle-gen9randombattle-53\n|deinit")
	assert_eq(console._current_battle, "", "an ended battle isn't followed: commands go globally")
	_cleanup(console, ["battle-gen9randombattle-53", "battle-gen9randombattle-54",
		"battle-gen9randombattle-55", "battle-gen9randombattle-56"])


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


## Each offered switch action as "text -> choice" (move buttons left out).
func _switch_actions(request: Dictionary) -> Array[String]:
	var console := _console()
	console._on_battle_request(BattleState.new("battle-gen9randombattle-67"), request)
	var actions: Array[String] = []
	for button: Button in _live(console._actions):
		if not button.text.begins_with("Tackle"):
			actions.append("%s -> %s" % [button.text, button.get_meta(&"choice")])
	_cleanup(console, [])
	return actions


func test_maybe_trapped_still_offers_switches() -> void:
	var moves := [{"move": "Tackle", "id": "tackle", "pp": 35, "maxpp": 35}]
	var garchomp: Array[String] = ["Switch to Garchomp (300/300) -> switch 2"]
	assert_eq(_switch_actions(_request({"moves": moves})), garchomp, "free")
	assert_eq(_switch_actions(_request({"moves": moves, "maybeTrapped": true})), garchomp, "maybe trapped")
	assert_eq(_switch_actions(_request({"moves": moves, "trapped": true})), [] as Array[String], "trapped")


func test_revival_blessing_offers_the_fainted_bench_pokemon() -> void:
	assert_eq(_switch_actions(_request({}, true)), ["Revive Gholdengo (0 fnt) -> switch 3"] as Array[String], "only the fainted one")
