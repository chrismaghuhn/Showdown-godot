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
