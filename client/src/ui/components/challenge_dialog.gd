class_name ChallengeDialog
extends PopupPanel
## "Challenge a user…" (design: lobby): a name and a format, sent with /challenge. Signed out,
## it asks for a name first. The server's answer to a failed challenge shows as a toast.

var _name := LineEdit.new()
var _format := FormatPicker.new(FormatPicker.Purpose.CHALLENGE)
var _send := Button.new()


func _init() -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 340
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	column.add_child(RichButton.label(tr("Challenge a user"), &"CardTitleLabel"))
	_name.placeholder_text = tr("Their Showdown name")
	_name.max_length = SignInCard.MAX_NAME_LENGTH
	_name.text_changed.connect(func(_t: String) -> void: _update())
	_name.text_submitted.connect(func(_t: String) -> void: _submit())
	column.add_child(_field(tr("Name"), _name))
	_format.select(str(AppConfig.get_setting("play", "last_format", QuickBattleCard.DEFAULT_FORMAT)))
	_format.format_selected.connect(func(_id: String) -> void: _update())
	column.add_child(_field(tr("Format"), _format))
	var buttons := HBoxContainer.new()
	_send.text = tr("Challenge")
	_send.theme_type_variation = &"PrimaryButton"
	_send.pressed.connect(_submit)
	buttons.add_child(_send)
	buttons.add_child(StateCard.make_button(tr("Cancel"), &"GhostButton", hide))
	column.add_child(buttons)


func open_at(anchor: Control) -> void:
	_name.clear()
	_format.select(str(AppConfig.get_setting("play", "last_format", QuickBattleCard.DEFAULT_FORMAT)))
	_update()
	reset_size()
	position = Vector2i(anchor.get_screen_position() + Vector2(anchor.size.x - size.x, anchor.size.y + 4))
	popup()
	_name.grab_focus()


func _update() -> void:
	_send.disabled = PSParser.to_id(_name.text).is_empty() or _format.selected_id.is_empty()


func _submit() -> void:
	if _send.disabled:
		return
	# Signed out, Rooms asks for a name first and sends the challenge right after.
	Rooms.challenge(_name.text, _format.selected_id)
	hide()


func _field(label_text: String, control: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(RichButton.label(label_text, &"FieldLabel"))
	column.add_child(control)
	return column
