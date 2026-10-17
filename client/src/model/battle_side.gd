class_name BattleSide
extends RefCounted
## One player's side of a battle (p1 .. p4).

var id := ""
var player_name := ""
var team_size := 0
## Nickname -> BattlePokemon, in the order they were first seen.
var pokemon := {}
## Active slot index -> BattlePokemon (or null). Singles uses slot 0 only.
var active: Array = []
## Side conditions: "Stealth Rock" -> {"layers": 1, "turn": <turn it started>}.
var conditions := {}


func _init(side_id := "") -> void:
	id = side_id


func get_or_add(nickname: String) -> BattlePokemon:
	if not pokemon.has(nickname):
		pokemon[nickname] = BattlePokemon.new(nickname)
	return pokemon[nickname]


func set_active(slot: int, mon: BattlePokemon) -> void:
	while active.size() <= slot:
		active.append(null)
	var previous: BattlePokemon = active[slot]
	if previous != null and previous != mon:
		previous.active = false
		previous.boosts.clear()
		previous.volatiles.clear()
	mon.active = true
	active[slot] = mon


func active_pokemon(slot := 0) -> BattlePokemon:
	return active[slot] if slot < active.size() else null


func add_condition(condition: String, turn: int) -> void:
	if conditions.has(condition):
		conditions[condition]["layers"] = int(conditions[condition]["layers"]) + 1
	else:
		conditions[condition] = {"layers": 1, "turn": turn}


func fainted_count() -> int:
	var count := 0
	for mon: BattlePokemon in pokemon.values():
		if mon.fainted:
			count += 1
	return count
