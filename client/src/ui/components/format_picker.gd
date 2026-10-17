class_name FormatPicker
extends RichButton
## A format dropdown (design: lobby "Format [Gen 9] OU ▾"): opens a searchable list grouped by
## the server's sections. Formats that need a team are shown but can't be picked until the
## Teambuilder exists (v0.2). Type to filter, Enter picks the first match, Esc closes.

signal format_selected(format_id: String)

enum Purpose { SEARCH, CHALLENGE }

var purpose := Purpose.SEARCH
var selected_id := ""
var _label := RichButton.label("", &"DockTitleLabel")
var _popup := PopupPanel.new()
var _search := LineEdit.new()
var _tree := Tree.new()


func _init(for_purpose := Purpose.SEARCH) -> void:
	super(&"Button", 12, 8)
	purpose = for_purpose
	min_width = 200
	custom_minimum_size.y = 40
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size.x = 120
	add(_label)
	add(IconView.new("ui-chevron-down", "color.text.secondary"))
	pressed.connect(open)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 360)
	_popup.add_child(column)
	_search.placeholder_text = tr("Search formats")
	_search.right_icon = null
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	_search.text_submitted.connect(func(_t: String) -> void: _pick_first())
	_search.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_DOWN:
			_tree.grab_focus()
			var first := _first_selectable(_tree.get_root())
			if first != null:
				first.select(0)
			_search.accept_event())
	column.add_child(_search)
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(func() -> void: _pick(_tree.get_selected()))
	_tree.item_mouse_selected.connect(func(_p: Vector2, _b: int) -> void: _pick(_tree.get_selected()))
	column.add_child(_tree)
	add_child(_popup)


func _ready() -> void:
	EventBus.formats_changed.connect(_refresh_label)
	_refresh_label()


func select(format_id: String) -> void:
	selected_id = format_id
	_refresh_label()


func open() -> void:
	_search.clear()
	_fill()
	_popup.reset_size()
	_popup.position = Vector2i(get_screen_position() + Vector2(0, size.y + 4))
	_popup.popup()
	_search.grab_focus()


## The formats for this picker: [{id, name, section, enabled, note}] in server order.
static func entries(formats: Array[Dictionary], picker_purpose: Purpose, query: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var words := query.to_lower().split(" ", false)
	for format in formats:
		if not format["search" if picker_purpose == Purpose.SEARCH else "challenge"]:
			continue
		var haystack := ("%s %s" % [format["name"], format["section"]]).to_lower()
		var matches := true
		for word in words:
			if not haystack.contains(word):
				matches = false
				break
		if not matches:
			continue
		result.append({"id": format["id"], "name": format["name"], "section": format["section"],
			"enabled": format["preset_team"],
			"note": "" if format["preset_team"] else TranslationServer.translate("needs a team · Teambuilder in v0.2")})
	return result


func _fill() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var sections := {}
	for entry in entries(Rooms.formats, purpose, _search.text):
		var section := str(entry["section"])
		if not sections.has(section):
			var header := _tree.create_item(root)
			header.set_text(0, section)
			header.set_selectable(0, false)
			header.set_custom_color(0, Themes.color("color.text.muted"))
			sections[section] = header
		var item := _tree.create_item(sections[section])
		item.set_text(0, str(entry["name"]) + ("  ·  " + str(entry["note"]) if not str(entry["note"]).is_empty() else ""))
		item.set_metadata(0, entry["id"])
		item.set_selectable(0, entry["enabled"])
		if not entry["enabled"]:
			item.set_custom_color(0, Themes.color("color.text.disabled"))
		elif entry["id"] == selected_id:
			item.select(0)
	if sections.is_empty():
		var empty := _tree.create_item(root)
		empty.set_text(0, tr("No formats match") if not Rooms.formats.is_empty() else tr("Connect to see the server's formats"))
		empty.set_selectable(0, false)


func _pick_first() -> void:
	_pick(_first_selectable(_tree.get_root()))


func _first_selectable(item: TreeItem) -> TreeItem:
	if item == null:
		return null
	for child in item.get_children():
		if child.is_selectable(0):
			return child
		var nested := _first_selectable(child)
		if nested != null:
			return nested
	return null


func _pick(item: TreeItem) -> void:
	if item == null or not item.is_selectable(0) or item.get_metadata(0) == null:
		return
	selected_id = str(item.get_metadata(0))
	_popup.hide()
	_refresh_label()
	format_selected.emit(selected_id)


func _refresh_label() -> void:
	var name := FormatList.display_name(Rooms.formats, selected_id)
	if name.is_empty():
		name = str(AppConfig.get_setting("play", "last_format_name", selected_id)) \
			if selected_id == str(AppConfig.get_setting("play", "last_format", "")) else selected_id
	if name.is_empty() and selected_id == QuickBattleCard.DEFAULT_FORMAT:
		name = "[Gen 9] Random Battle"
	_label.text = name if not name.is_empty() else tr("Choose a format")
