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


func test_effects_before_turn_one_or_after_upkeep_count_from_the_next_turn() -> void:
	var b := _battle("|switch|p1a: Rilla|Rillaboom|100/100\n" +
		"|-fieldstart|move: Grassy Terrain|[from] ability: Grassy Surge|[of] p1a: Rilla\n" +
		"|-weather|SunnyDay|[from] ability: Drought|[of] p1a: Rilla")
	assert_eq(b.weather_turns_left(), 5, "never more than the duration before turn 1")
	b.apply(PSParser.parse_line("battle-test", "|turn|1"))
	assert_eq(b.turns_left(int(b.field_turns["Grassy Terrain"])), 5, "lead terrain at turn 1")
	assert_eq(b.weather_turns_left(), 5, "lead weather at turn 1")
	b.apply(PSParser.parse_line("battle-test", "|upkeep|"))
	b.apply(PSParser.parse_line("battle-test", "|turn|2"))
	assert_eq(b.turns_left(int(b.field_turns["Grassy Terrain"])), 4, "lead terrain at turn 2")

	b = _battle("|turn|3\n|-fieldstart|move: Psychic Terrain\n|-sidestart|p1: Ash|Reflect\n|upkeep|\n" +
		"|-fieldstart|move: Electric Terrain|[from] ability: Electric Surge|[of] p2a: Pinchurchin\n" +
		"|-sidestart|p2: Gary|move: Light Screen\n|-weather|RainDance|[from] ability: Drizzle|[of] p2a: Pelipper\n|turn|4")
	assert_eq(b.weather_turns_left(), 5, "weather started after upkeep")
	assert_eq(b.turns_left(int(b.field_turns["Electric Terrain"])), 5, "terrain started after upkeep")
	assert_eq(b.turns_left(int(b.side("p2").conditions["Light Screen"]["turn"])), 5, "screen started after upkeep")
	assert_eq(b.turns_left(int(b.side("p1").conditions["Reflect"]["turn"])), 4, "screen started during the turn")


func test_ability_weather_has_no_countdown_before_gen_6() -> void:
	var b := _battle("|gen|5\n|-weather|RainDance|[from] ability: Drizzle|[of] p1a: Politoed\n|turn|1")
	assert_eq(b.weather_turns_left(), -1, "gen 5 Drizzle")
	b.apply(PSParser.parse_line("battle-test", "|-weather|SunnyDay"))
	assert_eq(b.weather_turns_left(), 5, "gen 5 Sunny Day lasts 5 turns")
	b = _battle("|gen|9\n|-weather|RainDance|[from] ability: Drizzle|[of] p1a: Pelipper\n|turn|1")
	assert_eq(b.weather_turns_left(), 5, "gen 9 Drizzle lasts 5 turns")


func test_tailwind_lasts_four_turns() -> void:
	var b := _battle("|gen|9\n|turn|3\n|-sidestart|p1: Ash|move: Tailwind")
	var start := int(b.side("p1").conditions["Tailwind"]["turn"])
	assert_eq(b.turns_left(start, BattleState.effect_duration("Tailwind", b.gen)), 4, "turn it was used")
	b.apply(PSParser.parse_line("battle-test", "|upkeep|"))
	b.apply(PSParser.parse_line("battle-test", "|turn|4"))
	assert_eq(b.turns_left(start, BattleState.effect_duration("Tailwind", b.gen)), 3, "next turn")
	assert_eq(BattleState.effect_duration("Tailwind", 4), 3, "gen 4 Tailwind")
	assert_eq(BattleState.effect_duration("Reflect", 9), 5, "other effects")


func test_extreme_weather_has_no_countdown() -> void:
	var b := _battle("|-weather|DesolateLand|[from] ability: Desolate Land|[of] p1a: Groudon\n|turn|1")
	assert_eq(b.weather_turns_left(), -1, "Desolate Land")
	b.apply(PSParser.parse_line("battle-test", "|-weather|RainDance"))
	assert_eq(b.weather_turns_left(), 5, "normal weather")


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


