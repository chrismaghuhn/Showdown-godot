class_name QuickBattleCard
extends PanelContainer
## "Quick battle · Same as last time" (design: start screen): format, team and "Battle!"
## (Ctrl+Enter). In v0.1 there's no teambuilder, so only formats where the server provides the
## team (Random Battles) are offered. While searching, the button cancels the search.

const DEFAULT_FORMAT := "gen9randombattle"

var _format := OptionButton.new()
var _battle := RichButton.new(&"PrimaryButton", 16, 8)
var _battle_text := RichButton.label("", &"DockTitleLabel")
var _battle_kbd := RichButton.kbd("Ctrl+Enter", true)
var _status := RichButton.label("", &"MutedLabel")
var _search_started_msec := -1


func _init() -> void:
	theme_type_variation = &"SectionPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var head := HBoxContainer.new()
	head.add_child(RichButton.label(tr("Quick battle"), &"CardTitleLabel"))
	head.add_child(RichButton.label(tr("Same as last time"), &"MutedLabel"))
	column.add_child(head)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	column.add_child(fields)
	_format.custom_minimum_size = Vector2(212, 40)
	_format.fit_to_longest_item = false
	_format.clip_text = true
	_format.item_selected.connect(func(index: int) -> void: _remember(index))
	fields.add_child(_field(tr("Format"), _format))
	var team := Button.new()
	team.text = tr("Team from the server · no team needed")
	team.disabled = true
	team.alignment = HORIZONTAL_ALIGNMENT_LEFT
	team.custom_minimum_size.y = 40
	team.tooltip_text = tr("Random Battles bring their own team. Building teams comes with the Teambuilder.")
	var team_field := _field(tr("Team"), team)
	team_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(team_field)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var random := StateCard.make_button(tr("Random Battle · no team needed"), &"SmallGhostButton", func() -> void:
		_select(DEFAULT_FORMAT))
	random.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(random)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(_status)
	_battle.custom_minimum_size.y = 40
	_battle.add(_battle_text)
	_battle.add(_battle_kbd)
	_battle.pressed.connect(battle)
	actions.add_child(_battle)


func _ready() -> void:
	EventBus.formats_changed.connect(_fill_formats)
	EventBus.search_changed.connect(func(_s: PackedStringArray, _g: Dictionary) -> void: _refresh())
	EventBus.connection_state_changed.connect(func(_s: int) -> void: _refresh())
	var ticker := Timer.new()
	ticker.wait_time = 1.0
	ticker.autostart = true
	ticker.timeout.connect(_refresh)
	add_child(ticker)
	_fill_formats()
	_refresh()


## "Battle!" - or cancels the running search.
func battle() -> void:
	if Rooms.is_searching():
		Rooms.cancel_search()
	else:
		Rooms.search(selected_format())
	_refresh()


func selected_format() -> String:
	if _format.selected < 0:
		return str(AppConfig.get_setting("play", "last_format", DEFAULT_FORMAT))
	return str(_format.get_item_metadata(_format.selected))


func _fill_formats() -> void:
	var wanted := str(AppConfig.get_setting("play", "last_format", DEFAULT_FORMAT))
	_format.clear()
	var formats := FormatList.quick_battle_formats(Rooms.formats)
	if formats.is_empty():
		# Not connected yet: offer the last format; the list arrives with |formats|.
		_format.add_item(str(AppConfig.get_setting("play", "last_format_name", _fallback_name(wanted))))
		_format.set_item_metadata(0, wanted)
	for format: Dictionary in formats:
		_format.add_item(str(format["name"]))
		_format.set_item_metadata(_format.item_count - 1, str(format["id"]))
	_select(wanted)


func _select(format_id: String) -> void:
	for i in _format.item_count:
		if str(_format.get_item_metadata(i)) == format_id:
			_format.select(i)
			_remember(i)
			return
	if _format.item_count > 0 and _format.selected < 0:
		_format.select(0)


func _refresh() -> void:
	var searching := Rooms.is_searching()
	if searching and _search_started_msec < 0:
		_search_started_msec = Time.get_ticks_msec()
	elif not searching:
		_search_started_msec = -1
	_battle.theme_type_variation = &"Button" if searching else &"PrimaryButton"
	_battle_text.text = tr("Cancel search") if searching else tr("Battle!")
	_battle_text.theme_type_variation = &"DockTitleLabel" if searching else &"OnAccentLabel"
	_battle_kbd.text = "Esc" if searching else "Ctrl+Enter"
	_battle_kbd.theme_type_variation = &"KbdLabel" if searching else &"KbdOnAccentLabel"
	if searching:
		var seconds := (Time.get_ticks_msec() - _search_started_msec) / 1000
		_status.text = tr("Searching… %d:%02d") % [seconds / 60, seconds % 60]
	else:
		_status.text = tr("Sound + notification when found")


## The format and its name, so the card can show it before the server's list arrives.
func _remember(index: int) -> void:
	AppConfig.set_setting("play", "last_format", str(_format.get_item_metadata(index)))
	AppConfig.set_setting("play", "last_format_name", _format.get_item_text(index))


static func _fallback_name(format_id: String) -> String:
	return "[Gen 9] Random Battle" if format_id == DEFAULT_FORMAT else format_id


func _field(label_text: String, control: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(RichButton.label(label_text, &"FieldLabel"))
	column.add_child(control)
	return column
