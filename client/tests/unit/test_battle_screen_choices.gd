extends "res://tests/test_case.gd"
## BattleScreen's choice state: wait requests, rejected choices and screens opened mid-decision.

const ROOM := "battle-gen9randombattle-90"
const REQUEST := {"rqid": 3, "active": [{"moves": [
		{"move": "Thunderbolt", "id": "thunderbolt", "pp": 24, "maxpp": 24, "target": "normal"},
		{"move": "Volt Switch", "id": "voltswitch", "pp": 32, "maxpp": 32, "target": "normal"}]}],
	"side": {"name": "Me", "id": "p1", "pokemon": [
		{"ident": "p1: Pikachu", "details": "Pikachu, L90", "condition": "200/200", "active": true,
			"moves": ["thunderbolt", "voltswitch"]},
		{"ident": "p1: Snorlax", "details": "Snorlax, L80", "condition": "300/300", "active": false,
			"moves": ["bodyslam"]}]}}


func _feed(lines: String) -> void:
	for msg in PSParser.parse_frame(">%s\n%s" % [ROOM, lines]):
		EventBus.message_received.emit(msg)


func _request(request: Dictionary) -> void:
	_feed("|request|" + JSON.stringify(request))


func _start() -> void:
	_feed("|init|battle\n|player|p1|Me|1|\n|player|p2|Foe|2|\n|switch|p1a: Pikachu|Pikachu, L90|200/200\n" +
		"|switch|p2a: Mew|Mew|100/100\n|turn|1")


func _screen() -> Control:
	var screen: Control = load("res://src/ui/screens/battle/battle_screen.tscn").instantiate()
	screen.bind(ROOM)
	Engine.get_main_loop().root.add_child(screen)
	return screen


func _done(screen: Control) -> void:
	screen.free()
	Rooms.battles.erase(ROOM)


func test_wait_request_leaves_nothing_to_cancel() -> void:
	_start()
	var screen := _screen()
	_request(REQUEST)
	screen._on_choice_sent("move 1")
	assert_true(screen._can_cancel(), "Cancel while the choice can still be taken back")
	_feed("|move|p1a: Pikachu|Thunderbolt|p2a: Mew\n|faint|p2a: Mew\n|upkeep|")
	_request({"rqid": 4, "wait": true, "side": REQUEST["side"]})
	screen._refresh()
	assert_eq(screen._chosen, "", "the carried-out choice is forgotten")
	assert_true(not screen._cancel_button.visible, "no Cancel after a wait request")
	assert_true(not screen._can_cancel(), "Esc doesn't send /undo")
	_done(screen)


func test_invalid_choice_makes_the_controls_usable_again() -> void:
	_start()
	var screen := _screen()
	_request(REQUEST)
	screen._on_choice_sent("move 3")
	_feed("|error|[Invalid choice] Can't move: Your Pikachu doesn't have a move 3")
	screen._refresh()
	assert_true(not screen._waiting, "not waiting any more")
	assert_eq(screen._chosen, "", "nothing chosen")
	assert_true(not screen._move_buttons[0].disabled, "moves can be picked again")
	assert_eq(screen._choice_note.text, "Can't move: Your Pikachu doesn't have a move 3", "the reason is shown")
	assert_true(Rooms.get_battle(ROOM).awaiting_choice, "the battle waits for a choice again")
	_done(screen)


func test_refused_undo_keeps_the_choice() -> void:
	_start()
	var screen := _screen()
	_request(REQUEST)
	screen._on_choice_sent("switch 2")
	assert_true(screen._can_cancel(), "can be taken back")
	screen._on_choice_undone()
	assert_true(not screen._waiting, "taken back locally")
	_feed("|error|[Invalid choice] Can't undo: A trapping/disabling effect would cause undo to leak information")
	screen._refresh()
	assert_eq(screen._chosen, "switch 2", "the switch stands")
	assert_true(screen._waiting, "waiting again")
	assert_true(not screen._cancel_button.visible and not screen._can_cancel(), "no Cancel for a choice that can't be undone")
	assert_true(not Rooms.get_battle(ROOM).awaiting_choice, "the battle doesn't ask for a choice")
	_done(screen)


func test_screen_opened_mid_decision_shows_the_request() -> void:
	_start()
	_request(REQUEST)
	var screen := _screen()
	screen._refresh()
	assert_true(not screen._waiting, "not waiting")
	assert_true(screen._move_buttons[0].visible and not screen._move_buttons[0].disabled, "moves to pick")
	assert_true(screen._slot_buttons[1].visible and not screen._slot_buttons[1].disabled, "a switch to pick")
	_done(screen)

	_start()
	_request(REQUEST)
	_feed("|sentchoice|move 1")
	screen = _screen()
	assert_true(screen._waiting, "a choice already sent: waiting")
	_done(screen)