func test_clear_negative_and_positive_boosts() -> void:
	var b := _battle("|switch|p1a: Shell|Cloyster|100/100\n|switch|p2a: Thief|Marshadow|100/100\n" +
		"|-boost|p1a: Shell|atk|2\n|-boost|p1a: Shell|spa|2\n|-boost|p1a: Shell|spe|2\n" +
		"|-unboost|p1a: Shell|def|1\n|-unboost|p1a: Shell|spd|1\n" +
		"|-clearnegativeboost|p1a: Shell|[silent]")
	var shell := b.side("p1").active_pokemon()
	assert_eq(shell.boosts, {"atk": 2, "spa": 2, "spe": 2}, "White Herb keeps the raised stats")
	b.apply(PSParser.parse_line("battle-test", "|-unboost|p1a: Shell|def|1"))
	b.apply(PSParser.parse_line("battle-test", "|-clearpositiveboost|p1a: Shell|p2a: Thief|move: Spectral Thief"))
	assert_eq(shell.boosts, {"def": -1}, "Spectral Thief takes only the raised stats")


func test_copy_swap_and_invert_boosts() -> void:
	var b := _battle("|switch|p1a: A|Alakazam|100/100\n|switch|p2a: B|Blissey|100/100\n" +
		"|-boost|p1a: A|spa|1\n|-boost|p2a: B|def|2\n|-unboost|p2a: B|spe|1\n" +
		"|-copyboost|p1a: A|p2a: B|[from] move: Psych Up")
	var a := b.side("p1").active_pokemon()
	var bliss := b.side("p2").active_pokemon()
	assert_eq(a.boosts, {"def": 2, "spe": -1}, "Psych Up copies the target's stages")
	b.apply(PSParser.parse_line("battle-test", "|-boost|p1a: A|spa|3"))
	b.apply(PSParser.parse_line("battle-test", "|-boost|p2a: B|atk|1"))
	b.apply(PSParser.parse_line("battle-test", "|-swapboost|p1a: A|p2a: B|atk, spa|[from] move: Power Swap"))
	assert_eq(a.boosts, {"def": 2, "spe": -1, "atk": 1}, "listed stats swapped, A")
	assert_eq(bliss.boosts, {"def": 2, "spe": -1, "spa": 3}, "listed stats swapped, B")
	b.apply(PSParser.parse_line("battle-test", "|-swapboost|p1a: A|p2a: B|[from] move: Heart Swap"))
	assert_eq(a.boosts, {"def": 2, "spe": -1, "spa": 3}, "Heart Swap swaps everything, A")
	assert_eq(bliss.boosts, {"def": 2, "spe": -1, "atk": 1}, "Heart Swap swaps everything, B")
	b.apply(PSParser.parse_line("battle-test", "|-boost|p1a: A|def|1"))
	b.apply(PSParser.parse_line("battle-test", "|-swapboost|p1a: A|p2a: B|[from] move: Heart Swap"))
	assert_eq(a.boosts, {"def": 2, "spe": -1, "atk": 1}, "a stat both have is swapped, A")
	assert_eq(bliss.boosts, {"def": 3, "spe": -1, "spa": 3}, "a stat both have is swapped, B")
	b.apply(PSParser.parse_line("battle-test", "|-invertboost|p1a: A|[from] move: Topsy-Turvy"))
	assert_eq(a.boosts, {"def": -2, "spe": 1, "atk": -1}, "Topsy-Turvy inverts")


