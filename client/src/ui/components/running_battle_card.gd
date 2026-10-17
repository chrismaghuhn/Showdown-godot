class_name RunningBattleCard
extends PanelContainer
## "Battle in progress" on the start screen (design): opponent, format, turn and the active
## Pokémon, "Your move", the timer, and "Rejoin battle" (Enter). Also shows a game the server
## lists for this user that the client hasn't joined yet (after a restart).

signal rejoin_requested(room_id: String)

var room_id := ""
var _pill := PanelContainer.new()
var _title := RichButton.label("", &"CardTitleLabel")
var _line := RichButton.label("", &"MutedLabel")
var _timer := HBoxContainer.new()
var _timer_text := RichButton.label("", &"MonoSmallLabel")
var _button := RichButton.new(&"PrimaryButton", 16, 8)


func _init() -> void:
	theme_type_variation = &"AccentCard"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var head := HBoxContainer.new()
	var caps := RichButton.label(tr("Battle in progress"), &"CapsLabel")
	caps.uppercase = true
	caps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caps)
	_pill.theme_type_variation = &"AccentPill"
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 8)
	pill_row.add_child(StatusDot.new("color.accent.text", false, 7.0))
	pill_row.add_child(RichButton.label(tr("Your move"), &"AccentPillLabel"))
	_pill.add_child(pill_row)
	head.add_child(_pill)
	column.add_child(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(_title)
	text.add_child(_line)
	body.add_child(text)
	_timer.add_theme_constant_override("separation", 4)
	_timer.add_child(IconView.new("ui-timer", "color.text.secondary"))
	_timer.add_child(_timer_text)
	body.add_child(_timer)
	column.add_child(body)
	_button.custom_minimum_size.y = 40
	_button.add(RichButton.label(tr("Rejoin battle"), &"OnAccentLabel"))
	_button.add_spacer()
	_button.add(RichButton.kbd("Enter", true))
	_button.pressed.connect(func() -> void: rejoin_requested.emit(room_id))
	column.add_child(_button)


## A joined battle.
func show_battle(battle: BattleState) -> void:
	room_id = battle.room_id
	var view := describe(battle)
	_title.text = view["title"]
	_line.text = view["line"]
	_pill.visible = battle.awaiting_choice
	_timer.visible = battle.timer_on and battle.timer_turn_seconds >= 0
	_timer_text.text = "%d:%02d" % [battle.timer_turn_seconds / 60, battle.timer_turn_seconds % 60]


## A game the server lists that isn't joined yet: {room_id: title}.
func show_game(game_room: String, title: String) -> void:
	room_id = game_room
	_title.text = title.trim_suffix("*")
	_line.text = tr("Still running on the server · rejoin to see it")
	_pill.visible = false
	_timer.visible = false


## {title: "vs Mirebloom", line: "[Gen 9] OU · Turn 7 · Tremor 52% vs Gholdengo 41%"}
static func describe(battle: BattleState) -> Dictionary:
	var mine := battle.my_side if not battle.my_side.is_empty() else "p1"
	var theirs := "p2" if mine == "p1" else "p1"
	var opponent := battle.side(theirs).player_name
	var parts := PackedStringArray()
	parts.append(battle.format if not battle.format.is_empty() else battle.room_id.get_slice("-", 1))
	if battle.turn > 0:
		parts.append(_t("Turn %d") % battle.turn)
	var my_mon := battle.side(mine).active_pokemon()
	var their_mon := battle.side(theirs).active_pokemon()
	if my_mon != null and their_mon != null:
		parts.append(_t("%s %d%% vs %s %d%%") % [my_mon.species, roundi(my_mon.hp_percent()),
			their_mon.species, roundi(their_mon.hp_percent())])
	return {
		"title": _t("vs %s") % opponent if not opponent.is_empty() else _t("Battle"),
		"line": " · ".join(parts),
	}


static func _t(text: String) -> String:
	return str(TranslationServer.translate(text))
