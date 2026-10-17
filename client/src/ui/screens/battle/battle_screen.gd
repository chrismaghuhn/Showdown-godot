extends Control
## Battle screen, layout B "Desktop" (design canvas: "B · Desktop — choose move / waiting").
##
##   ┌ battlefield (header, stage, HUD cards, field chips) ┐┌ battle log ┐┌ sidebar slot ┐
##   └ choices (moves 1–4, switch Shift+1–6, tera, timer)  ┘└ chat       ┘└ plugin panels ┘
##
## Columns can be resized with the split handles; panels collapse from their header.
## Hotkeys: 1–4 moves, Shift+1–6 switch, Esc cancel the chosen action.

var battle: BattleState

var _builder := BattleLogBuilder.new()
var _request := {}
var _waiting := false
var _chosen := ""
var _tera := false
var _refresh_queued := false
var _timer_turn := -1
var _timer_total := -1
var _timer_seen := Vector2i(-2, -2)

# Battlefield
var _my_name := Label.new()
var _my_team := TeamStrip.new()
var _opp_name := Label.new()
var _opp_team := TeamStrip.new()
var _turn := Label.new()
var _format := Label.new()
var _stage := BattleStage.new()
var _opp_card := HudCard.new(false)
var _my_card := HudCard.new(true)
var _field_chips := HBoxContainer.new()
# Choices
var _choice_title := Label.new()
var _choice_note := Label.new()
var _tera_button := Button.new()
var _timer_button := Button.new()
var _cancel_button := Button.new()
var _forfeit_button := Button.new()
var _moves := GridContainer.new()
var _switch_caption := Label.new()
var _slots := GridContainer.new()
var _move_buttons: Array[MoveButton] = []
var _slot_buttons: Array[PokemonSlot] = []
# Right column and sidebar
var _log := BattleLogView.new()
var _chat := RichTextLabel.new()
var _chat_input := LineEdit.new()
var _right := VBoxContainer.new()
var _aside := VBoxContainer.new()
var _plugin_count := Label.new()
var _plugin_empty := Label.new()
var _forfeit_dialog := ConfirmationDialog.new()


func _ready() -> void:
	_build()
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_updated.connect(_on_battle_updated)
	EventBus.battle_request.connect(_on_battle_request)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.chat_message.connect(_on_chat_message)
	EventBus.plugin_panel_added.connect(_on_plugin_panel_added)
	EventBus.plugin_paused.connect(_on_plugin_paused)
	EventBus.room_left.connect(func(room_id: String) -> void:
		if battle != null and battle.room_id == room_id:
			_queue_refresh())
	EventBus.data_loaded.connect(func(_dex: Dex) -> void: _queue_refresh())
	for entry in Plugins.get_panel_entries(&"sidebar"):
		_add_plugin_panel(entry["plugin_id"], entry["control"])
	for plugin_id: String in Plugins.paused:
		_on_plugin_paused(plugin_id, Plugins.paused[plugin_id])
	var ticker := Timer.new()
	ticker.wait_time = 1.0
	ticker.autostart = true
	ticker.timeout.connect(_on_tick)
	add_child(ticker)
	if not Rooms.battles.is_empty():
		_on_battle_started(Rooms.battles.values().back())
	_refresh()


# --- Layout -------------------------------------------------------------------------------

func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"AppBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	background.add_child(margin)

	var outer := HSplitContainer.new()
	margin.add_child(outer)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(main)
	var inner := HSplitContainer.new()
	outer.add_child(inner)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_right)
	inner.add_child(_aside)

	main.add_child(_build_battlefield())
	main.add_child(_build_choices())
	_build_right_column()
	_build_sidebar()

	_forfeit_dialog.title = tr("Forfeit battle?")
	_forfeit_dialog.dialog_text = tr("You will lose this battle.")
	_forfeit_dialog.ok_button_text = tr("Forfeit")
	_forfeit_dialog.confirmed.connect(_forfeit)
	add_child(_forfeit_dialog)
	_update_column_widths()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_column_widths()


## Design: log column clamp(360, 25vw, 480), sidebar clamp(264, 16.5vw, 320).
func _update_column_widths() -> void:
	_right.custom_minimum_size.x = clampf(size.x * 0.25, 360, 480)
	_aside.custom_minimum_size.x = clampf(size.x * 0.165, 264, 320)
	if _slots != null and _slots.is_inside_tree():
		_slots.columns = clampi(int(_slots.size.x / 158.0), 1, 6)


