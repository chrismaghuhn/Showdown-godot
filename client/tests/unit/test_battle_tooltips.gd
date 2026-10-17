extends "res://tests/test_case.gd"
## BattleTooltips: move effectiveness and Pokémon types, also after terastallizing.

const POKEDEX := {
	"garchomp": {"num": 445, "name": "Garchomp", "types": ["Dragon", "Ground"],
		"baseStats": {"hp": 108, "atk": 130, "def": 95, "spa": 80, "spd": 85, "spe": 102},
		"abilities": {"0": "Sand Veil", "H": "Rough Skin"}},
}
const MOVES := {
	"icebeam": {"num": 58, "name": "Ice Beam", "type": "Ice", "category": "Special",
		"basePower": 90, "accuracy": 100, "pp": 10},
}


func _dex() -> Dex:
	var typechart: Dictionary = JsObjectParser.parse_exports(
		FileAccess.get_file_as_string("res://tests/fixtures/typechart.js"))
	return Dex.from_sources(POKEDEX, MOVES, {}, {}, typechart)


func _chomp(tera_type := "") -> BattlePokemon:
	var mon := BattlePokemon.new("Chomp")
	mon.species = "Garchomp"
	mon.tera_type = tera_type
	return mon


## Texts of the tooltip's labels (or only its type badges); frees the tooltip.
func _texts(tooltip: Control, badges_only := false) -> PackedStringArray:
	var texts := PackedStringArray()
	for label in tooltip.find_children("*", "Label", true, false):
		if not badges_only or label is TypeBadge:
			texts.append((label as Label).text)
	tooltip.free()
	return texts


func test_move_effectiveness_uses_tera_type() -> void:
	var dex := _dex()
	var plain := _texts(BattleTooltips.move_tooltip("Ice Beam", dex, "", "1", _chomp()))
	assert_true(plain.has("×4.0"), "×4 vs Dragon/Ground: %s" % [plain])
	var steel := _texts(BattleTooltips.move_tooltip("Ice Beam", dex, "", "1", _chomp("Steel")))
	assert_true(steel.has("×0.5"), "×0.5 vs Tera Steel: %s" % [steel])
	assert_true(steel.has("Not very effective vs Garchomp"), "verdict")
	var stellar := _texts(BattleTooltips.move_tooltip("Ice Beam", dex, "", "1", _chomp("Stellar")))
	assert_true(stellar.has("×4.0"), "Stellar keeps the original types: %s" % [stellar])


func test_pokemon_tooltip_shows_tera_type() -> void:
	var dex := _dex()
	var plain := _texts(BattleTooltips.pokemon_tooltip(_chomp(), false, dex, null), true)
	assert_eq(plain, PackedStringArray(["Dragon", "Ground"]), "species types")
	var steel := _texts(BattleTooltips.pokemon_tooltip(_chomp("Steel"), false, dex, null), true)
	assert_eq(steel, PackedStringArray(["Tera Steel"]), "Tera badge in place of the species types")
