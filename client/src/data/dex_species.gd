class_name DexSpecies
extends RefCounted
## One Pokédex entry (species or forme), from Showdown's pokedex.json.

var id := ""
var name := ""
var num := 0
var base_species := ""
var forme := ""
var types := PackedStringArray()
## {"hp": 108, "atk": 130, "def": 95, "spa": 80, "spd": 85, "spe": 102}
var base_stats := {}
## {"0": "Sand Veil", "1": "...", "H": "Rough Skin", "S": "..."}
var abilities := {}
var weight_kg := 0.0
var tier := ""
## The full original entry, for fields not mapped above.
var raw := {}


static func from_dict(species_id: String, data: Dictionary) -> DexSpecies:
	var s := DexSpecies.new()
	s.id = species_id
	s.name = str(data.get("name", species_id))
	s.num = int(data.get("num", 0))
	s.base_species = str(data.get("baseSpecies", s.name))
	s.forme = str(data.get("forme", ""))
	s.types = PackedStringArray(data.get("types", []))
	s.base_stats = data.get("baseStats", {})
	s.abilities = data.get("abilities", {})
	s.weight_kg = float(data.get("weightkg", 0.0))
	s.tier = str(data.get("tier", ""))
	s.raw = data
	return s


## File name of the sprite on Showdown's sprite server, e.g. "rotom-wash".
func sprite_id() -> String:
	var base := Dex.species_id(base_species)
	return base if forme.is_empty() else base + "-" + Dex.species_id(forme)