func _build_battlefield() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DockPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var header := PanelContainer.new()
	header.theme_type_variation = &"BattleHeader"
	header.custom_minimum_size.y = 40
	column.add_child(header)
	var row := HBoxContainer.new()
	header.add_child(row)
	_my_name.theme_type_variation = &"DockTitleLabel"
	row.add_child(_my_name)
	row.add_child(_my_team)
	var left_space := Control.new()
	left_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_space)
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 0)
	_turn.theme_type_variation = &"HeadingLabel"
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_turn)
	_format.theme_type_variation = &"MutedLabel"
	_format.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_format)
	row.add_child(center)
	var right_space := Control.new()
	right_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_space)
	row.add_child(_opp_team)
	_opp_name.theme_type_variation = &"DockTitleLabel"
	row.add_child(_opp_name)

	var field := PanelContainer.new()
	field.theme_type_variation = &"FieldPanel"
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.clip_contents = true
	column.add_child(field)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_PASS
	field.add_child(layer)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_stage)
	_opp_card.position = Vector2(12, 12)
	layer.add_child(_opp_card)
	_my_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_my_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_my_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_my_card.offset_right = -12
	_my_card.offset_bottom = -12
	layer.add_child(_my_card)
	_field_chips.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_field_chips.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_field_chips.offset_right = -12
	_field_chips.offset_top = 12
	layer.add_child(_field_chips)
	return panel


func _build_choices() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ChoicePanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_choice_title.theme_type_variation = &"HeadingLabel"
	header.add_child(_choice_title)
	_choice_note.theme_type_variation = &"MutedLabel"
	header.add_child(_choice_note)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_tera_button.theme_type_variation = &"SmallButton"
	_tera_button.icon = Icons.get_icon("ui-tera")
	_tera_button.toggle_mode = true
	_tera_button.toggled.connect(func(on: bool) -> void: _tera = on)
	header.add_child(_tera_button)
	_timer_button.theme_type_variation = &"SmallButton"
	_timer_button.icon = Icons.get_icon("ui-timer")
	_timer_button.pressed.connect(_toggle_timer)
	header.add_child(_timer_button)
	_cancel_button.theme_type_variation = &"SmallButton"
	_cancel_button.text = tr("Cancel  (Esc)")
	_cancel_button.pressed.connect(_cancel_choice)
	header.add_child(_cancel_button)
	_forfeit_button.theme_type_variation = &"DangerButton"
	_forfeit_button.icon = Icons.get_icon("ui-forfeit")
	_forfeit_button.tooltip_text = tr("Forfeit battle")
	_forfeit_button.pressed.connect(func() -> void: _forfeit_dialog.popup_centered())
	header.add_child(_forfeit_button)

	_moves.columns = 4
	_moves.add_theme_constant_override("h_separation", 8)
	column.add_child(_moves)
	for i in 4:
		var button := MoveButton.new()
		button.pressed.connect(_choose_move.bind(i))
		_moves.add_child(button)
		_move_buttons.append(button)

	_switch_caption.text = tr("Switch")
	_switch_caption.uppercase = true
	_switch_caption.theme_type_variation = &"CapsLabel"
	column.add_child(_switch_caption)
	_slots.columns = 3
	_slots.add_theme_constant_override("h_separation", 8)
	_slots.add_theme_constant_override("v_separation", 8)
	_slots.resized.connect(_update_column_widths)
	column.add_child(_slots)
	for i in 6:
		var slot := PokemonSlot.new()
		slot.pressed.connect(_choose_switch.bind(i))
		_slots.add_child(slot)
		_slot_buttons.append(slot)
	return panel


