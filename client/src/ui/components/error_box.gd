class_name ErrorBox
extends PanelContainer
## Error messages (design: "03 · Motion & app states", frame 05):
##   blocking()  something can't continue - danger border, alert icon, title, text, actions
##   inline()    a list of problems next to what caused them, e.g. a team rejected by validation
##   plugin()    a plugin that was paused, with "Reload plugin" / "Disable"
## Actions are [[label, Callable], ...]; the first one is the main action.

var column := VBoxContainer.new()


func _init() -> void:
	column.add_theme_constant_override("separation", 8)
	add_child(column)


static func blocking(title: String, text: String, actions: Array = []) -> ErrorBox:
	var box := ErrorBox.new()
	box.theme_type_variation = &"DangerCard"
	box._add_heading("ui-alert", "color.danger.text", title, &"DockTitleLabel")
	box._add_text(text)
	box._add_actions(actions, [&"SmallPrimaryButton", &"SmallButton"])
	return box


static func inline(title: String, problems: PackedStringArray) -> ErrorBox:
	var box := ErrorBox.new()
	box.theme_type_variation = &"InlineErrorPanel"
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"SmallBoldLabel"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.column.add_child(heading)
	for problem in problems:
		box.column.add_child(_bullet(problem))
	return box


static func plugin(title: String, text: String, actions: Array = []) -> ErrorBox:
	var box := ErrorBox.new()
	box._add_heading("ui-plugin", "color.plugin.text", title, &"SmallBoldLabel")
	box._add_text(text)
	box._add_actions(actions, [&"SmallButton", &"SmallGhostButton"])
	return box


func _add_heading(icon: String, color_token: String, title: String, variation: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(IconView.new(icon, color_token))
	var label := Label.new()
	label.text = title
	label.theme_type_variation = variation
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	column.add_child(row)


func _add_text(text: String) -> void:
	if text.is_empty():
		return
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SmallSecondaryLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)


## variations: [first action, the others]
func _add_actions(actions: Array, variations: Array) -> void:
	if actions.is_empty():
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for i in actions.size():
		var action: Array = actions[i]
		var callback: Callable = action[1] if action.size() > 1 else Callable()
		var button := Button.new()
		button.text = str(action[0])
		button.theme_type_variation = variations[0] if i == 0 else variations[1]
		if callback.is_valid():
			button.pressed.connect(callback)
		row.add_child(button)
	column.add_child(row)


## A row with a 4px dot and wrapped text (design: ".ms-li").
static func _bullet(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := Label.new()
	dot.text = "•"
	dot.theme_type_variation = &"MutedLabel"
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(dot)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SmallSecondaryLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row
