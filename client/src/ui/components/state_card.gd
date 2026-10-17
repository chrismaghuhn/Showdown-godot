class_name StateCard
extends PanelContainer
## The centered card for app states (design: ".ms-card"): connecting, signing in, choosing a
## server. 360px wide, 12px between rows; build its rows with the helpers.

const WIDTH := 360

var rows := VBoxContainer.new()


func _init() -> void:
	theme_type_variation = &"StateCard"
	custom_minimum_size.x = WIDTH
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)


func add_title(text: String, centered := false) -> Label:
	return add_text(text, &"CardTitleLabel", centered)


func add_text(text: String, variation: StringName = &"SecondaryLabel", centered := false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(label)
	return label


## A row of buttons or an icon with text, 8px apart.
func add_row(centered := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if centered:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(row)
	return row


## A label above a field (design: ".ms-lbl", 4px gap).
func add_field(label_text: String, field: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"FieldLabel"
	column.add_child(label)
	column.add_child(field)
	rows.add_child(column)
	return column


static func make_button(text: String, variation: StringName, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.pressed.connect(callback)
	return button
