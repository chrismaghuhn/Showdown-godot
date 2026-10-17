class_name MoveButton
extends Button
## 56px move button: name and category on top, type badge and PP below.
## The background is tinted with the move's type (theme variations "MoveButton_<type>").
## States: normal, disabled (with a reason instead of PP), chosen (toggle pressed, "Chosen").
## The hotkey tag ("1"–"4") shows on hover and keyboard focus.

var move_id := ""
## Returns a custom tooltip Control; set by the battle screen.
var tooltip_builder: Callable
var move_type := ""
var _name_label := Label.new()
var _category_icon := IconView.new("", "color.text.secondary")
var _type_badge := TypeBadge.new()
var _pp_label := Label.new()
var _hotkey := Label.new()
var _pp_text := ""
var _unavailable_reason := ""
var _chosen := false


func _init() -> void:
	custom_minimum_size = Vector2(120, 56)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_type_variation = &"MoveButton"
	focus_mode = Control.FOCUS_ALL

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_top = 6
	box.offset_right = -8
	box.offset_bottom = -6
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.clip_text = true
	top.add_child(_name_label)
	top.add_child(_category_icon)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bottom)
	bottom.add_child(_type_badge)
	_pp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pp_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pp_label.clip_text = true
	bottom.add_child(_pp_label)

	_hotkey.theme_type_variation = &"KbdLabel"
	_hotkey.visible = false
	add_child(_hotkey)
	_category_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label: Label in [_name_label, _pp_label, _hotkey]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Fills the button; returns self so it can be used inline.
func setup(move_name: String, type: String, category: String, pp: int, max_pp: int, hotkey := "") -> MoveButton:
	move_id = PSParser.to_id(move_name)
	move_type = type
	_name_label.text = move_name
	# Category as icon (design); the name is in the tooltip.
	_category_icon.icon_name = "ui-" + category.to_lower() if category in ["Physical", "Special", "Status"] else ""
	_type_badge.type_name = type
	_pp_text = "%d/%d" % [pp, max_pp] if max_pp > 0 else ""
	_unavailable_reason = ""
	_pp_label.text = _pp_text
	_hotkey.text = hotkey
	theme_type_variation = StringName("MoveButton_" + PSParser.to_id(type))
	tooltip_text = "%s · %s · %s" % [move_name, type, category]
	if max_pp > 0 and pp <= 0:
		set_unavailable(tr("Out of PP"))
	return self


## Disables the button and shows why instead of the PP (e.g. "Disabled", "Taunted").
func set_unavailable(reason: String) -> void:
	disabled = true
	_unavailable_reason = reason
	_pp_label.text = reason


## Chosen state while waiting for the opponent.
func set_chosen(chosen: bool) -> void:
	_chosen = chosen
	toggle_mode = true
	button_pressed = chosen
	if chosen:
		_pp_label.text = tr("Chosen")
	else:
		_pp_label.text = _unavailable_reason if not _unavailable_reason.is_empty() else _pp_text
	queue_redraw()


func _draw() -> void:
	# Labels follow the button state (Button has no signal for "disabled").
	_name_label.theme_type_variation = &"MoveNameLabelDisabled" if disabled and not _chosen else &"MoveNameLabel"
	_category_icon.modulate.a = 0.45 if disabled and not _chosen else 1.0
	_pp_label.theme_type_variation = &"MoveMetaLabel"
	_type_badge.modulate.a = 0.45 if disabled and not _chosen else 1.0
	var hovered := get_global_rect().has_point(get_global_mouse_position())
	_hotkey.visible = not _hotkey.text.is_empty() and not disabled and (hovered or has_focus())
	_hotkey.position = Vector2(size.x - _hotkey.size.x - 6, -12)


## Returns the tooltip Control (set by the battle screen); falls back to tooltip_text.
func _make_custom_tooltip(_for_text: String) -> Object:
	return tooltip_builder.call() if tooltip_builder.is_valid() else null
