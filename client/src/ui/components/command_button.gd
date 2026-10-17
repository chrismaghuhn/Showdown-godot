class_name CommandButton
extends RichButton
## "Search or run a command · Ctrl+K" in the app header (design: ".c-cmd"). Until the command
## palette exists (#8) it opens a "Go to" menu; the app fills it with set_entries().

signal chosen(id: StringName)
## Right before the menu opens: the app fills it with set_entries().
signal opening

var _menu := PopupMenu.new()
var _ids: Array[StringName] = []


func _init() -> void:
	super(&"CommandButton", 8, 4)
	custom_minimum_size = Vector2(256, 28)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add(IconView.new("ui-search", "color.text.muted"))
	add(RichButton.label(tr("Search or run a command"), &"MutedLabel"))
	add_spacer()
	add(RichButton.kbd("Ctrl+K"))
	tooltip_text = tr("Go to a screen. The full command palette comes later.")
	pressed.connect(open_menu)
	_menu.id_pressed.connect(func(index: int) -> void:
		if index >= 0 and index < _ids.size():
			chosen.emit(_ids[index]))
	add_child(_menu)


## entries: [[id, label], ...]; a "" id adds a separator.
func set_entries(entries: Array) -> void:
	_menu.clear()
	_ids.clear()
	for entry: Array in entries:
		if str(entry[0]).is_empty():
			_menu.add_separator(str(entry[1]) if entry.size() > 1 else "")
			continue
		_menu.add_item(str(entry[1]), _ids.size())
		_ids.append(StringName(entry[0]))


func open_menu() -> void:
	opening.emit()
	_menu.reset_size()
	_menu.position = Vector2i(get_screen_position() + Vector2(0, size.y + 4))
	_menu.min_size.x = int(size.x)
	_menu.popup()
