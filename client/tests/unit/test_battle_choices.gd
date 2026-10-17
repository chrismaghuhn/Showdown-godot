extends "res://tests/test_case.gd"
## BattleChoices: the rules behind the battle screen's switch slots.


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

