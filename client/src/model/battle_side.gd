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
## Side conditions like "Stealth Rock", "Reflect".
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
	mon.active = true
	active[slot] = mon


func active_pokemon(slot := 0) -> BattlePokemon:
	return active[slot] if slot < active.size() else null
