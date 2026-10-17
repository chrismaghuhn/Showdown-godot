class_name LobbyBattleCard
extends PanelContainer
## One running battle in the lobby's "Your battles" (design: "Lobby / Home"): opponent and
## rating, "Your move", format, turn and time left, both active Pokémon with HP, who has how
## many Pokémon left, and Open (Ctrl+N, the battle's tab).

signal open_requested(room_id: String)

var room_id := ""


func _init(battle: BattleState, tab_number := 0) -> void:
	room_id = battle.room_id
	theme_type_variation = &"BattleCardActive" if battle.awaiting_choice else &"BattleCard"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var mine := battle.my_side if not battle.my_side.is_empty() else "p1"
	var theirs := "p2" if mine == "p1" else "p1"
	var head := HBoxContainer.new()
	var opponent := battle.opponent_name()
	head.add_child(RichButton.label(tr("vs %s") % opponent if not opponent.is_empty() else tr("Battle"), &"HeadingLabel"))
	if battle.side(theirs).rating > 0:
		head.add_child(RichButton.label(str(battle.side(theirs).rating), &"TabMetaLabel"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if battle.awaiting_choice:
		var pill := PanelContainer.new()
		pill.theme_type_variation = &"AccentPill"
		var pill_row := HBoxContainer.new()
		pill_row.add_child(StatusDot.new("color.accent.text", false, 7.0))
		pill_row.add_child(RichButton.label(tr("Your move"), &"AccentPillLabel"))
		pill.add_child(pill_row)
		head.add_child(pill)
	column.add_child(head)

	var meta := HBoxContainer.new()
	meta.add_child(RichButton.label(battle.display_format(), &"FormatChip"))
	if battle.turn > 0:
		meta.add_child(RichButton.label(tr("Turn %d") % battle.turn, &"MutedLabel"))
	if battle.timer_on and battle.timer_turn_seconds >= 0:
		meta.add_child(RichButton.label("·", &"MutedLabel"))
		meta.add_child(IconView.new("ui-timer", "color.text.muted"))
		meta.add_child(RichButton.label(tr("%d:%02d left") % [battle.timer_turn_seconds / 60, battle.timer_turn_seconds % 60], &"MutedLabel"))
	column.add_child(meta)

	var actives := HBoxContainer.new()
	actives.add_theme_constant_override("separation", 8)
	actives.add_child(_active(battle.side(mine).active_pokemon()))
	var versus := RichButton.label(tr("vs"), &"MutedLabel")
	versus.custom_minimum_size.x = 20
	versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actives.add_child(versus)
	actives.add_child(_active(battle.side(theirs).active_pokemon()))
	column.add_child(actives)

	var foot := HBoxContainer.new()
	var my_left := _left(battle.side(mine))
	var their_left := _left(battle.side(theirs))
	foot.add_child(_dots(battle.side(mine), my_left))
	foot.add_child(RichButton.label("%d – %d" % [my_left, their_left], &"MutedLabel"))
	foot.add_child(_dots(battle.side(theirs), their_left))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var open := RichButton.new(&"SmallPrimaryButton" if battle.awaiting_choice else &"SmallButton", 8, 4)
	open.custom_minimum_size.y = 28
	open.add(RichButton.label(tr("Open"), &"OnAccentLabel" if battle.awaiting_choice else &"DockTitleLabel"))
	if tab_number > 0 and tab_number <= 9:
		open.add(RichButton.kbd("Ctrl+%d" % tab_number, battle.awaiting_choice))
	open.pressed.connect(func() -> void: open_requested.emit(room_id))
	foot.add_child(open)
	column.add_child(foot)


## Pokémon left: the team size minus the fainted ones (6 until |teamsize| arrives).
static func _left(side: BattleSide) -> int:
	return maxi((side.team_size if side.team_size > 0 else 6) - side.fainted_count(), 0)


func _dots(side: BattleSide, left: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var total := side.team_size if side.team_size > 0 else 6
	for i in total:
		row.add_child(StatusDot.new("color.text.secondary" if i < left else "color.text.disabled", i >= left))
	row.tooltip_text = tr("%d of %d left") % [left, total]
	return row


func _active(mon: BattlePokemon) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mon == null:
		row.add_child(RichButton.label("–", &"MutedLabel"))
		return row
	var mini := PanelContainer.new()
	mini.theme_type_variation = &"MiniSprite"
	mini.custom_minimum_size = Vector2(28, 28)
	var initials := RichButton.label(mon.species.left(2), &"MiniSpriteLabel")
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mini.add_child(initials)
	row.add_child(mini)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := HBoxContainer.new()
	var name := RichButton.label(mon.species, &"SmallBoldLabel")
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.custom_minimum_size.x = 40
	line.add_child(name)
	if mon.level != 100:
		line.add_child(RichButton.label("L%d" % mon.level, &"TabMetaLabel"))
	line.add_child(RichButton.label("%d%%" % roundi(mon.hp_percent()), &"MonoSmallLabel"))
	text.add_child(line)
	var bar := HPBar.new(mon.hp_percent())
	text.add_child(bar)
	row.add_child(text)
	return row
