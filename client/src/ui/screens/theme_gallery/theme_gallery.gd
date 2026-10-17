extends Control
## Theme gallery: every base component in every state, with a live theme switcher and
## UI scale slider. Used to review themes (built-in and community) and the design system.

var _theme_select: OptionButton
var _warnings: Label


func _ready() -> void:
	_build()
	EventBus.theme_changed.connect(func(_id: String) -> void: _refresh_header())
	# Screens stay alive: coming back picks up themes added to the themes folder meanwhile.
	visibility_changed.connect(func() -> void:
		if visible:
			Themes.discover()
			_refresh_header())
	_refresh_header()


func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"AppBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	background.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	# Header
	# Flow containers wrap instead of overflowing when the window is narrow or the UI scaled up.
	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation", 12)
	page.add_child(header)
	var title := _label("Theme gallery", &"DisplayLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("Theme", &"CapsLabel", true))
	_theme_select = OptionButton.new()
	_theme_select.item_selected.connect(func(index: int) -> void:
		Themes.apply(_theme_select.get_item_metadata(index)))
	header.add_child(_theme_select)
	header.add_child(_label("UI scale", &"CapsLabel", true))
	header.add_child(UiScaleControl.new(160))
	var back := _button("Back to console", &"GhostButton")
	back.pressed.connect(func() -> void: EventBus.navigation_requested.emit(&"dev-console"))
	header.add_child(back)
	_warnings = _label("", &"WarningLabel")
	_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warnings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_warnings)

	var columns := HFlowContainer.new()
	columns.add_theme_constant_override("h_separation", 16)
	columns.add_theme_constant_override("v_separation", 16)
	page.add_child(columns)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for column: VBoxContainer in [left, right]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.custom_minimum_size.x = 420
		column.add_theme_constant_override("separation", 16)
		columns.add_child(column)

	_buttons_section(left)
	_inputs_section(left)
	_typography_section(left)
	_icons_section(left)
	_moves_section(right)
	_badges_section(right)
	_hp_section(right)
	_panels_section(right)
	_app_states_section(page)


func _refresh_header() -> void:
	_theme_select.clear()
	for entry in Themes.available_themes():
		var title: String = entry["name"] + ("" if entry["builtin"] else " (community)")
		_theme_select.add_item(title)
		var index := _theme_select.item_count - 1
		_theme_select.set_item_metadata(index, entry["id"])
		_theme_select.set_item_disabled(index, not str(entry["error"]).is_empty())
		if entry["id"] == Themes.theme_id:
			_theme_select.select(index)
	var warnings := Themes.tokens.warnings if Themes.tokens != null else PackedStringArray()
	_warnings.visible = not warnings.is_empty()
	_warnings.text = "Theme warnings:\n• " + "\n• ".join(warnings)


# --- Sections ---------------------------------------------------------------------------

func _section(parent: Control, title: String, description := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_label(title, &"HeadingLabel"))
	if not description.is_empty():
		var hint := _label(description, &"MutedLabel")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(hint)
	return box


func _buttons_section(parent: Control) -> void:
	var box := _section(parent, "Buttons", "Primary · Secondary · Ghost · Danger · Small · Icon. Second row: disabled. Tab through them to see the focus ring.")
	for disabled in [false, true]:
		var row := HFlowContainer.new()
		box.add_child(row)
		for spec: Array in [["Battle!", &"PrimaryButton", ""], ["Import", &"", "ui-import"], ["Cancel", &"GhostButton", ""],
				["Forfeit", &"DangerButton", "ui-forfeit"], ["Small", &"SmallButton", ""], ["", &"IconButton", "ui-settings"]]:
			var button := _button(spec[0], spec[1])
			if not str(spec[2]).is_empty():
				button.icon = Icons.get_icon(spec[2])
			button.disabled = disabled
			button.tooltip_text = "Settings" if str(spec[0]).is_empty() else "Tooltip: %s button" % spec[0]
			row.add_child(button)
		var kbd := _label("Ctrl+K", &"KbdLabel")
		kbd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(kbd)


