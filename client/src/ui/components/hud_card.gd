class_name HudCard
extends PanelContainer
## HUD card of an active Pokémon (design: B · Desktop): name, level or species, types (or Tera),
## animated HP bar with the number counting along, status, boosts, and the side's conditions
## plus volatiles. Own Pokémon show exact HP, opponents show %. Hover for the full tooltip.

## Returns the tooltip Control; set by the battle screen.
var tooltip_builder: Callable

var _name := Label.new()
var _sub := Label.new()
var _types := HBoxContainer.new()
var _bar := HPBar.new()
var _hp := Label.new()
var _status := StatusBadge.new()
var _boosts := HBoxContainer.new()
var _conditions := HFlowContainer.new()
var _separator := HSeparator.new()
var _own := false
var _mon: BattlePokemon
var _shown_key := ""


func _init(own := false) -> void:
	_own = own
	theme_type_variation = &"HudCard"
	custom_minimum_size.x = 300 if own else 284
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	_name.theme_type_variation = &"HudNameLabel"
	top.add_child(_name)
	_sub.theme_type_variation = &"MutedLabel" if own else &"MonoSmallLabel"
	top.add_child(_sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_types.add_theme_constant_override("separation", 4)
	top.add_child(_types)

	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.percent_changed.connect(_on_bar_changed)
	column.add_child(_bar)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	column.add_child(stats)
	_hp.theme_type_variation = &"MonoLabel"
	stats.add_child(_hp)
	stats.add_child(_status)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(spacer2)
	_boosts.add_theme_constant_override("separation", 4)
	stats.add_child(_boosts)

	column.add_child(_separator)
	_conditions.add_theme_constant_override("h_separation", 4)
	_conditions.add_theme_constant_override("v_separation", 4)
	column.add_child(_conditions)


func show_pokemon(mon: BattlePokemon, side: BattleSide, battle: BattleState, dex: Dex) -> void:
	_mon = mon
	visible = mon != null
	if mon == null:
		return
	var key := side.id + ":" + mon.name
	_name.text = mon.name
	_sub.text = mon.species if _own else "Lv %d" % mon.level
	_sub.visible = not _own or mon.species != mon.name

	for child in _types.get_children():
		child.queue_free()
	if not mon.tera_type.is_empty():
		var tera := TypeBadge.new(mon.tera_type)
		tera.text = tr("Tera %s") % mon.tera_type
		_types.add_child(tera)
	else:
		var species: DexSpecies = dex.get_species(mon.species) if dex != null else null
		if species != null:
			for type_name in species.types:
				_types.add_child(TypeBadge.new(type_name))

	# Animate HP changes of the same Pokémon; jump when a different one comes in.
	if mon.fainted:
		_bar.percent = 0.0
	elif key == _shown_key:
		_bar.animate_to(mon.hp_percent())
	else:
		_bar.percent = mon.hp_percent()
	_shown_key = key
	_on_bar_changed(_bar.percent)

	_status.visible = not mon.status.is_empty()
	if _status.visible:
		_status.status = mon.status
	for child in _boosts.get_children():
		child.queue_free()
	for stat: String in mon.boosts:
		if int(mon.boosts[stat]) != 0:
			_boosts.add_child(BoostChip.new(stat, int(mon.boosts[stat])))

	for child in _conditions.get_children():
		child.queue_free()
	for volatile: String in mon.volatiles:
		var chip := Label.new()
		chip.text = volatile
		chip.theme_type_variation = &"VolatileChip"
		_conditions.add_child(chip)
	for condition: String in side.conditions:
		var info: Dictionary = side.conditions[condition]
		var count := ""
		if condition in FieldConditions.LAYERED:
			count = "×%d" % int(info["layers"])
		elif condition in FieldConditions.TIMED:
			count = str(battle.turns_left(int(info["turn"])))
		_conditions.add_child(ConditionChip.new(condition, FieldConditions.icon(condition), count, true))
	var has_conditions := _conditions.get_child_count() > 0
	_separator.visible = has_conditions
	_conditions.visible = has_conditions
	tooltip_text = "%s (%s)" % [mon.name, mon.species]


func _on_bar_changed(value: float) -> void:
	if _mon == null:
		return
	if _mon.fainted:
		_hp.text = tr("Fainted")
	elif _own:
		var hp_now := roundi(value * _mon.max_hp / 100.0) if not is_equal_approx(value, _mon.hp_percent()) else _mon.hp
		_hp.text = "%d/%d" % [hp_now, _mon.max_hp]
	else:
		_hp.text = "%d%%" % roundi(value)


func _make_custom_tooltip(_for_text: String) -> Object:
	return tooltip_builder.call() if tooltip_builder.is_valid() and _mon != null else null
