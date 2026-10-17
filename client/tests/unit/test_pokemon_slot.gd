extends "res://tests/test_case.gd"
## PokemonSlot: how a team slot looks for healthy, fainted and revivable Pokémon.


func test_revivable_fainted_slot_does_not_look_disabled() -> void:
	var mon := BattlePokemon.new("Gholdengo")
	mon.species = "Gholdengo"
	mon.apply_condition("0 fnt")
	var slot := PokemonSlot.new()
	slot.show_pokemon(mon, true, Color.GOLD)
	assert_eq(slot._name.theme_type_variation, &"SlotNameLabelDisabled", "fainted")
	slot.show_pokemon(mon, true, Color.GOLD, "Shift+3", true)
	assert_eq(slot._name.theme_type_variation, &"SlotNameLabel", "Revival Blessing can pick it")
	assert_eq(slot._meta.text, "Fainted", "still says fainted")
	slot.free()