func test_consumed_items_are_not_revealed_again() -> void:
	var b := _battle("|switch|p1a: X|Scizor|100/100\n|switch|p2a: Y|Blissey|100/100\n" +
		"|-enditem|p2a: Y|Sitrus Berry|[eat]\n|-heal|p2a: Y|60/100|[from] item: Sitrus Berry")
	var x := b.side("p1").active_pokemon()
	var y := b.side("p2").active_pokemon()
	assert_eq(y.item, "", "eaten berry stays gone")
	b.apply(PSParser.parse_line("battle-test", "|-item|p2a: Y|Sitrus Berry|[from] move: Recycle"))
	b.apply(PSParser.parse_line("battle-test", "|-damage|p2a: Y|40/100"))
	assert_eq(y.item, "Sitrus Berry", "recycled berry is held again")
	b.apply(PSParser.parse_line("battle-test", "|-enditem|p2a: Y|Sitrus Berry|[from] stealeat|[move] Bug Bite|[of] p1a: X"))
	b.apply(PSParser.parse_line("battle-test", "|-heal|p1a: X|100/100|[from] item: Sitrus Berry"))
	assert_eq(x.item, "", "Bug Bite: the eater doesn't hold the berry")
	assert_eq(y.item, "", "Bug Bite: the berry is gone")
	b.apply(PSParser.parse_line("battle-test", "|-heal|p2a: Y|46/100|[from] item: Leftovers"))
	assert_eq(y.item, "Leftovers", "other items are still revealed")


func test_of_names_the_holder_only_for_some_effects() -> void:
	var b := _battle("|switch|p1a: Starmie|Starmie|100/100\n|switch|p2a: Vaporeon|Vaporeon|80/100\n" +
		"|-heal|p2a: Vaporeon|100/100|[from] ability: Water Absorb|[of] p1a: Starmie")
	var starmie := b.side("p1").active_pokemon()
	var vaporeon := b.side("p2").active_pokemon()
	assert_eq(vaporeon.ability, "Water Absorb", "Water Absorb belongs to the healed Pokémon")
	assert_eq(starmie.ability, "", "the attacker isn't revealed")

	b = _battle("|switch|p1a: Gyarados|Gyarados|100/100\n|switch|p2a: Gardevoir|Gardevoir|100/100\n" +
		"|-ability|p2a: Gardevoir|Intimidate|Trace|[from] ability: Trace|[of] p1a: Gyarados")
	assert_eq(b.side("p2").active_pokemon().ability, "Intimidate", "Trace: the tracer now has Intimidate")
	assert_eq(b.side("p1").active_pokemon().ability, "Intimidate", "Trace: the traced Pokémon has Intimidate")

	b = _battle("|switch|p1a: Klefki|Klefki|100/100\n|switch|p2a: Y|Blissey|100/100\n" +
		"|-item|p1a: Klefki|Leftovers|[from] ability: Magician|[of] p2a: Y")
	assert_eq(b.side("p1").active_pokemon().ability, "Magician", "Magician belongs to the thief")
	assert_eq(b.side("p1").active_pokemon().item, "Leftovers", "Magician: stolen item")
	assert_eq(b.side("p2").active_pokemon().ability, "", "Magician: the victim isn't revealed")

	b = _battle("|switch|p1a: Atk|Scizor|100/100\n|switch|p2a: Weavile|Weavile|100/100\n" +
		"|-enditem|p1a: Atk|Life Orb|[silent]|[from] ability: Pickpocket|[of] p1a: Atk\n" +
		"|-item|p2a: Weavile|Life Orb|[from] ability: Pickpocket|[of] p1a: Atk")
	assert_eq(b.side("p1").active_pokemon().ability, "", "Pickpocket: the attacker isn't revealed")
	assert_eq(b.side("p2").active_pokemon().ability, "Pickpocket", "Pickpocket belongs to the thief")

	b = _battle("|switch|p1a: Frisker|Banette|100/100\n|switch|p2a: T|Garchomp|100/100\n" +
		"|-item|p2a: T|Choice Scarf|[from] ability: Frisk|[of] p1a: Frisker")
	assert_eq(b.side("p1").active_pokemon().ability, "Frisk", "Frisk still belongs to [of]")
	assert_eq(b.side("p2").active_pokemon().item, "Choice Scarf", "Frisk reveals the target's item")


