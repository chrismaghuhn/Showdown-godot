extends "res://tests/test_case.gd"


func _battle(lines: String) -> BattleState:
	var battle := BattleState.new("battle-test")
	for msg in PSParser.parse_frame(">battle-test\n" + lines):
		battle.apply(msg)
	return battle


func test_parse_ident() -> void:
	var ref := BattleState.parse_ident("p2b: Mr. Mime")
	assert_eq(ref["side"], "p2", "side")
	assert_eq(ref["slot"], 1, "slot")
	assert_eq(ref["name"], "Mr. Mime", "name")


func test_switch_sets_active_and_details() -> void:
	var b := _battle("|player|p1|Ash|1|\n|switch|p1a: Sparky|Pikachu, L88, F, shiny|100/100")
	var mon := b.side("p1").active_pokemon()
	assert_eq(b.side("p1").player_name, "Ash", "player name")
	assert_eq(mon.name, "Sparky", "nickname")
	assert_eq(mon.species, "Pikachu", "species")
	assert_eq(mon.level, 88, "level")
	assert_eq(mon.gender, "F", "gender")
	assert_true(mon.shiny, "shiny")


func test_damage_status_and_faint() -> void:
	var b := _battle("|switch|p2a: Mew|Mew|100/100\n|-damage|p2a: Mew|40/100 par\n")
	var mon := b.side("p2").active_pokemon()
	assert_eq(mon.hp, 40, "hp")
	assert_eq(mon.status, "par", "status")
	b.apply(PSParser.parse_line("battle-test", "|faint|p2a: Mew"))
	assert_true(mon.fainted, "fainted")


func test_boosts_reset_on_switch_out() -> void:
	var b := _battle("|switch|p1a: A|Abra|100/100\n|-boost|p1a: A|spa|2\n|-unboost|p1a: A|def|1")
	var abra := b.side("p1").active_pokemon()
	assert_eq(abra.boosts, {"spa": 2, "def": -1}, "boosts")
	b.apply(PSParser.parse_line("battle-test", "|switch|p1a: B|Bulbasaur|100/100"))
	assert_true(abra.boosts.is_empty(), "boosts cleared")
	assert_true(not abra.active, "no longer active")


func test_weather_field_and_side_conditions() -> void:
	var b := _battle("|-weather|SunnyDay\n|-fieldstart|move: Grassy Terrain\n|-sidestart|p1: Ash|move: Stealth Rock")
	assert_eq(b.weather, "SunnyDay", "weather")
	assert_eq(b.field_conditions, PackedStringArray(["Grassy Terrain"]), "field")
	assert_true(b.side("p1").conditions.has("Stealth Rock"), "side condition")
	b.apply(PSParser.parse_line("battle-test", "|-weather|none"))
	b.apply(PSParser.parse_line("battle-test", "|-fieldend|move: Grassy Terrain"))
	assert_eq(b.weather, "", "weather cleared")
	assert_true(b.field_conditions.is_empty(), "field cleared")


func test_win() -> void:
	var b := _battle("|turn|12\n|win|Ash")
	assert_eq(b.turn, 12, "turn")
	assert_true(b.ended, "ended")
	assert_eq(b.winner, "Ash", "winner")


func test_request_sets_own_side() -> void:
	var b := BattleState.new("battle-test")
	b.apply_request({
		"rqid": 1,
		"side": {"id": "p2", "name": "Me", "pokemon": [
			{"ident": "p2: Garchomp", "details": "Garchomp, L80, M", "condition": "250/301", "moves": ["earthquake", "outrage"]},
		]},
	})
	var chomp: BattlePokemon = b.side("p2").pokemon["Garchomp"]
	assert_eq(b.my_side, "p2", "my side")
	assert_eq(chomp.hp, 250, "hp")
	assert_eq(chomp.max_hp, 301, "max hp")
	assert_eq(chomp.moves, PackedStringArray(["earthquake", "outrage"]), "moves")
