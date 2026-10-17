class_name ConditionChip
extends PanelContainer
## Field / side condition chip: icon + name + optional count (turns left or layers),
## e.g. "Sandstorm 3", "Spikes ×2". Small variant for HUD cards.

var _icon := IconView.new()
var _label := Label.new()
var _count := Label.new()


func _init(text := "", icon_name := "", count := "", small := false, muted := false) -> void:
	theme_type_variation = &"FieldChipSmallPanel" if small else &"FieldChipPanel"
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4 if small else 8)
	add_child(row)
	_icon.color_token = "color.text.muted" if muted else "color.text.secondary"
	if small:
		_icon.custom_minimum_size = Vector2(14, 14)
	row.add_child(_icon)
	_label.theme_type_variation = &"ChipSmallTextLabel" if small else &"ChipTextLabel"
	if muted:
		_label.theme_type_variation = &"MutedLabel"
	row.add_child(_label)
	_count.theme_type_variation = &"ChipCountLabel"
	row.add_child(_count)
	setup(text, icon_name, count)


func setup(text: String, icon_name: String, count := "") -> void:
	_label.text = text
	_icon.icon_name = icon_name
	_icon.visible = not icon_name.is_empty()
	_count.text = count
	_count.visible = not count.is_empty()
	tooltip_text = text + (" · " + count if not count.is_empty() else "")