func test_called_moves_are_not_revealed() -> void:
	var b := _battle("|switch|p1a: X|Clefable|100/100\n|switch|p2a: Y|Espeon|100/100\n" +
		"|move|p1a: X|Stealth Rock|p2a: Y\n" +
		"|move|p2a: Y|Stealth Rock|p1a: X|[from] ability: Magic Bounce\n" +
		"|move|p1a: X|Metronome|p1a: X\n|move|p1a: X|Thunderbolt|p2a: Y|[from] move: Metronome\n" +
		"|move|p2a: Y|Outrage|p1a: X\n|move|p2a: Y|Outrage|p1a: X|[from] lockedmove\n" +
		"|move|p1a: X|Sleep Talk|p1a: X\n|move|p1a: X|Moonblast|p2a: Y|[from] move: Sleep Talk\n" +
		"|move|p2a: Y|Pursuit|p1a: X|[from] move: Pursuit")
	var x := b.side("p1").active_pokemon()
	var y := b.side("p2").active_pokemon()
	assert_eq(x.revealed_moves, PackedStringArray(["Stealth Rock", "Metronome", "Sleep Talk", "Moonblast"]),
		"Metronome's pick isn't X's move, Sleep Talk's is")
	assert_eq(y.revealed_moves, PackedStringArray(["Outrage", "Pursuit"]), "a bounced move isn't Y's move, Pursuit is")
	assert_eq(y.ability, "Magic Bounce", "Magic Bounce is revealed")


func test_formechange_keeps_level_and_gender() -> void:
	var b := _battle("|switch|p1a: Aegislash|Aegislash, L50, M|100/100\n" +
		"|-formechange|p1a: Aegislash|Aegislash-Blade||[from] ability: Stance Change")
	var mon := b.side("p1").active_pokemon()
	assert_eq(mon.species, "Aegislash-Blade", "species")
	assert_eq(mon.level, 50, "level")
	assert_eq(mon.gender, "M", "gender")


func test_replace_moves_the_disguise_state_to_the_revealed_pokemon() -> void:
	var b := _battle("|switch|p2a: Pikachu|Pikachu, L88, F|50/100 par\n|switch|p2a: Snorlax|Snorlax|100/100\n" +
		"|switch|p2a: Pikachu|Pikachu, L88, F|100/100\n|-damage|p2a: Pikachu|40/100\n" +
		"|-boost|p2a: Pikachu|spa|2\n|-start|p2a: Pikachu|Taunt\n" +
		"|replace|p2a: Zoroark|Zoroark, L84, M")
	var side := b.side("p2")
	var zoroark: BattlePokemon = side.pokemon["Zoroark"]
	var pikachu: BattlePokemon = side.pokemon["Pikachu"]
	assert_true(side.active_pokemon() == zoroark, "Zoroark is in the slot")
	assert_eq(zoroark.species, "Zoroark", "species")
	assert_eq(zoroark.hp, 40, "Zoroark has the disguise's HP")
	assert_eq(zoroark.boosts, {"spa": 2}, "Zoroark has the disguise's boosts")
	assert_true(zoroark.volatiles.has("Taunt"), "Zoroark has the disguise's volatiles")
	assert_true(not pikachu.active, "Pikachu isn't active")
	assert_eq(pikachu.hp, 50, "Pikachu's own HP is back")
	assert_eq(pikachu.status, "par", "Pikachu's own status is back")
	assert_true(pikachu.boosts.is_empty(), "Pikachu has no boosts")


func test_replace_on_our_side_keeps_the_exact_hp() -> void:
	var b := BattleState.new("battle-test")
	b.my_side = "p1"
	for line in ["|switch|p1a: Pikachu|Pikachu, L88, F|100/100", "|-boost|p1a: Pikachu|spa|1"]:
		b.apply(PSParser.parse_line("battle-test", line))
	var zoroark := b.side("p1").get_or_add("Zoroark")
	zoroark.hp = 150
	zoroark.max_hp = 250
	b.apply(PSParser.parse_line("battle-test", "|replace|p1a: Zoroark|Zoroark, L84, M"))
	assert_eq(zoroark.hp, 150, "own HP from the request stays")
	assert_eq(zoroark.max_hp, 250, "own max HP stays")
	assert_eq(zoroark.boosts, {"spa": 1}, "boosts still move over")
