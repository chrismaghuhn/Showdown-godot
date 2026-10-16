class_name MoveButton
extends Button
## 56px move button: name and category on top, type badge and PP below.
## The background is tinted with the move's type (theme variations "MoveButton_<type>").

var _name_label := Label.new()
var _category_label := Label.new()
var _type_badge := TypeBadge.new()
var _pp_label := Label.new()


func _init() -> void:
	custom_minimum_size = Vector2(176, 56)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_type_variation = &"MoveButton"

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
	top.add_child(_category_label)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bottom)
	bottom.add_child(_type_badge)
	_pp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_pp_label)
	for label: Label in [_name_label, _category_label, _pp_label]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fills the button; returns self so it can be used inline.
func setup(move_name: String, move_type: String, category: String, pp: int, max_pp: int) -> MoveButton:
	_name_label.text = move_name
	_category_label.text = category
	_type_badge.type_name = move_type
	_pp_label.text = "%d/%d" % [pp, max_pp]
	theme_type_variation = StringName("MoveButton_" + PSParser.to_id(move_type))
	tooltip_text = "%s · %s · %s · PP %d/%d" % [move_name, move_type, category, pp, max_pp]
	if pp <= 0:
		disabled = true
	return self


func _draw() -> void:
	# Labels follow the button's disabled state (Button has no signal for it).
	var label_variation := &"MoveNameLabelDisabled" if disabled else &"MoveNameLabel"
	if _name_label.theme_type_variation != label_variation:
		_name_label.theme_type_variation = label_variation
		_category_label.theme_type_variation = &"MoveMetaLabel"
		_pp_label.theme_type_variation = &"MoveMetaLabel"
		_type_badge.modulate.a = 0.45 if disabled else 1.0
