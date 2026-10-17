extends "res://tests/test_case.gd"


func _run(lines: String, my_side := "p1") -> Array[Dictionary]:
	var battle := BattleState.new("battle-test")
	battle.my_side = my_side
	var builder := BattleLogBuilder.new()
	for msg in PSParser.parse_frame(">battle-test\n" + lines):
		battle.apply(msg)
		builder.push(msg, battle)
	return builder.take_new()


func test_move_row_collects_effectiveness_and_damage() -> void:
	var entries := _run("|player|p2|Mirebloom|1|\n|switch|p1a: Tremor|Garchomp|357/357\n" +
		"|switch|p2a: Ttar|Tyranitar|100/100\n|turn|4\n|move|p1a: Tremor|Iron Head|p2a: Ttar\n" +
		"|-supereffective|p2a: Ttar\n|-damage|p2a: Ttar|59/100")
	assert_eq(entries[2]["kind"], "turn", "turn header")
	assert_eq(entries[2]["turn"], 4, "turn number")
	var move: Dictionary = entries[3]
	assert_eq(move["text"], "Tremor used [b]Iron Head[/b]!", "move text")
	assert_eq(move["chips"], [["×2", "up"], ["Ttar −41%", "down"]], "chips on the move row")


func test_opponent_names_and_secondary_rows() -> void:
	var entries := _run("|switch|p2a: Ghold|Gholdengo|100/100\n|move|p2a: Ghold|Nasty Plot|p2a: Ghold\n" +
		"|-boost|p2a: Ghold|spa|2\n|-heal|p2a: Ghold|100/100|[from] item: Leftovers\n" +
		"|-damage|p2a: Ghold|94/100|[from] Stealth Rock")
	assert_eq(entries[1]["text"], "The opposing Ghold used [b]Nasty Plot[/b]!", "opposing prefix")
	assert_eq(entries[2]["indent"], true, "boost row indented")
	assert_eq(entries[2]["text"], "The opposing Ghold", "name at the start of a row is capitalized")
	assert_eq(entries[2]["chips"], [["+2 SpA", "up"]], "boost chip")
	assert_eq(entries[3]["text"], "Stealth Rock", "damage source row")
	assert_eq(entries[3]["chips"], [["Ghold −6%", "down"]], "hazard damage chip")


func test_consecutive_boosts_merge_into_one_row() -> void:
	var entries := _run("|switch|p1a: Tremor|Garchomp|100/100\n|-unboost|p1a: Tremor|def|1\n|-boost|p1a: Tremor|spe|1")
	assert_eq(entries.size(), 2, "one boost row")
	assert_eq(entries[1]["chips"], [["−1 Def", "down"], ["+1 Spe", "up"]], "merged chips")


func test_names_are_escaped_for_bbcode() -> void:
	var entries := _run("|switch|p1a: [b]Evil|Garchomp|100/100\n|move|p1a: [b]Evil|Earthquake|")
	assert_eq(entries[1]["text"], "[lb]b]Evil used [b]Earthquake[/b]!", "escaped nickname")


func test_status_damage_and_move_heals() -> void:
	var entries := _run("|switch|p1a: Goat|Gogoat|100/100\n|-damage|p1a: Goat|94/100|[from] brn\n" +
		"|move|p1a: Goat|Milk Drink|p1a: Goat\n|-heal|p1a: Goat|100/100")
	assert_eq(entries[1]["text"], "Burn", "status id becomes a name")
	assert_eq(entries[2]["chips"], [["Goat +6%", "up"]], "heal chip on the move row")


## #17: the server replays the whole log before the first |request| when (re)joining.
func _replay(lines: String, me: String) -> Array[Dictionary]:
	var battle := BattleState.new("battle-test")
	var builder := BattleLogBuilder.new()
	for msg in PSParser.parse_frame(">battle-test\n" + lines):
		battle.apply(msg)
		if msg.type == "player":
			battle.claim_side_by_name(me)
		builder.push(msg, battle)
	return builder.take_new()


func test_rejoin_names_opponent_before_first_request() -> void:
	var replay := "|init|battle\n|player|p1|Mirebloom|1|\n|player|p2|ironquill|2|\n" + \
		"|switch|p1a: Ghold|Gholdengo|100/100\n|switch|p2a: Tremor|Garchomp|100/100\n|turn|5\n" + \
		"|move|p1a: Ghold|Shadow Ball|p2a: Tremor"
	var entries := _replay(replay, "IronQuill")
	assert_eq(entries.back()["text"], "The opposing Ghold used [b]Shadow Ball[/b]!", "opponent named as opposing")
	assert_eq(entries[1]["text"], "ironquill sent out [b]Tremor[/b]!", "own switch unchanged")


func test_spectator_keeps_neutral_names() -> void:
	var replay := "|player|p1|Mirebloom|1|\n|player|p2|sandsea|2|\n|switch|p1a: Ghold|Gholdengo|100/100\n" + \
		"|move|p1a: Ghold|Shadow Ball|"
	var entries := _replay(replay, "ironquill")
	assert_eq(entries.back()["text"], "Ghold used [b]Shadow Ball[/b]!", "no opposing prefix for spectators")


func test_replace_caches_the_revealed_pokemons_hp() -> void:
	var entries := _run("|switch|p2a: Pikachu|Pikachu|100/100\n|-damage|p2a: Pikachu|40/100\n" +
		"|replace|p2a: Zoroark|Zoroark, M\n|turn|2\n|move|p1a: X|Tackle|p2a: Zoroark\n|-damage|p2a: Zoroark|20/100")
	assert_eq(entries.back()["chips"], [["Zoroark −20%", "down"]], "damage is relative to the disguise's HP")
