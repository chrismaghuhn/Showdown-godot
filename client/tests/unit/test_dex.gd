extends "res://tests/test_case.gd"

const POKEDEX := {
	"garchomp": {"num": 445, "name": "Garchomp", "types": ["Dragon", "Ground"],
		"baseStats": {"hp": 108, "atk": 130, "def": 95, "spa": 80, "spd": 85, "spe": 102},
		"abilities": {"0": "Sand Veil", "H": "Rough Skin"}, "weightkg": 95, "tier": "UUBL"},
	"rotomwash": {"num": 479, "name": "Rotom-Wash", "baseSpecies": "Rotom", "forme": "Wash",
		"types": ["Electric", "Water"]},
	"mrmimegalar": {"num": 122, "name": "Mr. Mime-Galar", "baseSpecies": "Mr. Mime", "forme": "Galar",
		"types": ["Ice", "Psychic"]},
}
const MOVES := {
	"earthquake": {"num": 89, "name": "Earthquake", "type": "Ground", "category": "Physical",
		"basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "target": "allAdjacent"},
	"aerialace": {"num": 332, "name": "Aerial Ace", "type": "Flying", "category": "Physical",
		"basePower": 60, "accuracy": true, "pp": 20},
}
const ITEMS := {"leftovers": {"num": 234, "name": "Leftovers", "spritenum": 242}}
const ABILITIES := {"roughskin": {"num": 24, "name": "Rough Skin"}}


func _dex() -> Dex:
	var typechart: Dictionary = JsObjectParser.parse_exports(
		FileAccess.get_file_as_string("res://tests/fixtures/typechart.js"))
	return Dex.from_sources(POKEDEX, MOVES, ITEMS, ABILITIES, typechart)


func test_species_lookup_by_name_or_id() -> void:
	var dex := _dex()
	var chomp := dex.get_species("Garchomp")
	assert_true(chomp != null, "found by name")
	assert_true(dex.get_species("garchomp") == chomp, "found by id")
	assert_eq(chomp.types, PackedStringArray(["Dragon", "Ground"]), "types")
	assert_eq(chomp.base_stats["atk"], 130, "base stat")
	assert_eq(chomp.abilities["H"], "Rough Skin", "hidden ability")
	assert_eq(chomp.base_species, "Garchomp", "base species defaults to name")
	assert_true(dex.get_species("Missingno") == null, "unknown species")


func test_sprite_ids() -> void:
	var dex := _dex()
	assert_eq(dex.get_species("Garchomp").sprite_id(), "garchomp", "plain species")
	assert_eq(dex.get_species("Rotom-Wash").sprite_id(), "rotom-wash", "forme")
	assert_eq(dex.get_species("Mr. Mime-Galar").sprite_id(), "mrmime-galar", "punctuation removed")


func test_moves_items_abilities() -> void:
	var dex := _dex()
	var eq := dex.get_move("Earthquake")
	assert_eq(eq.type, "Ground", "move type")
	assert_eq(eq.category, "Physical", "category")
	assert_eq(eq.base_power, 100, "base power")
	assert_eq(eq.accuracy, 100, "accuracy")
	assert_eq(dex.get_move("Aerial Ace").accuracy, DexMove.ALWAYS_HITS, "never misses")
	assert_eq(dex.get_item("Leftovers").raw["spritenum"], 242, "item raw data")
	assert_eq(dex.get_ability("Rough Skin").name, "Rough Skin", "ability")


func test_type_names_skip_non_type_keys() -> void:
	var names := _dex().type_names
	assert_true("Fairy" in names and "Steel" in names, "real types")
	assert_true(not "prankster" in names and not "sandstorm" in names, "no special keys")


func test_effectiveness() -> void:
	var dex := _dex()
	assert_eq(dex.effectiveness("Ground", PackedStringArray(["Fire", "Flying"])), 0.0, "immune")
	assert_eq(dex.effectiveness("Fire", PackedStringArray(["Grass", "Steel"])), 4.0, "double weakness")
	assert_eq(dex.effectiveness("Water", PackedStringArray(["Dragon"])), 0.5, "resisted")
	assert_eq(dex.effectiveness("Ice", PackedStringArray(["Dragon", "Ground"])), 4.0, "ice vs garchomp")
	assert_eq(dex.effectiveness("Fighting", PackedStringArray(["Normal"])), 2.0, "super effective")
	assert_eq(dex.effectiveness("Normal", PackedStringArray(["Ghost"])), 0.0, "ghost immune to normal")
	assert_eq(dex.effectiveness("Fire", PackedStringArray(["Water", "Grass"])), 1.0, "cancels out")
	assert_eq(dex.effectiveness("Fire", PackedStringArray(["Unknown"])), 1.0, "unknown type neutral")


func test_cosmetic_formes_inherit_from_the_base_species() -> void:
	var pokedex := {
		"minior": {"num": 774, "name": "Minior", "baseForme": "Red", "types": ["Rock", "Flying"],
			"baseStats": {"hp": 60, "atk": 100, "def": 60, "spa": 100, "spd": 60, "spe": 120},
			"abilities": {"0": "Shields Down"}, "weightkg": 0.3, "tier": "ZU"},
		"miniororange": {"isCosmeticForme": true, "name": "Minior-Orange", "baseSpecies": "Minior",
			"forme": "Orange", "color": "Red"},
	}
	var dex := Dex.from_sources(pokedex, {}, {}, {}, {})
	var orange := dex.get_species("Minior-Orange")
	assert_eq(orange.name, "Minior-Orange", "own name")
	assert_eq(orange.forme, "Orange", "own forme")
	assert_eq(orange.types, PackedStringArray(["Rock", "Flying"]), "types from the base species")
	assert_eq(orange.base_stats["spe"], 120, "stats from the base species")
	assert_eq(orange.abilities["0"], "Shields Down", "abilities from the base species")
	assert_eq(orange.num, 774, "dex number from the base species")
	assert_eq(orange.sprite_id(), "minior-orange", "sprite of the cosmetic forme")
	assert_eq(dex.get_species("Minior").types, PackedStringArray(["Rock", "Flying"]), "base unchanged")
	assert_true(not orange.raw.has("cosmeticFormes"), "the base's forme lists aren't copied")


func test_cosmetic_formes_listed_only_by_their_base() -> void:
	var pokedex := {
		"furfrou": {"num": 676, "name": "Furfrou", "baseForme": "Natural", "types": ["Normal"],
			"baseStats": {"hp": 75, "atk": 80, "def": 60, "spa": 65, "spd": 90, "spe": 102},
			"abilities": {"0": "Fur Coat"}, "cosmeticFormes": ["Furfrou-La Reine", "Furfrou-Heart"]},
		"flabebe": {"num": 669, "name": "Flabébé", "types": ["Fairy"], "cosmeticFormes": ["Flabébé-Blue"]},
		"vivillonpolar": {"isCosmeticForme": true, "name": "Vivillon-Polar", "baseSpecies": "Vivillon",
			"forme": "Polar"},
	}
	var dex := Dex.from_sources(pokedex, {}, {}, {}, {})
	var reine := dex.get_species("Furfrou-La Reine")
	assert_true(reine != null, "listed forme exists")
	assert_eq(reine.name, "Furfrou-La Reine", "name")
	assert_eq(reine.forme, "La Reine", "forme")
	assert_eq(reine.types, PackedStringArray(["Normal"]), "types from the base species")
	assert_eq(reine.base_stats["spe"], 102, "stats from the base species")
	assert_eq(reine.sprite_id(), "furfrou-lareine", "sprite id")
	assert_eq(dex.get_species("Flabébé-Blue").sprite_id(), "flabebe-blue", "sprite id without accents")
	assert_true(dex.get_species("Flabébé") == dex.species["flabebe"], "Flabébé by name")
	var polar := dex.get_species("Vivillon-Polar")
	assert_true(polar != null and polar.types.is_empty(), "a forme whose base is missing still loads")
