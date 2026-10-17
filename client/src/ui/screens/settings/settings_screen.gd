extends Control
## Settings (design: "Settings · Notifications" and "Settings · Appearance"): navigation on the
## left, one page at a time on the right. Settings save automatically.

const PAGES := ["appearance", "notifications", "sounds"]
const PAGE_TITLES := {"appearance": "Appearance", "notifications": "Notifications", "sounds": "Sounds"}
const PAGE_ICONS := {"appearance": "ui-theme", "notifications": "ui-notify", "sounds": "ui-sound"}

var _page_holder := VBoxContainer.new()
var _nav := VBoxContainer.new()
var _nav_buttons := {}
var _file_dialog := FileDialog.new()
var _import_event := ""
var _sound_rows := {}
var _current := ""


func _ready() -> void:
	_build()
	EventBus.theme_changed.connect(func(_id: String) -> void: _rebuild_current.call_deferred())
	var start_page := AppConfig.cli("settings-page", "notifications")
	show_page(start_page if start_page in PAGES else "notifications")


func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"AppBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	background.add_child(row)

	var nav_panel := PanelContainer.new()
	nav_panel.theme_type_variation = &"FlatPanel"
	nav_panel.custom_minimum_size.x = 240
	row.add_child(nav_panel)
	var nav_margin := _margin(16)
	nav_panel.add_child(nav_margin)
	_nav.add_theme_constant_override("separation", 4)
	nav_margin.add_child(_nav)
	_nav.add_child(_label(tr("Settings"), &"TitleLabel"))
	for page: String in PAGES:
		var button := Button.new()
		button.text = tr(PAGE_TITLES[page])
		button.icon = Icons.get_icon(PAGE_ICONS[page])
		button.theme_type_variation = &"SlotButton"
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(show_page.bind(page))
		_nav.add_child(button)
		_nav_buttons[page] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nav.add_child(spacer)
	_nav.add_child(_label(tr("Settings save automatically."), &"MutedLabel"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var content_margin := _margin(32)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_margin)
	_page_holder.custom_minimum_size.x = 640
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.add_theme_constant_override("separation", 16)
	content_margin.add_child(_page_holder)

	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; " + tr("Sounds")])
	_file_dialog.file_selected.connect(_on_sound_file_selected)
	add_child(_file_dialog)


func show_page(page: String) -> void:
	_current = page
	for id: String in _nav_buttons:
		_nav_buttons[id].set_pressed_no_signal(id == page)
	_rebuild_current()


func _rebuild_current() -> void:
	for child in _page_holder.get_children():
		child.queue_free()
	_sound_rows.clear()
	match _current:
		"appearance":
			_build_appearance()
		"notifications":
			_build_notifications()
		"sounds":
			_build_sounds()


# --- Appearance -------------------------------------------------------------------------------

func _build_appearance() -> void:
	_page_header(tr("Appearance"), tr("Themes only change design tokens. Community themes go into the themes folder."))
	var box := _section(tr("Theme"))
	var themes := OptionButton.new()
	for entry in Themes.available_themes():
		themes.add_item(str(entry["name"]) + ("" if entry["builtin"] else " (" + tr("community") + ")"))
		var index := themes.item_count - 1
		themes.set_item_metadata(index, entry["id"])
		themes.set_item_disabled(index, not str(entry["error"]).is_empty())
		if entry["id"] == Themes.theme_id:
			themes.select(index)
	themes.item_selected.connect(func(index: int) -> void: Themes.apply(themes.get_item_metadata(index)))
	box.add_child(_setting_row(tr("Theme"), tr("Midnight Dark, Classic Light, High Contrast or a community theme."), themes))
	var folder := Button.new()
	folder.text = tr("Open themes folder")
	folder.theme_type_variation = &"SmallButton"
	folder.pressed.connect(func() -> void: OS.shell_open(ProjectSettings.globalize_path(Themes.USER_DIR)))
	box.add_child(_setting_row(tr("Community themes"), tr("Put .sdtheme.json files here."), folder))

	var scale_row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = Themes.SCALE_MIN * 100
	slider.max_value = Themes.SCALE_MAX * 100
	slider.step = Themes.SCALE_STEP * 100
	slider.value = Themes.ui_scale * 100
	slider.custom_minimum_size.x = 200
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := _label("%d %%" % roundi(slider.value), &"MonoLabel")
	slider.value_changed.connect(func(v: float) -> void: value.text = "%d %%" % roundi(v))
	slider.drag_ended.connect(func(_c: bool) -> void: Themes.set_ui_scale(slider.value / 100.0))
	scale_row.add_child(slider)
	scale_row.add_child(value)
	box.add_child(_setting_row(tr("UI scale"), tr("Makes everything larger or smaller."), scale_row))
	var reduce := CheckButton.new()
	reduce.button_pressed = Themes.reduce_motion
	reduce.toggled.connect(Themes.set_reduce_motion)
	box.add_child(_setting_row(tr("Reduce motion"), tr("No slides or bouncing; HP bars jump to the new value."), reduce))


# --- Notifications ----------------------------------------------------------------------------

func _build_notifications() -> void:
	_page_header(tr("Notifications"), tr("Choose how Showdown Desktop gets your attention. Desktop notifications go through your system's notification center."))
	var status := HBoxContainer.new()
	var available := NativeNotifier.is_available()
	status.add_child(IconView.new("ui-notify" if available else "ui-warning", "color.success.text" if available else "color.warning.text"))
	var status_text := VBoxContainer.new()
	status_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_text.add_child(_label(tr("Desktop notifications are available") if available else tr("Desktop notifications are unavailable"), &"DockTitleLabel"))
	status_text.add_child(_label(tr("Your system's focus or do-not-disturb mode can still hold them back.") if available
		else tr("Install libnotify (notify-send) to enable them on Linux."), &"MutedLabel"))
	status.add_child(status_text)
	var test := Button.new()
	test.text = tr("Send test notification")
	test.theme_type_variation = &"SmallButton"
	test.pressed.connect(Notifier.send_test)
	status.add_child(test)
	_page_holder.add_child(_card(status))

	var events := _section(tr("Events"))
	var reset := Button.new()
	reset.text = tr("Reset to defaults")
	reset.theme_type_variation = &"GhostButton"
	reset.pressed.connect(func() -> void:
		Notifier.reset_events()
		_rebuild_current())
	events.get_parent().get_child(0).add_child(reset)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	events.add_child(grid)
	for header in [tr("Event"), tr("In-app"), tr("Sound"), tr("Desktop")]:
		grid.add_child(_label(header, &"CapsLabel", true))
	for event: String in NotificationEvents.EVENTS:
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(_label(tr(NotificationEvents.LABELS[event][0]), &"DockTitleLabel"))
		info.add_child(_label(tr(NotificationEvents.LABELS[event][1]), &"MutedLabel"))
		grid.add_child(info)
		for channel: String in NotificationEvents.CHANNELS:
			var check := CheckBox.new()
			var key := "%s.%s" % [event, channel]
			check.button_pressed = bool(Notifier.get_value(key))
			check.tooltip_text = "%s: %s" % [tr(NotificationEvents.LABELS[event][0]), tr(channel)]
			check.toggled.connect(func(on: bool) -> void: Notifier.set_value(key, on))
			grid.add_child(check)

	var behavior := _section(tr("Behavior"))
	behavior.add_child(_switch_row("only_background", tr("Only when Showdown Desktop is in the background"),
		tr("Desktop notifications and sounds stay quiet while the battle is on screen.")))
	behavior.add_child(_switch_row("flash_taskbar", tr("Flash taskbar icon on your turn"), tr("Bounces the Dock icon on macOS.")))
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for seconds: int in NotificationEvents.TIMER_OPTIONS:
		var option := Button.new()
		option.text = tr("%d s left") % seconds
		option.theme_type_variation = &"SmallButton"
		option.toggle_mode = true
		option.button_group = group
		option.button_pressed = int(Notifier.get_value("timer_warning")) == seconds
		option.pressed.connect(func() -> void: Notifier.set_value("timer_warning", seconds))
		timer_row.add_child(option)
	behavior.add_child(_setting_row(tr("Timer warning"), tr("When \"Timer running low\" fires."), timer_row))
	behavior.add_child(_setting_row(tr("Notification volume"), tr("Separate from battle music and effects."), _volume_control()))


func _switch_row(key: String, title: String, description: String) -> Control:
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(Notifier.get_value(key))
	toggle.toggled.connect(func(on: bool) -> void: Notifier.set_value(key, on))
	return _setting_row(title, description, toggle)


func _volume_control() -> Control:
	var row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = Notifier.volume() * 100
	slider.custom_minimum_size.x = 200
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := _label("%d%%" % roundi(slider.value), &"MonoLabel")
	slider.value_changed.connect(func(v: float) -> void:
		value.text = "%d%%" % roundi(v)
		Notifier.set_value("volume", v / 100.0))
	row.add_child(slider)
	row.add_child(value)
	var play := Button.new()
	play.theme_type_variation = &"IconButton"
	play.icon = Icons.get_icon("ui-play")
	play.tooltip_text = tr("Play test sound")
	play.pressed.connect(func() -> void: Sounds.play("your_turn", Notifier.volume()))
	row.add_child(play)
	return row


# --- Sounds -----------------------------------------------------------------------------------

func _build_sounds() -> void:
	_page_header(tr("Sounds"), tr("Pick a sound pack, or use your own file for any event (.wav, .ogg or .mp3, up to 2 MB and 5 s)."))
	var pack_box := _section(tr("Sound pack"))
	var packs := OptionButton.new()
	for id: String in Sounds.packs:
		var pack: Dictionary = Sounds.packs[id]
		packs.add_item(str(pack["name"]) + ("" if pack["builtin"] else " (" + tr("community") + ")"))
		packs.set_item_metadata(packs.item_count - 1, id)
		if id == Sounds.current_pack():
			packs.select(packs.item_count - 1)
	packs.item_selected.connect(func(index: int) -> void:
		Sounds.set_pack(packs.get_item_metadata(index))
		_rebuild_current())
	var author := str(Sounds.packs.get(Sounds.current_pack(), {}).get("author", ""))
	pack_box.add_child(_setting_row(tr("Pack"), author, packs))
	var folder := Button.new()
	folder.text = tr("Open sounds folder")
	folder.theme_type_variation = &"SmallButton"
	folder.pressed.connect(func() -> void: OS.shell_open(ProjectSettings.globalize_path(Sounds.USER_DIR)))
	pack_box.add_child(_setting_row(tr("Community packs"), tr("A folder with sounds and an sdsounds.json."), folder))

	var output := _section(tr("Output"))
	var devices := OptionButton.new()
	devices.custom_minimum_size.x = 260
	var saved := Sounds.get_output_device()
	var available := Sounds.output_devices()
	for device in available:
		devices.add_item(Sounds.device_label(device))
		var index := devices.item_count - 1
		devices.set_item_metadata(index, device)
		devices.set_item_tooltip(index, device)
		if device == Sounds.resolve_device(saved, available):
			devices.select(index)
	devices.item_selected.connect(func(index: int) -> void: Sounds.set_output_device(devices.get_item_metadata(index)))
	var device_row := HBoxContainer.new()
	device_row.add_child(devices)
	var test := Button.new()
	test.theme_type_variation = &"IconButton"
	test.icon = Icons.get_icon("ui-play")
	test.tooltip_text = tr("Play test sound")
	test.pressed.connect(func() -> void: Sounds.play("your_turn", Notifier.volume()))
	device_row.add_child(test)
	var hint := tr("Where notification sounds play. \"System default\" follows your system settings.")
	if Sounds.resolve_device(saved, available) != saved:
		hint = tr("Your saved device (%s) isn't connected, so the system default is used.") % Sounds.device_label(saved)
	output.add_child(_setting_row(tr("Output device"), hint, device_row))

	var events := _section(tr("Per event"))
	for event: String in NotificationEvents.EVENTS:
		var controls := HBoxContainer.new()
		var choice := OptionButton.new()
		choice.add_item(tr("Pack sound"))
		choice.add_item(tr("No sound"))
		choice.add_item(tr("Custom file…"))
		var current := Sounds.get_choice(event)
		if current.begins_with("custom:"):
			choice.add_item(tr("Custom: %s") % current.substr(7))
			choice.select(3)
		else:
			choice.select(1 if current == "none" else 0)
		choice.custom_minimum_size.x = 200
		choice.item_selected.connect(_on_sound_choice.bind(event, choice))
		controls.add_child(choice)
		var play := Button.new()
		play.theme_type_variation = &"IconButton"
		play.icon = Icons.get_icon("ui-play")
		play.tooltip_text = tr("Play")
		play.pressed.connect(func() -> void: Sounds.play(event, Notifier.volume()))
		controls.add_child(play)
		var row := _setting_row(tr(NotificationEvents.LABELS[event][0]), "", controls)
		events.add_child(row)
		var error := _label("", &"DangerLabel")
		error.visible = false
		events.add_child(error)
		_sound_rows[event] = error


func _on_sound_choice(index: int, event: String, choice: OptionButton) -> void:
	match index:
		0:
			Sounds.set_choice(event, "pack")
		1:
			Sounds.set_choice(event, "none")
		2:
			_import_event = event
			_file_dialog.popup_centered_ratio(0.6)


func _on_sound_file_selected(path: String) -> void:
	var error := Sounds.import_custom(_import_event, path)
	_rebuild_current()
	if not error.is_empty():
		await get_tree().process_frame
		var label: Label = _sound_rows.get(_import_event)
		if label != null:
			label.text = error
			label.visible = true
	else:
		Sounds.play(_import_event, Notifier.volume())


# --- Helpers ----------------------------------------------------------------------------------

func _page_header(title: String, description: String) -> void:
	_page_holder.add_child(_label(title, &"DisplayLabel"))
	var text := _label(description, &"SecondaryLabel")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.add_child(text)


## A card with a heading row; returns the body container.
func _section(title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	var heading := _label(title, &"HeadingLabel")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	column.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	_page_holder.add_child(_card(column))
	return body


func _card(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_child(content)
	return panel


func _setting_row(title: String, description: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(_label(title, &"DockTitleLabel"))
	if not description.is_empty():
		var hint := _label(description, &"MutedLabel")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(hint)
	row.add_child(text)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


func _margin(px: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, px)
	return margin


func _label(text: String, variation: StringName, uppercase := false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.uppercase = uppercase
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label
