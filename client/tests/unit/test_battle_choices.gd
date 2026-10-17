extends "res://tests/test_case.gd"
## BattleChoices: the rules behind the battle screen's switch slots and timer countdown.


## Own team in request order: an active Pokémon, a healthy one and a fainted one on the bench.
func _team() -> Array[BattlePokemon]:
	var lead := BattlePokemon.new("Pawmot")
	lead.active = true
	var bench := BattlePokemon.new("Garchomp")
	var fainted := BattlePokemon.new("Gholdengo")
	fainted.apply_condition("0 fnt")
	return [lead, bench, fainted]


func _request(active: Dictionary, reviving := false, force_switch := false) -> Dictionary:
	var request := {"active": [active], "side": {"pokemon": [
		{"ident": "p1: Pawmot", "condition": "250/250", "active": true},
		{"ident": "p1: Garchomp", "condition": "357/357", "active": false},
		{"ident": "p1: Gholdengo", "condition": "0 fnt", "active": false},
	]}}
	if reviving:
		request["side"]["pokemon"][0]["reviving"] = true
	if force_switch:
		request["forceSwitch"] = [true]
		request.erase("active")
	return request


func _switchable(request: Dictionary) -> Array[bool]:
	var result: Array[bool] = []
	for mon in _team():
		result.append(BattleChoices.can_switch_to(request, mon))
	return result


func test_maybe_trapped_still_allows_switching() -> void:
	assert_eq(_switchable(_request({"moves": []})), [false, true, false] as Array[bool], "free")
	assert_eq(_switchable(_request({"moves": [], "maybeTrapped": true})), [false, true, false] as Array[bool], "maybe trapped")
	assert_eq(_switchable(_request({"moves": [], "trapped": true})), [false, false, false] as Array[bool], "trapped")


func test_revival_blessing_picks_fainted_bench_pokemon() -> void:
	var request := _request({}, true, true)
	assert_true(BattleChoices.is_reviving(request), "reviving request")
	assert_eq(_switchable(request), [false, false, true] as Array[bool], "only the fainted one")
	assert_true(not BattleChoices.is_reviving(_request({}, false, true)), "plain forced switch")
	assert_eq(_switchable(_request({}, false, true)), [false, true, false] as Array[bool], "forced switch")


func test_timer_countdown_keeps_unknown_seconds() -> void:
	# Spectators only learn that the timer is on (-1 seconds): no "0:00 / 0:00" countdown.
	assert_eq(BattleChoices.count_down(-1), -1, "unknown stays unknown")
	assert_eq(BattleChoices.count_down(140), 139, "counts down")
	assert_eq(BattleChoices.count_down(0), 0, "stops at zero")


func test_timer_resyncs_on_every_update() -> void:
	var line := "|inactive|Time left: 140 sec this turn | 280 sec total"
	var battle := BattleState.new("battle-test")
	assert_true(BattleChoices.needs_timer_resync([], battle), "first sync")
	battle.apply(PSParser.parse_line("battle-test", line))
	assert_true(BattleChoices.needs_timer_resync([], battle), "first update")
	var seen := BattleChoices.timer_sync_key(battle)
	assert_true(not BattleChoices.needs_timer_resync(seen, battle), "no new update: keep counting down")
	battle.apply(PSParser.parse_line("battle-test", line))
	assert_true(BattleChoices.needs_timer_resync(seen, battle), "same values again")
	seen = BattleChoices.timer_sync_key(battle)
	var other := BattleState.new("battle-other")
	other.apply(PSParser.parse_line("battle-other", line))
	other.apply(PSParser.parse_line("battle-other", line))
	assert_true(BattleChoices.needs_timer_resync(seen, other), "another battle with the same values")


func test_timer_button_text() -> void:
	assert_eq(BattleChoices.timer_button(true, 140, 280),
		PackedStringArray(["2:20 / 4:40", "Your time this turn / in total. Click to turn the timer off."]), "own clock")
	assert_eq(BattleChoices.timer_button(true, -1, -1),
		PackedStringArray(["Timer", "The battle timer is on. Click to turn it off."]), "on, seconds unknown")
	assert_eq(BattleChoices.timer_button(false, -1, -1), PackedStringArray(["Timer", "Start the battle timer"]), "off")
