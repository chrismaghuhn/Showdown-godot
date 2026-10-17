class_name BattleTooltips
extends RefCounted
## Builds the move and Pokémon tooltips of the battle screen (design: Components › Tooltip).
## Returned controls are shown inside the themed TooltipPanel via _make_custom_tooltip().

const STAT_ORDER := ["atk", "def", "spa", "spd", "spe"]


## target: the defending Pokémon (effectiveness uses its Tera type once it terastallized).
static func move_tooltip(move_name: String, dex: Dex, pp_text: String, hotkey: String, target: BattlePokemon) -> Control:
	var root := _root()
	var data: DexMove = dex.get_move(move_name) if dex != null else null
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(_label(data.name if data != null else move_name, &"HudNameLabel", true))
	if not hotkey.is_empty():
		head.add_child(_label(hotkey, &"KbdLabel"))
	if data == null:
		return root

	var info := HBoxContainer.new()
	root.add_child(info)
	info.add_child(TypeBadge.new(data.type))
	info.add_child(_label(data.category, &"SecondaryLabel", true))
	var contact := _label(_t("Contact") if data.flags.has("contact") else _t("No contact"), &"MutedLabel")
	contact.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	contact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(contact)

	var stats := _sunken_grid(3)
	root.add_child(stats.get_parent())
	_stat_cell(stats, _t("Power"), str(data.base_power) if data.base_power > 0 else "—")
	_stat_cell(stats, _t("Accuracy"), _t("Always hits") if data.accuracy == DexMove.ALWAYS_HITS else "%d%%" % data.accuracy)
	_stat_cell(stats, "PP", pp_text if not pp_text.is_empty() else str(data.pp))

	var target_species: DexSpecies = dex.get_species(target.species) if target != null else null
	var target_types := defending_types(target, target_species) if target != null else PackedStringArray()
	if not target_types.is_empty() and data.category != "Status":
		var multiplier := dex.effectiveness(data.type, target_types)
		var row := HBoxContainer.new()
		root.add_child(row)
		var verdict := _t("Neutral vs %s")
		var kind := &"VolatileChip"
		if multiplier == 0.0:
			verdict = _t("No effect on %s")
			kind = &"BoostDownChip"
		elif multiplier > 1.0:
			verdict = _t("Super effective vs %s")
			kind = &"BoostUpChip"
		elif multiplier < 1.0:
			verdict = _t("Not very effective vs %s")
			kind = &"BoostDownChip"
		row.add_child(_label("×" + String.num(multiplier), kind))
		row.add_child(_label(verdict % (target_species.name if target_species != null else target.species), &"SecondaryLabel", true))
	return root


