class_name EmptyState
extends RefCounted
## Empty lists (design: "03 · Motion & app states", frames 06-08). Actions are
## [[label, Callable], ...]; the first one is the main action.
##   page()        a whole screen without content yet, e.g. "No teams yet" (frame 06)
##   section()     a list inside a panel, e.g. "Your battles" with nothing in it (frame 07)
##   no_results()  a search that found nothing, with "Clear search" (frame 08)


## Centered: 48px icon circle, title, text, buttons and an optional small link below.
static func page(icon: String, title: String, text: String, actions: Array = [], link: Array = []) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size.x = 380
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var circle := PanelContainer.new()
	circle.theme_type_variation = &"EmptyIconPanel"
	circle.custom_minimum_size = Vector2(48, 48)
	circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icon_view := IconView.new(icon, "color.text.secondary")
	icon_view.custom_minimum_size = Vector2(24, 24)
	icon_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	circle.add_child(icon_view)
	column.add_child(circle)
	column.add_child(_label(title, &"CardTitleLabel", true))
	column.add_child(_label(text, &"SecondaryLabel", true))
	if not actions.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		for i in actions.size():
			row.add_child(_button(actions[i], &"PrimaryButton" if i == 0 else &"Button"))
		column.add_child(row)
	if not link.is_empty():
		var button := _button(link, &"SmallGhostButton")
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(button)
	return column


## A panel with a title, a muted line and an optional small button.
static func section(title: String, text: String, action: Array = []) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SectionPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_label(title, &"DockTitleLabel", false))
	var line := _label(text, &"MutedLabel", false)
	column.add_child(line)
	if not action.is_empty():
		var button := _button(action, &"SmallButton")
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		column.add_child(button)
	return panel


## "No teams match “kingambit stall” in All teams." with a "Clear search" button. The
## query is the user's text and only ever shown as plain text.
static func no_results(things: String, query: String, scope: String, on_clear: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sentence := HFlowContainer.new()
	sentence.add_theme_constant_override("h_separation", 4)
	sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sentence.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sentence.add_child(_label(_t("No %s match") % things, &"SecondaryLabel", false))
	sentence.add_child(_label("“%s”" % query, &"DockTitleLabel", false))
	sentence.add_child(_label(_t("in %s.") % scope, &"SecondaryLabel", false))
	for label: Label in sentence.get_children():
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(sentence)
	var clear := _button([_t("Clear search"), on_clear], &"SmallGhostButton")
	clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(clear)
	return row


static func _label(text: String, variation: StringName, centered: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func _button(action: Array, variation: StringName) -> Button:
	var button := Button.new()
	button.text = str(action[0])
	button.theme_type_variation = variation
	var callback: Callable = action[1] if action.size() > 1 else Callable()
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


static func _t(text: String) -> String:
	return str(TranslationServer.translate(text))
