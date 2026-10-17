class_name AppTabs
extends HBoxContainer
## The tabs in the app header (design: ".c-tab"): Home, Teambuilder, one tab per battle (dot
## filled = your move, ring = waiting; opponent and "OU · T7"), then closable pages such as
## Watch and Settings (icon, title, close button).

signal tab_selected(id: StringName)
signal tab_close_requested(id: StringName)

## id -> {button, title, meta, dot, icon, close}
var _tabs := {}
var _order: Array[StringName] = []
var _group := ButtonGroup.new()
var current: StringName = &""


func _init() -> void:
	add_theme_constant_override("separation", 0)
	_group.allow_unpress = false


func has_tab(id: StringName) -> bool:
	return _tabs.has(id)


func ids() -> Array[StringName]:
	return _order.duplicate()


## Adds a tab (or updates it if it exists). spec: {title, meta, dot ("" / "active" /
## "waiting"), icon, closable, tooltip}. A tab is inserted before `before` if given.
func add_tab(id: StringName, spec: Dictionary, before: StringName = &"") -> void:
	if _tabs.has(id):
		update_tab(id, spec)
		return
	var button := RichButton.new(&"AppTab", 12, 8 if spec.get("closable", false) else 12)
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = 40
	button.pressed.connect(func() -> void: _on_pressed(id))
	var dot := StatusDot.new()
	dot.visible = false
	var icon := IconView.new("", "color.text.secondary")
	icon.visible = false
	var title := RichButton.label("", &"TabLabel")
	var meta := RichButton.label("", &"TabMetaLabel")
	button.add(dot)
	button.add(icon)
	button.add(title)
	button.add(meta)
	var close: Button = null
	if spec.get("closable", false):
		close = Button.new()
		close.theme_type_variation = &"IconButton"
		close.icon = Icons.get_icon("ui-close")
		close.custom_minimum_size = Vector2(22, 22)
		close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		close.focus_mode = Control.FOCUS_NONE
		close.tooltip_text = tr("Close")
		close.pressed.connect(func() -> void: tab_close_requested.emit(id))
		button.add(close)
	_tabs[id] = {"button": button, "dot": dot, "icon": icon, "title": title, "meta": meta, "close": close}
	add_child(button)
	var index := _order.find(before) if before != &"" else -1
	if index >= 0:
		_order.insert(index, id)
		move_child(button, index)
	else:
		_order.append(id)
	update_tab(id, spec)


func update_tab(id: StringName, spec: Dictionary) -> void:
	if not _tabs.has(id):
		return
	var tab: Dictionary = _tabs[id]
	var title: Label = tab["title"]
	var meta: Label = tab["meta"]
	var icon: IconView = tab["icon"]
	var dot: StatusDot = tab["dot"]
	if spec.has("title"):
		title.text = str(spec["title"])
	if spec.has("meta"):
		meta.text = str(spec["meta"])
		meta.visible = not meta.text.is_empty()
	if spec.has("icon"):
		icon.icon_name = str(spec["icon"])
		icon.visible = not icon.icon_name.is_empty()
	if spec.has("dot"):
		var kind := str(spec["dot"])
		dot.visible = not kind.is_empty()
		dot.hollow = kind == "waiting"
		dot.color_token = "color.text.muted" if kind == "waiting" else "color.accent.text"
	if spec.has("tooltip"):
		(tab["button"] as Button).tooltip_text = str(spec["tooltip"])
	meta.visible = not meta.text.is_empty()


func remove_tab(id: StringName) -> void:
	if not _tabs.has(id):
		return
	var button: Button = _tabs[id]["button"]
	_tabs.erase(id)
	_order.erase(id)
	button.queue_free()
	if current == id:
		current = &""


## Marks a tab as selected without emitting tab_selected.
func select(id: StringName) -> void:
	current = id
	for tab_id: StringName in _tabs:
		var tab: Dictionary = _tabs[tab_id]
		var selected := tab_id == id
		(tab["button"] as Button).set_pressed_no_signal(selected)
		(tab["title"] as Label).theme_type_variation = &"DockTitleLabel" if selected else &"TabLabel"
		(tab["icon"] as IconView).color_token = "color.text.primary" if selected else "color.text.secondary"


func _on_pressed(id: StringName) -> void:
	select(id)
	tab_selected.emit(id)
