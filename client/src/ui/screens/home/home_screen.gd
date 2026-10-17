class_name HomeScreen
extends Control
## Home tab: quick battle and your running battles. The full lobby (format picker, challenges,
## ratings; design board "Lobby / Home") replaces this in #23.
## Keys: Ctrl+Enter battle, Esc cancel the search.

const MAX_WIDTH := 960

var _quick := QuickBattleCard.new()
var _battles := VBoxContainer.new()
var _margin := MarginContainer.new()


func _ready() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"AppBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	background.add_child(scroll)
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_margin)
	scroll.resized.connect(func() -> void:
		var side := maxi(16, int((scroll.size.x - MAX_WIDTH) / 2.0))
		_margin.add_theme_constant_override("margin_left", side)
		_margin.add_theme_constant_override("margin_right", side))
	for side in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 16)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_margin.add_child(column)
	column.add_child(_quick)
	_battles.add_theme_constant_override("separation", 8)
	column.add_child(_battles)

	EventBus.battle_started.connect(func(_b: BattleState) -> void: _refresh())
	EventBus.battle_attention_changed.connect(func(_b: BattleState) -> void: _refresh())
	EventBus.battle_ended.connect(func(_b: BattleState, _w: String) -> void: _refresh())
	EventBus.battle_updated.connect(func(_b: BattleState, msg: PSMessage) -> void:
		if msg.type in ["turn", "player"]:
			_refresh())
	EventBus.room_left.connect(func(_room: String) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	for child in _battles.get_children():
		child.queue_free()
	var running := Rooms.running_battles()
	if running.is_empty():
		_battles.add_child(EmptyState.section(tr("Your battles"),
			tr("No active battles. Battles you start or join show up here."), [tr("Find a battle"), _quick.battle]))
		return
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SectionPanel"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	panel.add_child(list)
	list.add_child(RichButton.label(tr("Your battles"), &"DockTitleLabel"))
	for battle in running:
		list.add_child(_battle_row(battle))
	_battles.add_child(panel)


func _battle_row(battle: BattleState) -> Control:
	var view := RunningBattleCard.describe(battle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 48
	var dot := StatusDot.new("color.accent.text" if battle.awaiting_choice else "color.text.muted", not battle.awaiting_choice)
	row.add_child(dot)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_child(RichButton.label(view["title"], &"DockTitleLabel"))
	var line := RichButton.label(view["line"], &"MutedLabel")
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(line)
	row.add_child(text)
	if battle.awaiting_choice:
		row.add_child(RichButton.label(tr("Your move"), &"AccentPillLabel"))
	var room_id := battle.room_id
	var open := StateCard.make_button(tr("Open"), &"SmallButton", func() -> void:
		EventBus.navigation_requested.emit(StringName("battle:" + room_id)))
	open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(open)
	return row


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		_quick.battle()
	elif key.keycode == KEY_ESCAPE and not key.ctrl_pressed and Rooms.is_searching():
		Rooms.cancel_search()
	else:
		return
	get_viewport().set_input_as_handled()
