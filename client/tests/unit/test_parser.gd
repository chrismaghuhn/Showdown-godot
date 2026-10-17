extends "res://tests/test_case.gd"


func test_frame_with_room_id() -> void:
	var msgs := PSParser.parse_frame(">battle-gen9randombattle-1\n|turn|3\n|move|p1a: Pikachu|Thunderbolt|p2a: Mew")
	assert_eq(msgs.size(), 2, "message count")
	assert_eq(msgs[0].room_id, "battle-gen9randombattle-1", "room id")
	assert_eq(msgs[0].type, "turn", "type")
	assert_eq(msgs[0].arg(0), "3", "turn arg")
	assert_eq(msgs[1].args, PackedStringArray(["p1a: Pikachu", "Thunderbolt", "p2a: Mew"]), "move args")


func test_global_frame_has_empty_room() -> void:
	var msgs := PSParser.parse_frame("|updateuser| Guest 1|0|1|{}")
	assert_eq(msgs[0].room_id, "", "room id")
	assert_eq(msgs[0].type, "updateuser", "type")


func test_chat_keeps_pipes_in_message() -> void:
	var msg := PSParser.parse_line("lobby", "|c|+Chris|hello | world")
	assert_eq(msg.args, PackedStringArray(["+Chris", "hello | world"]), "chat args")


func test_challstr_stays_intact() -> void:
	var msg := PSParser.parse_line("", "|challstr|4|abcdef0123")
	assert_eq(msg.arg(0), "4|abcdef0123", "challstr")


func test_kwargs_are_extracted() -> void:
	var msg := PSParser.parse_line("b", "|-heal|p1a: Snorlax|75/100|[from] item: Leftovers")
	assert_eq(msg.args, PackedStringArray(["p1a: Snorlax", "75/100"]), "positional args")
	assert_eq(msg.kwargs.get("from"), "item: Leftovers", "from kwarg")


func test_flag_kwarg_without_value() -> void:
	var msg := PSParser.parse_line("b", "|-weather|RainDance|[upkeep]")
	assert_eq(msg.kwargs.get("upkeep"), "", "upkeep flag")


func test_plain_text_lines() -> void:
	assert_eq(PSParser.parse_line("lobby", "Welcome!").type, "text", "no pipe")
	var msg := PSParser.parse_line("lobby", "||Some log text")
	assert_eq(msg.type, "text", "double pipe type")
	assert_eq(msg.arg(0), "Some log text", "double pipe text")


func test_to_id() -> void:
	assert_eq(PSParser.to_id("Mr. Mime-Galar!"), "mrmimegalar", "to_id")


func test_init_frames_are_backlog() -> void:
	var init := PSParser.parse_frame(">lobby\n|init|chat\n|title|Lobby\n|c:|1760699400|+Mirebloom|hi")
	assert_eq(init.map(func(m: PSMessage) -> bool: return m.backlog), [true, true, true], "every line of an |init| frame")
	var live := PSParser.parse_frame(">lobby\n|c:|1760700060|+Mirebloom|hi\n|j| Alice")
	assert_eq(live.map(func(m: PSMessage) -> bool: return m.backlog), [false, false], "a live frame")
	var later := PSParser.parse_frame(">lobby\n|c:|1760700060|+Mirebloom|hi\n|init|chat")
	assert_eq(later.map(func(m: PSMessage) -> bool: return m.backlog), [false, false], "|init| not on the first line")
	var headerless := PSParser.parse_frame("|init|chat\n|title|Lobby\n|c|+Mirebloom|hi")
	assert_eq(headerless.map(func(m: PSMessage) -> bool: return m.backlog), [true, true, true], "no >ROOMID header (lobby)")
	assert_eq(headerless[0].room_id, "", "lobby frame room id")
