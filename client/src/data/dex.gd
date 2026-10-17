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
		var entry: Dictionary = pokedex[id]
		# Cosmetic formes (Vivillon patterns, Minior colours …) only carry their name and
		# forme; types, stats and abilities come from the base species.
		if entry.get("isCosmeticForme", false):
			var base: Variant = pokedex.get(species_id(str(entry.get("baseSpecies", ""))))
			if base is Dictionary:
				entry = _cosmetic_entry(base, entry)
		dex.species[id] = DexSpecies.from_dict(id, entry)
	# Others (Unown letters, Furfrou trims, Flabébé colours …) are only listed by their base.
	for id: String in pokedex:
		var base: Dictionary = pokedex[id]
		for forme_name: Variant in base.get("cosmeticFormes", []):
			var forme_id := species_id(str(forme_name))
			if not dex.species.has(forme_id):
				var base_name := str(base.get("name", id))
				dex.species[forme_id] = DexSpecies.from_dict(forme_id, _cosmetic_entry(base, {
					"name": str(forme_name), "baseSpecies": base_name, "isCosmeticForme": true,
					"forme": str(forme_name).trim_prefix(base_name + "-"),
				}))
	for id: String in movedex:
		dex.moves[id] = DexMove.from_dict(id, movedex[id])
	for id: String in itemdex:
		dex.items[id] = DexEntry.from_dict(id, itemdex[id])
	for id: String in abilitydex:
		dex.abilities[id] = DexEntry.from_dict(id, abilitydex[id])
	dex._load_type_chart(typechart)
	return dex


## Species id as in Showdown's pokedex: "Flabébé-Blue" -> "flabebeblue" (toID alone would drop
## the "é"; usernames keep plain toID).
static func species_id(species_name: String) -> String:
	return PSParser.to_id(species_name.replace("é", "e"))


## A cosmetic forme's entry: the base species' data under the forme's own keys, without the
## base's list of formes.
static func _cosmetic_entry(base: Dictionary, forme: Dictionary) -> Dictionary:
	var entry := base.merged(forme, true)
	for key in ["otherFormes", "cosmeticFormes", "formeOrder", "baseForme"]:
		entry.erase(key)
	return entry


func get_species(name_or_id: String) -> DexSpecies:
	return species.get(species_id(name_or_id))


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