func _build_right_column() -> void:
	var log_panel := DockPanel.new(tr("Battle log"))
	log_panel.set_vertical_expand(true)
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", 2)
	var full := Button.new()
	var compact := Button.new()
	for spec: Array in [[full, tr("Full"), false], [compact, tr("Compact"), true]]:
		var button: Button = spec[0]
		button.text = spec[1]
		button.theme_type_variation = &"SmallButton"
		button.toggle_mode = true
		button.button_pressed = spec[0] == full
		button.pressed.connect(func() -> void:
			_log.compact = spec[2]
			full.set_pressed_no_signal(not spec[2])
			compact.set_pressed_no_signal(spec[2]))
		detail.add_child(button)
	log_panel.header_extras.add_child(detail)
	log_panel.body.add_child(_log)
	_right.add_child(log_panel)

	var chat_panel := DockPanel.new(tr("Chat"), "ui-chat")
	chat_panel.custom_minimum_size.y = 212
	_chat.bbcode_enabled = true
	_chat.scroll_following = true
	_chat.selection_enabled = true
	_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var chat_margin := MarginContainer.new()
	chat_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top"]:
		chat_margin.add_theme_constant_override("margin_" + side, 12 if side != "top" else 8)
	chat_margin.add_child(_chat)
	chat_panel.body.add_child(chat_margin)
	var input_row := HBoxContainer.new()
	var input_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		input_margin.add_theme_constant_override("margin_" + side, 8)
	input_margin.add_child(input_row)
	chat_panel.body.add_child(input_margin)
	_chat_input.placeholder_text = tr("Chat message")
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(func(_t: String) -> void: _send_chat())
	input_row.add_child(_chat_input)
	var send := Button.new()
	send.icon = Icons.get_icon("ui-send")
	send.tooltip_text = tr("Send message")
	send.pressed.connect(_send_chat)
	input_row.add_child(send)
	_right.add_child(chat_panel)


func _build_sidebar() -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 28
	header.add_child(IconView.new("ui-plugin", "color.plugin.text"))
	var title := Label.new()
	title.text = tr("Sidebar slot")
	title.uppercase = true
	title.theme_type_variation = &"CapsLabel"
	header.add_child(title)
	_plugin_count.theme_type_variation = &"MutedLabel"
	header.add_child(_plugin_count)
	_aside.add_child(header)
	_plugin_empty.text = tr("No sidebar plugins enabled. Plugins can add panels here, e.g. a damage calculator.")
	_plugin_empty.theme_type_variation = &"MutedLabel"
	_plugin_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aside.add_child(_plugin_empty)
	_update_plugin_count()


func _add_plugin_panel(plugin_id: String, control: Control) -> void:
	var manifest := Plugins.get_manifest(plugin_id)
	var title := manifest.name if manifest != null else plugin_id
	var panel := DockPanel.new(title, "ui-plugin")
	var source := "%s %s · community plugin" % [plugin_id, manifest.version if manifest != null else ""]
	panel.set_plugin_source(source)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12 if side != "top" else 4)
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	margin.add_child(control)
	panel.body.add_child(margin)
	panel.set_meta("plugin_id", plugin_id)
	_aside.add_child(panel)
	# A disabled or paused plugin frees its control; its panel goes with it.
	control.tree_exiting.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
			_update_plugin_count.call_deferred())
	_remove_paused_box(plugin_id)
	_update_plugin_count()


## Design: "Damage Calc paused" in place of the plugin's panel.
func _on_plugin_paused(plugin_id: String, reason: String) -> void:
	_remove_paused_box(plugin_id)
	var manifest := Plugins.get_manifest(plugin_id)
	var title := manifest.name if manifest != null else plugin_id
	var box := ErrorBox.plugin(tr("%s paused") % title, tr("It caused an error: %s. The battle is not affected.") % reason, [
		[tr("Reload plugin"), func() -> void:
			_remove_paused_box(plugin_id)
			Plugins.reload(plugin_id)],
		[tr("Disable"), func() -> void:
			Plugins.set_enabled_in_settings(plugin_id, false)
			_remove_paused_box(plugin_id)],
	])
	box.set_meta("paused_plugin", plugin_id)
	var index := -1
	for child in _aside.get_children():
		if child.get_meta("plugin_id", "") == plugin_id:
			index = child.get_index()
	_aside.add_child(box)
	if index >= 0:
		_aside.move_child(box, index)
	_update_plugin_count()


func _remove_paused_box(plugin_id: String) -> void:
	for child in _aside.get_children():
		if child.get_meta("paused_plugin", "") == plugin_id:
			child.queue_free()
	_update_plugin_count.call_deferred()


func _update_plugin_count() -> void:
	var count := 0
	for child in _aside.get_children():
		if (child is DockPanel or child is ErrorBox) and not child.is_queued_for_deletion():
			count += 1
	_plugin_count.text = tr("%d plugins") % count if count != 1 else tr("1 plugin")
	_plugin_empty.visible = count == 0


# --- Events -------------------------------------------------------------------------------

