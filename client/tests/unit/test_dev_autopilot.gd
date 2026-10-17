extends "res://tests/test_case.gd"
## The dev-autopilot plugin (tools/e2e_battle.sh): which choices it picks from at random.
## Its script lives outside res:// (loaded with --plugins-dir), like in test_scripts_compile.


func _autopilot() -> GDScript:
	var dir := ProjectSettings.globalize_path("res://").path_join("../plugins/dev-autopilot").simplify_path()
	return load(dir.path_join("main.gd"))


## Our lead Pawmot with a healthy and a fainted Pokémon on the bench.
func _request(extra: Dictionary) -> Dictionary:
	var request := {"rqid": 9, "side": {"id": "p1", "name": "Ash", "pokemon": [
		{"ident": "p1: Pawmot", "details": "Pawmot, L84, F", "condition": "250/250", "active": true},
		{"ident": "p1: Garchomp", "details": "Garchomp, L79, M", "condition": "300/300", "active": false},
		{"ident": "p1: Gholdengo", "details": "Gholdengo, L80", "condition": "0 fnt", "active": false},
	]}}
	request.merge(extra)
	return request


func test_revival_blessing_picks_the_fainted_pokemon() -> void:
	var request := _request({"forceSwitch": [true]})
	request["side"]["pokemon"][0]["reviving"] = true
	assert_eq(_autopilot().legal_choices(request), PackedStringArray(["switch 3"]), "only the fainted one")


func test_moves_first_and_switches_otherwise() -> void:
	var autopilot := _autopilot()
	var moves := [{"move": "Tackle", "pp": 35}, {"move": "Thunderbolt", "pp": 0}, {"move": "Nuzzle", "pp": 20, "disabled": true}]
	assert_eq(autopilot.legal_choices(_request({"active": [{"moves": moves}]})), PackedStringArray(["move 1"]), "usable moves")
	assert_eq(autopilot.legal_choices(_request({"forceSwitch": [true]})), PackedStringArray(["switch 2"]), "forced switch")
	var no_moves := [{"move": "Tackle", "pp": 0}]
	assert_eq(autopilot.legal_choices(_request({"active": [{"moves": no_moves, "maybeTrapped": true}]})),
		PackedStringArray(["switch 2"]), "no usable move: switch, also when maybe trapped")
