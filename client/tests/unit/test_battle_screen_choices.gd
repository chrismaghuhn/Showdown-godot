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


func test_choice_errors_are_classified() -> void:
	assert_eq(BattleState.choice_error("[Invalid choice] Can't move: Your Pikachu doesn't have a move 3"), "rejected", "rejected")
	assert_eq(BattleState.choice_error("[Invalid choice] Can't undo: A trapping/disabling effect would cause undo to leak information"),
		"stands", "can't undo")
	assert_eq(BattleState.choice_error("[Invalid choice] Sorry, too late to cancel; the next turn has already started"), "stands", "too late")
	assert_eq(BattleState.choice_error("[Invalid choice] There's nothing to choose"), "stands", "nothing to choose")
	assert_eq(BattleState.choice_error("[Invalid choice] There's nothing to cancel"), "ignore", "nothing to cancel")
	assert_eq(BattleState.choice_error("[Unavailable choice] Can't switch: The active Pokémon is trapped"), "unavailable", "unavailable")
	assert_eq(BattleState.choice_error("/join: you must be logged in"), "", "not a choice error")


func test_unavailable_choice_keeps_its_reason_with_the_updated_request() -> void:
	_start()
	var screen := _screen()
	_request(REQUEST)
	screen._on_choice_sent("switch 2")
	_feed("|error|[Unavailable choice] Can't switch: The active Pokémon is trapped")
	var trapped := REQUEST.duplicate(true)
	trapped["rqid"] = 4
	trapped["update"] = true
	trapped["active"][0]["trapped"] = true
	_request(trapped)
	screen._refresh()
	assert_true(not screen._waiting and screen._chosen.is_empty(), "pick again")
	assert_eq(screen._choice_note.text, "Can't switch: The active Pokémon is trapped", "the reason stays")
	assert_true(screen._slot_buttons[1].disabled, "the switch is blocked now")
	assert_true(not screen._move_buttons[0].disabled, "moves can be picked")
	_done(screen)


func test_late_undo_and_nothing_to_cancel() -> void:
	_start()
	var screen := _screen()
	_request(REQUEST)
	screen._on_choice_sent("move 1")
	screen._on_choice_undone()
	_feed("|error|[Invalid choice] Sorry, too late to cancel; the next turn has already started")
	assert_eq(screen._chosen, "move 1", "too late: the move stands")
	assert_true(screen._waiting and not screen._can_cancel(), "waiting, nothing to cancel")
	_request({"rqid": 4, "wait": true, "side": REQUEST["side"]})
	_feed("|error|[Invalid choice] There's nothing to cancel")
	screen._refresh()
	assert_true(screen._waiting, "still waiting after a wait request")
	assert_eq(screen._choice_error, "", "no stale note")
	_done(screen)


func test_refused_undo_of_a_choice_made_elsewhere_waits() -> void:
	_start()
	var screen := _screen()
	_request(REQUEST)
	_feed("|error|[Invalid choice] Can't undo: A trapping/disabling effect would cause undo to leak information")
	assert_true(screen._waiting, "the choice made elsewhere stands: waiting")
	assert_true(not Rooms.get_battle(ROOM).awaiting_choice, "the tab doesn't ask for a choice")
	_done(screen)


func test_no_cancel_in_formats_without_cancel() -> void:
	_start()
	var screen := _screen()
	var no_cancel := REQUEST.duplicate(true)
	no_cancel["noCancel"] = true
	_request(no_cancel)
	screen._on_choice_sent("move 1")
	assert_true(not screen._can_cancel(), "no Cancel offered")
	_done(screen)
