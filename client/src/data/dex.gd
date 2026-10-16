class_name Dex
extends RefCounted
## Read-only game data: species, moves, items, abilities and the type chart.
##
## Pure: built from already-parsed dictionaries, no network or file access.
## Lookups accept names or ids ("Rotom-Wash", "rotomwash").

## species id -> DexSpecies
var species := {}
## move id -> DexMove
var moves := {}
## item id -> DexEntry
var items := {}
## ability id -> DexEntry
var abilities := {}
## Type names as used in the data, e.g. "Fire", sorted.
var type_names := PackedStringArray()

## defending type name -> {attacking type name -> multiplier}
var _type_chart := {}


## Builds a Dex from Showdown's pokedex, moves, items, abilities and typechart data.
static func from_sources(pokedex: Dictionary, movedex: Dictionary, itemdex: Dictionary,
		abilitydex: Dictionary, typechart: Dictionary) -> Dex:
	var dex := Dex.new()
	for id: String in pokedex:
		dex.species[id] = DexSpecies.from_dict(id, pokedex[id])
	for id: String in movedex:
		dex.moves[id] = DexMove.from_dict(id, movedex[id])
	for id: String in itemdex:
		dex.items[id] = DexEntry.from_dict(id, itemdex[id])
	for id: String in abilitydex:
		dex.abilities[id] = DexEntry.from_dict(id, abilitydex[id])
	dex._load_type_chart(typechart)
	return dex


func get_species(name_or_id: String) -> DexSpecies:
	return species.get(PSParser.to_id(name_or_id))


func get_move(name_or_id: String) -> DexMove:
	return moves.get(PSParser.to_id(name_or_id))


func get_item(name_or_id: String) -> DexEntry:
	return items.get(PSParser.to_id(name_or_id))


func get_ability(name_or_id: String) -> DexEntry:
	return abilities.get(PSParser.to_id(name_or_id))


## Damage multiplier of an attacking type against one or two defending types:
## 0, 0.25, 0.5, 1, 2 or 4. Unknown types count as neutral.
func effectiveness(attack_type: String, defend_types: PackedStringArray) -> float:
	var multiplier := 1.0
	for defend in defend_types:
		var chart: Dictionary = _type_chart.get(defend, {})
		multiplier *= float(chart.get(attack_type, 1.0))
	return multiplier


## Showdown's damageTaken codes: 0 = neutral, 1 = weak (x2), 2 = resists (x0.5), 3 = immune.
## The table also contains non-type keys ("prankster", "sandstorm", "par") which are skipped.
func _load_type_chart(typechart: Dictionary) -> void:
	const MULTIPLIERS := {0: 1.0, 1: 2.0, 2: 0.5, 3: 0.0}
	var names := {}
	for id: String in typechart:
		var taken: Dictionary = typechart[id].get("damageTaken", {})
		for attack: String in taken:
			if attack[0] == attack[0].to_upper():
				names[attack] = true
	type_names = PackedStringArray(names.keys())
	type_names.sort()
	for defend_name in type_names:
		var entry: Variant = typechart.get(PSParser.to_id(defend_name))
		if not entry is Dictionary:
			continue
		var chart := {}
		var taken: Dictionary = entry.get("damageTaken", {})
		for attack: String in taken:
			if names.has(attack):
				chart[attack] = MULTIPLIERS.get(int(taken[attack]), 1.0)
		_type_chart[defend_name] = chart
