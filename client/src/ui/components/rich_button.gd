class_name RichButton
extends Button
## A button whose content is a row of controls (dot, icon box, labels, key hint) instead of a
## single text. The theme variation still draws background, hover, pressed and focus; the row
## sits inside with the given padding and the button grows to fit it.

var row := HBoxContainer.new()
## The button is at least this wide, however small its content (custom_minimum_size.x is
## recomputed from the content).
var min_width := 0.0:
	set(value):
		min_width = value
		_fit()
var _pad_left := 12
var _pad_right := 12


func _init(variation: StringName = &"Button", pad_left := 12, pad_right := 12) -> void:
	theme_type_variation = variation
	_pad_left = pad_left
	_pad_right = pad_right
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = pad_left
	row.offset_right = -pad_right
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	row.minimum_size_changed.connect(_fit)


## Adds a control to the content row. Plain controls let clicks through to the button.
func add(control: Control) -> Control:
	if not control is BaseButton:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in control.find_children("*", "Control", true, false):
			if not child is BaseButton:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(control)
	return control


## A flexible gap that pushes the following controls to the right edge.
func add_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return add(spacer)


static func label(text_value: String, variation: StringName) -> Label:
	var result := Label.new()
	result.text = text_value
	result.theme_type_variation = variation
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return result


## A key hint such as "Ctrl+K" or "Enter" (design: .sd-kbd).
static func kbd(keys: String, on_accent := false) -> Label:
	var hint := label(keys, &"KbdOnAccentLabel" if on_accent else &"KbdLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size.x = 20
	return hint


func _fit() -> void:
	var content := row.get_combined_minimum_size()
	custom_minimum_size.x = maxf(content.x + _pad_left + _pad_right, min_width)
	custom_minimum_size.y = maxf(custom_minimum_size.y, content.y)