func _on_battle_started(started: BattleState) -> void:
	# After a reconnect every battle comes back; keep showing the one that was on screen.
	if started.restored and battle != null and battle.room_id != started.room_id and not battle.ended:
		return
	battle = started
	_builder = BattleLogBuilder.new()
	_log.clear()
	_chat.clear()
	_request = {}
	_waiting = false
	_chosen = ""
	_tera = false
	_tera_button.set_pressed_no_signal(false)
	_queue_refresh()


func _on_battle_updated(updated: BattleState, msg: PSMessage) -> void:
	if updated != battle:
		return
	_builder.push(msg, battle)
	if msg.type == "turn" or msg.type == "upkeep":
		_waiting = false
	_queue_refresh()


func _on_battle_request(requested: BattleState, request: Dictionary) -> void:
	if requested != battle:
		return
	_request = request
	_waiting = request.get("wait", false)
	if not _waiting:
		_chosen = ""
		_tera = false
		_tera_button.set_pressed_no_signal(false)
	_queue_refresh()


func _on_battle_ended(ended: BattleState, _winner: String) -> void:
	if ended == battle:
		_queue_refresh()


func _on_plugin_panel_added(plugin_id: String, slot: StringName, control: Control) -> void:
	if slot == &"sidebar":
		_add_plugin_panel(plugin_id, control)


func _on_chat_message(room_id: String, user: String, text: String) -> void:
	if battle == null or room_id != battle.room_id:
		return
	_chat.append_text("[b]%s[/b] %s\n" % [BattleLogBuilder.esc(user), BattleLogBuilder.esc(text)])


func _on_tick() -> void:
	# A paused plugin may be reloaded from its toast; drop its box then.
	for child in _aside.get_children():
		var paused_id: String = child.get_meta("paused_plugin", "")
		if not paused_id.is_empty() and not Plugins.paused.has(paused_id):
			_remove_paused_box(paused_id)
	if battle == null or not battle.timer_on or _waiting or battle.ended:
		return
	_timer_turn = maxi(_timer_turn - 1, 0)
	_timer_total = maxi(_timer_total - 1, 0)
	_update_timer_button()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or battle == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var number := key.keycode - KEY_1
	if key.keycode == KEY_ESCAPE and _waiting:
		_cancel_choice()
	elif number >= 0 and number < 6 and key.shift_pressed:
		if not _slot_buttons[number].disabled and _slot_buttons[number].visible:
			_choose_switch(number)
	elif number >= 0 and number < 4 and not key.ctrl_pressed and not key.alt_pressed:
		if not _move_buttons[number].disabled and _move_buttons[number].visible:
			_choose_move(number)
	else:
		return
	get_viewport().set_input_as_handled()


# --- Choices ------------------------------------------------------------------------------

func _choose_move(index: int) -> void:
	var choice := "move %d" % (index + 1)
	if _tera:
		choice += " terastallize"
	_send_choice(choice)


func _choose_switch(index: int) -> void:
	if _request.get("teamPreview", false):
		_send_choice("team %d" % (index + 1))
	else:
		_send_choice("switch %d" % (index + 1))


func _send_choice(choice: String) -> void:
	if battle == null:
		return
	Connection.choose(battle.room_id, choice, int(_request.get("rqid", -1)))
	_chosen = choice
	_waiting = true
	_refresh()


func _cancel_choice() -> void:
	if battle == null or not _waiting:
		return
	Connection.send(battle.room_id, "/undo")
	_waiting = false
	_chosen = ""
	_refresh()


func _forfeit() -> void:
	if battle != null:
		Connection.send(battle.room_id, "/forfeit")


func _toggle_timer() -> void:
	if battle != null:
		Connection.send(battle.room_id, "/timer off" if battle.timer_on else "/timer on")


func _send_chat() -> void:
	var text := _chat_input.text.strip_edges()
	if battle == null or text.is_empty():
		return
	Connection.send(battle.room_id, text)
	_chat_input.clear()


# --- Rendering ----------------------------------------------------------------------------