func _inputs_section(parent: Control) -> void:
	var box := _section(parent, "Inputs", "Text input: empty · filled · read-only. Dropdown, checkbox, tabs.")
	var row := HBoxContainer.new()
	box.add_child(row)
	for spec: Array in [["Chat message", "", true], ["Search", "Garchomp", true], ["Team name", "Sand Offense", false]]:
		var edit := LineEdit.new()
		edit.placeholder_text = spec[0]
		edit.text = spec[1]
		edit.editable = spec[2]
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	var formats := OptionButton.new()
	for f in ["[Gen 9] OU", "[Gen 9] Random Battle", "[Gen 9] Doubles OU"]:
		formats.add_item(f)
	row2.add_child(formats)
	var check := CheckBox.new()
	check.text = "Notify when it's my turn"
	check.button_pressed = true
	row2.add_child(check)
	var tabs := TabBar.new()
	for title in ["Battle", "Teambuilder", "Ladder", "Replays"]:
		tabs.add_tab(title)
	tabs.set_tab_disabled(3, true)
	box.add_child(tabs)


func _typography_section(parent: Control) -> void:
	var box := _section(parent, "Typography", "Atkinson Hyperlegible Next and Mono, sizes 11 / 12 / 13 / 15 / 18 / 24.")
	for spec: Array in [["Teambuilder", &"DisplayLabel"], ["Incoming challenges", &"TitleLabel"],
			["What will Tremor do?", &"HeadingLabel"], ["Tremor used Earthquake! It's super effective!", &""],
			["Secondary text for details", &"SecondaryLabel"], ["Taunted — status moves unavailable (1 turn)", &"MutedLabel"],
			["Ground · Special · PP", &"CapsLabel"], ["187/357 · 52% · 1:52 · Il1 O0", &"MonoLabel"],
			["Forfeit the battle?", &"DangerLabel"], ["Team saved", &"SuccessLabel"], ["Timer low", &"WarningLabel"],
			["bench-hp 1.4.0 · community plugin", &"PluginLabel"]]:
		var label := _label(spec[0], spec[1], spec[1] == &"CapsLabel")
		box.add_child(label)


func _icons_section(parent: Control) -> void:
	var box := _section(parent, "Icons", "%d hand-drawn icons, 16px grid, 1.5px stroke, tinted by the theme. Always paired with a label or tooltip." % Icons.names().size())
	for group_name in Icons.groups():
		box.add_child(_label(group_name, &"CapsLabel", true))
		var grid := GridContainer.new()
		grid.columns = 3
		box.add_child(grid)
		for icon_name in Icons.names():
			if Icons.group(icon_name) != group_name:
				continue
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.tooltip_text = icon_name
			var view := IconView.new(icon_name, "color.text.primary")
			view.tooltip_text = icon_name
			row.add_child(view)
			row.add_child(_label(Icons.label(icon_name), &"MutedLabel"))
			grid.add_child(row)


func _moves_section(parent: Control) -> void:
	var box := _section(parent, "Move buttons", "Background tinted by type (mix.type.tint). Out of PP = disabled.")
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(MoveButton.new().setup("Earthquake", "Ground", "Physical", 15, 16))
	grid.add_child(MoveButton.new().setup("Shadow Ball", "Ghost", "Special", 24, 24))
	grid.add_child(MoveButton.new().setup("Nasty Plot", "Dark", "Status", 32, 32))
	grid.add_child(MoveButton.new().setup("Make It Rain", "Steel", "Special", 0, 8))


func _badges_section(parent: Control) -> void:
	var box := _section(parent, "Badges & chips", "Every badge carries its text label.")
	var types := HFlowContainer.new()
	box.add_child(types)
	for type_id: String in ThemeTokens.TYPES:
		types.add_child(TypeBadge.new(type_id.capitalize()))
	var other := HFlowContainer.new()
	box.add_child(other)
	for status: String in ThemeTokens.STATUSES:
		other.add_child(StatusBadge.new(status))
	for boost: Array in [["spe", 1], ["spa", 2], ["def", -1], ["spd", -2]]:
		other.add_child(BoostChip.new(boost[0], boost[1]))
	other.add_child(_label("Taunt · 1", &"VolatileChip"))
	other.add_child(_label("Sandstorm · 3", &"FieldChip"))
	other.add_child(_label("Plugin", &"PluginBadge", true))


func _hp_section(parent: Control) -> void:
	var box := _section(parent, "HP bars", "High > 50 % · mid 21–50 % · low ≤ 20 %. The number is always shown.")
	for spec: Array in [[82.0, "82%"], [41.0, "41%"], [12.0, "12%"], [52.4, "187/357"], [0.0, "Fainted"]]:
		var row := HBoxContainer.new()
		box.add_child(row)
		var bar := HPBar.new(spec[0])
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		var value := _label(spec[1], &"MonoSmallLabel")
		value.custom_minimum_size.x = 72
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)


