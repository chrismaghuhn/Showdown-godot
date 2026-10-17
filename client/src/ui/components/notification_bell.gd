class_name NotificationBell
extends Button
## The bell in the app header: a red dot while there are unread notifications, and on click the
## recent ones (Notifier.history), newest first. Opening it marks everything read.

signal open_screen(screen: StringName)

const SHOWN := 10

var _dot := StatusDot.new("color.danger.text", false, 7.0)
var _popup := PopupPanel.new()
var _list := VBoxContainer.new()


func _init() -> void:
	theme_type_variation = &"IconButton"
	icon = Icons.get_icon("ui-notify")
	custom_minimum_size = Vector2(28, 28)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.ring_token = "color.surface.panel"
	_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dot.position = Vector2(17, 4)
	add_child(_dot)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 320
	column.add_theme_constant_override("separation", 8)
	_popup.add_child(column)
	var head := HBoxContainer.new()
	var title := RichButton.label(tr("Notifications"), &"DockTitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var clear := StateCard.make_button(tr("Clear"), &"SmallGhostButton", func() -> void:
		Notifier.clear_history()
		_rebuild())
	head.add_child(clear)
	column.add_child(head)
	_list.add_theme_constant_override("separation", 4)
	column.add_child(_list)
	add_child(_popup)
	pressed.connect(_open)


func _ready() -> void:
	EventBus.notifications_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_dot.visible = Notifier.unread > 0
	tooltip_text = tr("Notifications, %d new") % Notifier.unread if Notifier.unread > 0 else tr("Notifications")


func _open() -> void:
	_rebuild()
	Notifier.mark_all_read()
	_popup.reset_size()
	_popup.position = Vector2i(get_screen_position() + Vector2(size.x - 320, size.y + 4))
	_popup.popup()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	if Notifier.history.is_empty():
		_list.add_child(RichButton.label(tr("Nothing yet. Battles, challenges and mentions show up here."), &"MutedLabel"))
		return
	var now := int(Time.get_unix_time_from_system())
	for i in mini(Notifier.history.size(), SHOWN):
		var entry: Dictionary = Notifier.history[i]
		var item := RichButton.new(&"GhostButton", 8, 8)
		item.custom_minimum_size.y = 44
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := RichButton.label(str(entry["title"]), &"DockTitleLabel")
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(title)
		var body := RichButton.label(str(entry["body"]), &"MutedLabel")
		body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(body)
		item.add(IconView.new(ToastStack.EVENT_ICONS.get(entry["event"], "ui-notify"),
			ToastStack.EVENT_COLORS.get(entry["event"], "color.text.secondary")))
		item.add(text)
		item.add(RichButton.label(time_ago(now - int(entry["time"])), &"MutedLabel"))
		var screen := str(entry.get("screen", ""))
		item.disabled = screen.is_empty()
		item.pressed.connect(func() -> void:
			_popup.hide()
			open_screen.emit(StringName(screen)))
		_list.add_child(item)


## 30 -> "now", 300 -> "5 min", 7200 -> "2 h", 200000 -> "2 d"
static func time_ago(seconds: int) -> String:
	if seconds < 60:
		return TranslationServer.translate("now")
	if seconds < 3600:
		return TranslationServer.translate("%d min") % (seconds / 60)
	if seconds < 86400:
		return TranslationServer.translate("%d h") % (seconds / 3600)
	return TranslationServer.translate("%d d") % (seconds / 86400)