func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	_log.append(_builder.take_new())
	if battle == null:
		_choice_title.text = tr("No battle yet")
		_choice_note.text = tr("Search for a battle from the console.")
		_set_controls_visible(false)
		return
	var dex := GameData.dex
	var my_id := battle.my_side if not battle.my_side.is_empty() else "p1"
	var opp_id := "p2" if my_id == "p1" else "p1"
	var mine := battle.side(my_id)
	var theirs := battle.side(opp_id)

	_my_name.text = mine.player_name
	_opp_name.text = theirs.player_name
	_turn.text = tr("Turn %d") % battle.turn if battle.turn > 0 else tr("Team preview")
	_format.text = battle.format
	_my_team.show_team(_team_order(mine), maxi(mine.team_size, 6), dex)
	_opp_team.show_team(theirs.pokemon.values(), theirs.team_size, dex)

	var my_active := mine.active_pokemon()
	var opp_active := theirs.active_pokemon()
	_show_on_stage("front", opp_active, false)
	_show_on_stage("back", my_active, true)
	_opp_card.show_pokemon(opp_active, theirs, battle, dex)
	_my_card.show_pokemon(my_active, mine, battle, dex)
	_opp_card.tooltip_builder = func() -> Control: return BattleTooltips.pokemon_tooltip(opp_active, false, GameData.dex, my_active)
	_my_card.tooltip_builder = func() -> Control: return BattleTooltips.pokemon_tooltip(my_active, true, GameData.dex, null)
	_refresh_field_chips()
	_refresh_choices(mine, my_active, opp_active, theirs)


func _show_on_stage(key: String, mon: BattlePokemon, back: bool) -> void:
	if mon == null or mon.fainted:
		_stage.clear_slot(key)
	else:
		_stage.set_slot(key, mon.species, back, mon.shiny)


## Own team in |request| order (the order the server uses for "switch N").
func _team_order(side: BattleSide) -> Array:
	var team: Array = []
	for entry: Variant in _request.get("side", {}).get("pokemon", []):
		var mon_name: String = BattleState.parse_ident(str(entry.get("ident", "")))["name"]
		if side.pokemon.has(mon_name):
			team.append(side.pokemon[mon_name])
	return team if not team.is_empty() else side.pokemon.values()


func _refresh_field_chips() -> void:
	for child in _field_chips.get_children():
		child.queue_free()
	if battle.weather.is_empty():
		_field_chips.add_child(ConditionChip.new(tr("No weather"), "weather-none", "", false, true))
	else:
		var weather_left := battle.weather_turns_left()
		_field_chips.add_child(ConditionChip.new(FieldConditions.weather_name(battle.weather),
			FieldConditions.weather_icon(battle.weather), "" if weather_left < 0 else str(weather_left)))
	var has_terrain := false
	for condition in battle.field_conditions:
		has_terrain = has_terrain or FieldConditions.is_terrain(condition)
		var count := str(battle.turns_left(int(battle.field_turns.get(condition, battle.turn))))
		_field_chips.add_child(ConditionChip.new(condition, FieldConditions.icon(condition), count))
	if not has_terrain:
		_field_chips.add_child(ConditionChip.new(tr("No terrain"), "terrain-none", "", false, true))