## own: exact HP and stats from |request|; opponent: what is revealed plus stat ranges.
static func pokemon_tooltip(mon: BattlePokemon, own: bool, dex: Dex, my_active: BattlePokemon) -> Control:
	var root := _root()
	var species: DexSpecies = dex.get_species(mon.species) if dex != null else null
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(_label(mon.name, &"HudNameLabel", true))
	head.add_child(_label("Lv %d" % mon.level, &"MonoSmallLabel"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	# Terastallized: the Tera badge in place of the types; Stellar keeps them, so it goes next to them.
	if species != null and (mon.tera_type.is_empty() or mon.tera_type == "Stellar"):
		for type_name in species.types:
			head.add_child(TypeBadge.new(type_name))
	if not mon.tera_type.is_empty():
		var tera := TypeBadge.new(mon.tera_type)
		tera.text = _t("Tera %s") % mon.tera_type
		head.add_child(tera)

	var hp_row := HBoxContainer.new()
	root.add_child(hp_row)
	hp_row.add_child(_label("%d%%" % roundi(mon.hp_percent()), &"MonoLabel"))
	if own:
		hp_row.add_child(_label("%d/%d HP" % [mon.hp, mon.max_hp], &"MutedLabel"))
	elif species != null:
		var hp_range := StatCalc.stat_range("hp", int(species.base_stats.get("hp", 1)), mon.level)
		hp_row.add_child(_label("≈ %d–%d HP" % [roundi(hp_range.x * mon.hp_percent() / 100.0), roundi(hp_range.y * mon.hp_percent() / 100.0)], &"MutedLabel"))
	var bar := HPBar.new(mon.hp_percent())
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(bar)

	var facts := GridContainer.new()
	facts.columns = 2
	root.add_child(facts)
	_fact(facts, _t("Ability"), _ability_text(mon, species, dex))
	_fact(facts, _t("Item"), _entry_name(dex, mon.item, true) if not mon.item.is_empty() else _t("Unknown"))
	_fact(facts, _t("Tera"), (_t("Tera %s") % mon.tera_type) if not mon.tera_type.is_empty() else (mon.tera_option if own and not mon.tera_option.is_empty() else _t("Not used")))
	var moves: PackedStringArray = mon.revealed_moves
	if own and not mon.moves.is_empty():
		moves = PackedStringArray()
		for move_id in mon.moves:
			var move: DexMove = dex.get_move(move_id) if dex != null else null
			moves.append(move.name if move != null else move_id)
	_fact(facts, _t("Moves"), ", ".join(moves) if not moves.is_empty() else _t("None revealed"))

	if species != null:
		var stats := _sunken_grid(3)
		root.add_child(stats.get_parent())
		for stat_id: String in STAT_ORDER:
			var value := ""
			if own and mon.stats.has(stat_id):
				value = str(int(mon.stats[stat_id]))
			else:
				var r := StatCalc.stat_range(stat_id, int(species.base_stats.get(stat_id, 1)), mon.level)
				value = "%d–%d" % [r.x, r.y]
			stats.add_child(_label(BoostChip.STAT_LABELS.get(stat_id, stat_id), &"CapsLabel", true))
			stats.add_child(_label(value, &"MonoLabel"))
			var boost := int(mon.boosts.get(stat_id, 0))
			stats.add_child(BoostChip.new(stat_id, boost) if boost != 0 else Control.new())
		if not own and my_active != null and my_active.stats.has("spe"):
			root.add_child(_label(_speed_verdict(mon, species, my_active), &"SecondaryLabel", true))
	return root


## The types `mon` defends with: its Tera type once terastallized, except Stellar, which keeps
## the original types. Empty when neither is known (species not in the Dex).
static func defending_types(mon: BattlePokemon, species: DexSpecies) -> PackedStringArray:
	if not mon.tera_type.is_empty() and mon.tera_type != "Stellar":
		return PackedStringArray([mon.tera_type])
	return species.types if species != null else PackedStringArray()


static func _speed_verdict(opponent: BattlePokemon, species: DexSpecies, mine: BattlePokemon) -> String:
	var my_speed := int(mine.stats["spe"]) * StatCalc.boost_multiplier(int(mine.boosts.get("spe", 0)))
	var r := StatCalc.stat_range("spe", int(species.base_stats.get("spe", 1)), opponent.level)
	var m := StatCalc.boost_multiplier(int(opponent.boosts.get("spe", 0)))
	if my_speed > r.y * m:
		return _t("%s is faster (%d)") % [mine.name, roundi(my_speed)]
	if my_speed < r.x * m:
		return _t("%s is slower (%d)") % [mine.name, roundi(my_speed)]
	return _t("%s (%d) may be faster or slower") % [mine.name, roundi(my_speed)]


static func _ability_text(mon: BattlePokemon, species: DexSpecies, dex: Dex) -> String:
	if not mon.ability.is_empty():
		return _entry_name(dex, mon.ability, false)
	if species == null:
		return _t("Unknown")
	return " / ".join(PackedStringArray(species.abilities.values()))


static func _entry_name(dex: Dex, id_or_name: String, is_item: bool) -> String:
	if dex == null:
		return id_or_name
	var entry: DexEntry = dex.get_item(id_or_name) if is_item else dex.get_ability(id_or_name)
	return entry.name if entry != null else id_or_name


static func _root() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.custom_minimum_size.x = 300
	root.add_theme_constant_override("separation", 8)
	return root


static func _sunken_grid(columns: int) -> GridContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SunkenPanel"
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 12)
	panel.add_child(grid)
	return grid


static func _stat_cell(grid: GridContainer, caption: String, value: String) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 0)
	cell.add_child(_label(caption, &"CapsLabel", true))
	cell.add_child(_label(value, &"MonoLabel"))
	grid.add_child(cell)


static func _fact(grid: GridContainer, caption: String, value: String) -> void:
	grid.add_child(_label(caption, &"MutedLabel"))
	var label := _label(value, &"")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 220
	grid.add_child(label)


static func _label(text: String, variation: StringName, uppercase_caps := false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.uppercase = uppercase_caps and variation == &"CapsLabel"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


static func _t(text: String) -> String:
	return TranslationServer.translate(text)