func _panels_section(parent: Control) -> void:
	var box := _section(parent, "Surfaces", "Raised · sunken · overlay (tooltips, menus, toasts) · selectable slot.")
	var row := HBoxContainer.new()
	box.add_child(row)
	for spec: Array in [["Raised", &"RaisedPanel"], ["Sunken (log, inputs)", &"SunkenPanel"], ["Overlay · shadow.md", &"OverlayPanel"], ["Scrim", &"Scrim"]]:
		var panel := PanelContainer.new()
		panel.theme_type_variation = spec[1]
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(_label(spec[0], &"SecondaryLabel"))
		row.add_child(panel)
	var slots := HBoxContainer.new()
	box.add_child(slots)
	for spec: Array in [["Great Tusk  263/371", false, false], ["Kingambit  186/404 · active", true, false], ["Dragapult  fainted", false, true]]:
		var slot := _button(spec[0], &"SlotButton")
		slot.toggle_mode = true
		slot.button_pressed = spec[1]
		slot.disabled = spec[2]
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slots.add_child(slot)


## Design "03 · Motion & app states", frames 04-08 (the connection cards are full-screen:
## run with --app-state=<id>, see src/app/dev_automation.gd).
func _app_states_section(parent: Control) -> void:
	var box := _section(parent, "App states", "Errors (blocking, inline, plugin), empty lists and loading skeletons.")
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	box.add_child(grid)

	var errors := _state_frame(grid, "05 · Errors")
	var error_row := HBoxContainer.new()
	error_row.add_theme_constant_override("separation", 12)
	errors.add_child(error_row)
	var blocking := ErrorBox.blocking("Couldn’t load your teams", "teams.json is damaged. Your last backup is from today, 22:41.",
		[["Restore backup", Callable()], ["Open folder", Callable()]])
	blocking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blocking.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	error_row.add_child(blocking)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	error_row.add_child(side)
	side.add_child(ErrorBox.inline("Team rejected by [Gen 9] OU · 2 problems",
		PackedStringArray(["Flutter Mane is banned in OU.", "Garchomp’s EVs total 512, max 510."])))
	side.add_child(ErrorBox.plugin("Damage Calc paused", "It stopped responding for 5 s. The battle is not affected.",
		[["Reload plugin", Callable()], ["Disable", Callable()]]))

	var empty := _state_frame(grid, "06 · Empty page")
	empty.add_child(EmptyState.page("ui-grid-view", "No teams yet",
		"Build one from scratch, or paste a team you copied from Showdown, Pokepaste or VRPastes.",
		[["New team", Callable()], ["Paste from clipboard", Callable()]], ["Restore from a backup…", Callable()]))

	var lists := _state_frame(grid, "07 · Empty lists · 08 · No results")
	var list_row := HBoxContainer.new()
	list_row.add_theme_constant_override("separation", 12)
	lists.add_child(list_row)
	for section: Control in [
			EmptyState.section("Your battles", "No active battles. Battles you start or join show up here.", ["Find a battle", Callable()]),
			EmptyState.section("Incoming challenges", "Nobody has challenged you. You can turn challenges off in Settings › General.")]:
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		for label in section.find_children("*", "Label", true, false):
			(label as Label).custom_minimum_size.x = 180
		list_row.add_child(section)
	var search := LineEdit.new()
	search.text = "kingambit stall"
	search.placeholder_text = "Search teams"
	lists.add_child(search)
	lists.add_child(EmptyState.no_results("teams", "kingambit stall", "All teams", Callable()))

	var loading := _state_frame(grid, "04 · Loading")
	for fraction in [0.3, 0.7, 0.55]:
		loading.add_child(SkeletonBlock.line(fraction))
	for i in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(SkeletonBlock.new(28, 28))
		var middle := SkeletonBlock.new(0, 12)
		middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(middle)
		row.add_child(SkeletonBlock.new(64, 12))
		loading.add_child(row)
	loading.add_child(_label("Opacity pulse 1 ↔ 0.6 every 1.2 s, static with reduce motion.", &"MutedLabel"))


func _state_frame(parent: Control, tag: String) -> VBoxContainer:
	var frame := VBoxContainer.new()
	frame.custom_minimum_size.x = 520
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_constant_override("separation", 12)
	frame.add_child(_label(tag, &"CapsLabel", true))
	parent.add_child(frame)
	return frame


# --- Helpers ------------------------------------------------------------------------------

func _label(text: String, variation: StringName, uppercase := false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.uppercase = uppercase
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return label


func _button(text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	return button
