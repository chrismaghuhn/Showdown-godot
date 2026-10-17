extends "res://tests/test_case.gd"
## HudCard and HPBar: what the card shows after each refresh.


func _mon(nickname: String, condition: String) -> BattlePokemon:
	var mon := BattlePokemon.new(nickname)
	mon.species = nickname
	mon.apply_condition(condition)
	return mon


## Tweens only run while the tree processes frames: step the bar's tween by hand.
func _finish_tween(bar: HPBar) -> void:
	if bar._tween != null and bar._tween.is_valid():
		bar._tween.custom_step(10.0)


func test_set_instant_stops_running_animation() -> void:
	var reduce_motion: bool = Themes.reduce_motion
	Themes.reduce_motion = false
	var bar := HPBar.new()
	Engine.get_main_loop().root.add_child(bar)
	bar.animate_to(30.0)
	assert_true(bar._tween != null and bar._tween.is_running(), "animating")
	bar.set_instant(80.0)
	assert_true(not bar._tween.is_valid(), "tween killed")
	_finish_tween(bar)
	assert_eq(bar.percent, 80.0, "keeps the assigned value")
	bar.free()
	Themes.reduce_motion = reduce_motion


func test_switch_during_hp_animation_shows_new_pokemon() -> void:
	var reduce_motion: bool = Themes.reduce_motion
	Themes.reduce_motion = false
	var card := HudCard.new(false)
	Engine.get_main_loop().root.add_child(card)
	var side := BattleSide.new("p2")
	var battle := BattleState.new("battle-test")
	var hurt := _mon("Garchomp", "100/100")
	card.show_pokemon(hurt, side, battle, null)
	hurt.apply_condition("30/100")
	card.show_pokemon(hurt, side, battle, null)  # starts draining to 30 %
	card.show_pokemon(_mon("Gholdengo", "100/100"), side, battle, null)  # forced switch, still draining
	_finish_tween(card._bar)
	assert_eq(card._bar.percent, 100.0, "new Pokémon's HP")
	assert_eq(card._hp.text, "100%", "HP label")
	var fainting := _mon("Corviknight", "100/100")
	card.show_pokemon(fainting, side, battle, null)
	fainting.apply_condition("40/100")
	card.show_pokemon(fainting, side, battle, null)
	fainting.apply_condition("0 fnt")
	card.show_pokemon(fainting, side, battle, null)
	_finish_tween(card._bar)
	assert_eq(card._bar.percent, 0.0, "fainted")
	card.free()
	Themes.reduce_motion = reduce_motion


func test_condition_row_hides_with_the_last_condition() -> void:
	var card := HudCard.new(true)
	var side := BattleSide.new("p1")
	var battle := BattleState.new("battle-test")
	var mon := _mon("Garchomp", "100/100")
	side.conditions["Reflect"] = {"layers": 1, "turn": 0}
	mon.boosts["atk"] = 2
	card.show_pokemon(mon, side, battle, null)
	assert_true(card._separator.visible, "separator with a condition")
	side.conditions.clear()
	mon.boosts.clear()
	card.show_pokemon(mon, side, battle, null)
	assert_true(not card._separator.visible, "separator hidden in the same refresh")
	assert_true(not card._conditions.visible, "row hidden")
	assert_eq(card._conditions.get_child_count(), 0, "no chips left")
	assert_eq(card._boosts.get_child_count(), 0, "no boost chips left")
	card.free()


func test_tailwind_chip_counts_four_turns() -> void:
	var card := HudCard.new(true)
	Engine.get_main_loop().root.add_child(card)
	var battle := BattleState.new("battle-test")
	for line in ["|gen|9", "|turn|3", "|switch|p1a: Corv|Corviknight|100/100", "|-sidestart|p1: Ash|move: Tailwind"]:
		battle.apply(PSParser.parse_line("battle-test", line))
	var side := battle.side("p1")
	card.show_pokemon(side.active_pokemon(), side, battle, null)
	var chip: ConditionChip = card._conditions.get_child(0)
	assert_eq(chip._label.text, "Tailwind", "Tailwind chip")
	assert_eq(chip._count.text, "4", "Tailwind lasts 4 turns")
	card.free()