func _refresh_choices(mine: BattleSide, my_active: BattlePokemon, opp_active: BattlePokemon, theirs: BattleSide) -> void:
	var dex := GameData.dex
	var active_req: Dictionary = (_request.get("active", [{}]) as Array)[0] if not (_request.get("active", []) as Array).is_empty() else {}
	var force_switch: bool = not (_request.get("forceSwitch", []) as Array).is_empty()
	var team_preview: bool = _request.get("teamPreview", false)
	var has_request: bool = not _request.is_empty() and not _request.get("wait", false)
	var choosing: bool = has_request and not _waiting and not battle.ended
	_set_controls_visible(true)

	# Header
	if battle.ended:
		_choice_title.text = tr("%s won the battle!") % battle.winner if not battle.winner.is_empty() else tr("The battle ended in a tie.")
		_choice_note.text = ""
	elif _waiting or not has_request:
		_choice_title.text = tr("Waiting for %s…") % theirs.player_name
		_choice_note.text = _chosen_text(active_req, dex)
	elif team_preview:
		_choice_title.text = tr("Choose your lead")
		_choice_note.text = ""
	elif force_switch:
		_choice_title.text = tr("Choose a Pokémon to send in")
		_choice_note.text = ""
	else:
		_choice_title.text = tr("What will %s do?") % (my_active.name if my_active != null else "?")
		_choice_note.text = ""
	_cancel_button.visible = _waiting and not battle.ended and not _chosen.is_empty()
	_forfeit_button.disabled = battle.ended
	var tera_type := str(active_req.get("canTerastallize", ""))
	_tera_button.visible = not tera_type.is_empty() and not battle.ended
	_tera_button.text = tr("Tera %s") % tera_type
	_tera_button.disabled = not choosing or force_switch
	_update_timer_button()

	# Moves
	var moves: Array = active_req.get("moves", [])
	var show_moves := not team_preview and not moves.is_empty()
	_moves.visible = show_moves
	var target: DexSpecies = dex.get_species(opp_active.species) if dex != null and opp_active != null else null
	for i in 4:
		var button := _move_buttons[i]
		button.visible = i < moves.size()
		if not button.visible:
			continue
		var move: Dictionary = moves[i]
		var data: DexMove = dex.get_move(str(move.get("id", move.get("move", "")))) if dex != null else null
		button.disabled = false
		button.setup(str(move.get("move", "?")), data.type if data != null else "Normal",
			data.category if data != null else "", int(move.get("pp", 0)), int(move.get("maxpp", 0)), str(i + 1))
		if move.get("disabled", false):
			button.set_unavailable(tr("Disabled"))
		if not choosing or force_switch:
			button.disabled = true
		button.set_chosen(_chosen.begins_with("move %d" % (i + 1)))
		var pp_text := "%s/%s" % [move.get("pp", "?"), move.get("maxpp", "?")]
		var move_name := str(move.get("move", ""))
		var hotkey := str(i + 1)
		button.tooltip_builder = func() -> Control: return BattleTooltips.move_tooltip(move_name, GameData.dex, pp_text, hotkey, target)

	# Switches (own team in request order)
	var team: Array = _request.get("side", {}).get("pokemon", [])
	var trapped: bool = active_req.get("trapped", false) or active_req.get("maybeTrapped", false)
	_switch_caption.visible = not team.is_empty()
	_slots.visible = not team.is_empty()
	for i in 6:
		var slot := _slot_buttons[i]
		slot.visible = i < team.size()
		if not slot.visible:
			continue
		var mon_name: String = BattleState.parse_ident(str(team[i].get("ident", "")))["name"]
		var mon: BattlePokemon = mine.pokemon.get(mon_name)
		if mon == null:
			slot.visible = false
			continue
		var species: DexSpecies = dex.get_species(mon.species) if dex != null else null
		var tint := Themes.color("color.type.%s.bg" % species.types[0].to_lower()) if species != null else Themes.color("color.surface.hover")
		var can_switch: bool = choosing and not mon.active and not mon.fainted and (not trapped or force_switch)
		slot.show_pokemon(mon, true, tint, "Shift+%d" % (i + 1) if can_switch else "")
		slot.disabled = not (can_switch or (team_preview and choosing))
		slot.modulate.a = 0.6 if (_waiting and not mon.active) else 1.0
		var shown := mon
		slot.tooltip_builder = func() -> Control: return BattleTooltips.pokemon_tooltip(shown, true, GameData.dex, null)
	_update_column_widths()


func _chosen_text(active_req: Dictionary, dex: Dex) -> String:
	if _chosen.begins_with("move "):
		var index := _chosen.get_slice(" ", 1).to_int() - 1
		var moves: Array = active_req.get("moves", [])
		if index >= 0 and index < moves.size():
			return tr("You chose %s") % str(moves[index].get("move", ""))
	elif _chosen.begins_with("switch "):
		return tr("You chose to switch")
	return ""


func _update_timer_button() -> void:
	if battle == null:
		return
	var seen := Vector2i(battle.timer_turn_seconds, battle.timer_total_seconds)
	if seen != _timer_seen:
		_timer_seen = seen
		_timer_turn = battle.timer_turn_seconds
		_timer_total = battle.timer_total_seconds
	if battle.timer_on and _timer_turn >= 0:
		_timer_button.text = "%s / %s" % [_clock(_timer_turn), _clock(_timer_total)]
		_timer_button.tooltip_text = tr("Your time this turn / in total. Click to turn the timer off.")
	else:
		_timer_button.text = tr("Timer")
		_timer_button.tooltip_text = tr("Start the battle timer")
	_timer_button.disabled = battle.ended


static func _clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


## Shows or hides all choice controls; _refresh_choices() then hides what doesn't apply.
func _set_controls_visible(on: bool) -> void:
	for control: Control in [_tera_button, _timer_button, _forfeit_button, _cancel_button, _moves, _switch_caption, _slots]:
		control.visible = on
