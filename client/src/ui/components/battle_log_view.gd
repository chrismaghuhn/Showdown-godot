class_name BattleLogView
extends ScrollContainer
## Renders BattleLogBuilder entries: turn headers with time, rows with BBCode text and chips,
## indented secondary rows (hidden in compact mode). Keeps the newest MAX_ROWS entries and
## follows new entries while the view is scrolled to the bottom.

const MAX_ROWS := 600

var compact := false:
	set(value):
		compact = value
		for row in _secondary_rows:
			if is_instance_valid(row):
				row.visible = not compact

var _list := VBoxContainer.new()
var _secondary_rows: Array[Control] = []


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"LogPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(panel)
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_list)


func clear() -> void:
	for child in _list.get_children():
		child.queue_free()
	_secondary_rows.clear()


func append(entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		return
	var scroll_bar := get_v_scroll_bar()
	var at_bottom := scroll_bar.value >= scroll_bar.max_value - scroll_bar.page - 24
	for entry in entries:
		_list.add_child(_turn(entry) if entry["kind"] == "turn" else _row(entry))
	while _list.get_child_count() > MAX_ROWS:
		var oldest := _list.get_child(0)
		_list.remove_child(oldest)
		oldest.queue_free()
	if at_bottom:
		await get_tree().process_frame
		scroll_vertical = int(get_v_scroll_bar().max_value)


func _turn(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"LogTurnPanel"
	var row := HBoxContainer.new()
	panel.add_child(row)
	var title := Label.new()
	title.text = tr("Turn %d") % int(entry["turn"])
	title.theme_type_variation = &"LogTurnLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var time := Label.new()
	time.text = str(entry.get("time", ""))
	time.theme_type_variation = &"LogTimeLabel"
	row.add_child(time)
	return panel


func _row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var indent: bool = entry.get("indent", false)
	if indent:
		var gap := Control.new()
		gap.custom_minimum_size.x = 12
		row.add_child(gap)
		row.visible = not compact
		_secondary_rows.append(row)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.selection_enabled = true
	if indent:
		text.theme_type_variation = &"LogSubText"
	text.text = entry["text"]
	row.add_child(text)
	for chip: Array in entry.get("chips", []):
		var label := Label.new()
		label.text = chip[0]
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label.theme_type_variation = &"BoostUpChip" if chip[1] == "up" else (&"BoostDownChip" if chip[1] == "down" else &"VolatileChip")
		row.add_child(label)
	return row
