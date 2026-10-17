extends "res://tests/test_case.gd"
## StageLayout (design "Battlefield spec"), StatCalc and the extended BattleState.


func _battle(lines: String) -> BattleState:
	var battle := BattleState.new("battle-test")
	for msg in PSParser.parse_frame(">battle-test\n" + lines):
		battle.apply(msg)
	return battle


func test_stage_matches_design_table() -> void:
	# "Resolved sizes" table: B · Desktop 1280 -> field 622 × 420, u 0.972, slots 109 · 128.
	var field := Vector2(622, 420)
	assert_eq(snappedf(StageLayout.unit(field), 0.001), 0.972, "u desktop 1280")
	var slots := StageLayout.compute(field)
	assert_eq(roundi(slots["front"]["slot"].size.x), 109, "front slot")
	assert_eq(roundi(slots["back"]["slot"].size.x), 128, "back slot")
	assert_eq(Vector2i(slots["front"]["platform"].size.round()), Vector2i(156, 19), "front platform")
	# A · Familiar 1920 -> 1494 × 780, u 2.167, slots 243 · 286.
	var big := StageLayout.compute(Vector2(1494, 780))
	assert_eq(roundi(big["front"]["slot"].size.x), 243, "front slot 1920")
	assert_eq(roundi(big["back"]["slot"].size.x), 286, "back slot 1920")


func test_stage_is_centered_and_bottom_aligned() -> void:
	var field := Vector2(1000, 400)  # wider than 16:9 -> centered horizontally
	var u := StageLayout.unit(field)
	assert_eq(u, 400.0 / 360.0, "height bound")
	assert_eq(StageLayout.origin(field), Vector2((1000 - 640 * u) / 2, 0), "origin")
	var slots := StageLayout.compute(field)
	assert_eq(slots["back"]["slot"].end.y, slots["back"]["feet"].y, "sprite stands on its feet point")
	assert_eq(slots["back"]["platform"].get_center(), slots["back"]["feet"], "platform centered on feet")


func test_doubles_has_four_slots() -> void:
	var slots := StageLayout.compute(Vector2(640, 360), true)
	assert_eq(slots.keys().size(), 4, "slots")
	assert_eq(slots["front_r"]["feet"], Vector2(564, 152), "feet at u = 1")


func test_sprite_size_snaps_pixel_sprites() -> void:
	assert_eq(StageLayout.sprite_size(191, Vector2(96, 96)), Vector2(192, 192), "snaps to 2 × 96")
	assert_eq(StageLayout.sprite_size(100, Vector2(96, 96)), Vector2(96, 96), "snaps to 1 × 96")
	var unsnapped := StageLayout.sprite_size(128, Vector2(96, 96))
	assert_eq(unsnapped, Vector2(128, 128), "too far from 96 -> fit slot")
	assert_eq(StageLayout.sprite_size(100, Vector2(200, 100), false), Vector2(100, 50), "keeps aspect")


func test_stat_ranges() -> void:
	assert_eq(StatCalc.stat_range("atk", 130, 100), Vector2i(238, 394), "Garchomp Atk")
	assert_eq(StatCalc.stat_range("hp", 108, 100), Vector2i(326, 420), "Garchomp HP")
	assert_eq(StatCalc.stat_range("hp", 1, 100), Vector2i(1, 1), "Shedinja HP")
	assert_eq(StatCalc.boost_multiplier(2), 2.0, "+2")
	assert_eq(StatCalc.boost_multiplier(-1), 2.0 / 3.0, "-1")


func test_items_abilities_and_tera_are_revealed() -> void:
	var b := _battle("|switch|p2a: Ghold|Gholdengo|100/100\n|switch|p1a: Tremor|Garchomp|100/100\n" +
		"|-heal|p2a: Ghold|47/100|[from] item: Leftovers\n" +
		"|-ability|p1a: Tremor|Rough Skin\n" +
		"|-damage|p1a: Tremor|80/100|[from] ability: Rough Skin|[of] p2a: Ghold\n" +
		"|-terastallize|p1a: Tremor|Steel\n|move|p2a: Ghold|Nasty Plot|p2a: Ghold")
	var ghold := b.get_pokemon("p2a: Ghold")
	assert_eq(ghold.item, "Leftovers", "item from [from]")
	assert_eq(ghold.ability, "Rough Skin", "ability of [of] holder")
	assert_eq(b.get_pokemon("p1a: Tremor").tera_type, "Steel", "tera")
	assert_eq(ghold.revealed_moves, PackedStringArray(["Nasty Plot"]), "revealed moves")


func test_volatiles_hazard_layers_and_turns() -> void:
	var b := _battle("|turn|3\n|switch|p1a: A|Abra|100/100\n|-start|p1a: A|move: Taunt\n" +
		"|-sidestart|p1: Ash|Spikes\n|-sidestart|p1: Ash|Spikes\n|-weather|Sandstorm\n|turn|5")
	assert_true(b.get_pokemon("p1a: A").volatiles.has("Taunt"), "volatile")
	assert_eq(b.side("p1").conditions["Spikes"]["layers"], 2, "spike layers")
	assert_eq(b.turns_left(b.weather_turn), 3, "weather turns left")
	b.apply(PSParser.parse_line("battle-test", "|-end|p1a: A|move: Taunt"))
	assert_true(b.get_pokemon("p1a: A").volatiles.is_empty(), "volatile ended")


func test_timer_messages() -> void:
	var b := _battle("|inactive|Time left: 140 sec this turn | 280 sec total")
	assert_true(b.timer_on, "timer on")
	assert_eq(b.timer_turn_seconds, 140, "turn seconds")
	assert_eq(b.timer_total_seconds, 280, "total seconds")
	b.apply(PSParser.parse_line("battle-test", "|inactiveoff|Battle timer is now OFF."))
	assert_true(not b.timer_on, "timer off")


func test_every_time_left_message_is_a_timer_update() -> void:
	var b := _battle("|inactive|Time left: 140 sec this turn | 280 sec total")
	assert_eq(b.timer_updates, 1, "first update")
	# The server often repeats the same values; the countdown must still resync to them.
	b.apply(PSParser.parse_line("battle-test", "|inactive|Time left: 140 sec this turn | 280 sec total"))
	assert_eq(b.timer_updates, 2, "repeated values")
	b.apply(PSParser.parse_line("battle-test", "|inactive|Ash has 60 seconds left."))
	assert_eq(b.timer_updates, 2, "other |inactive| texts don't touch our clock")
	b.apply(PSParser.parse_line("battle-test", "|inactiveoff|Battle timer is now OFF."))
	assert_eq(b.timer_updates, 3, "timer off")
