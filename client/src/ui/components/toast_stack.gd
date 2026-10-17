class_name ToastStack
extends VBoxContainer
## In-app toasts (design: Components › Toast notification): bottom-right stack, newest on top,
## at most toast.max. Info toasts close after toast.lifetime.info (with actions:
## toast.lifetime.action); "your turn", challenges and timer warnings stay until handled.
## Hovering a toast pauses its timer.

const EVENT_ICONS := {
	"battle_found": "ui-battle", "your_turn": "ui-notify", "timer_low": "ui-timer",
	"challenge": "ui-user-plus", "mention": "ui-chat", "private_message": "ui-inbox", "battle_ended": "ui-check-circle",
}


func _init() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size.x = 360
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	EventBus.toast_requested.connect(show_toast)
	EventBus.toast_dismissed.connect(dismiss)


func show_toast(toast: Dictionary) -> void:
	var key := str(toast.get("key", ""))
	if not key.is_empty():
		dismiss(key)
	var panel := _build(toast)
	add_child(panel)
	move_child(panel, 0)
	var max_toasts := maxi(int(Themes.tokens.num("toast.max")) if Themes.tokens != null else 3, 1)
	# Closing toasts stay children until their exit fade ends, so count only the open ones.
	var open := get_children().filter(func(child: Node) -> bool: return not child.get_meta("closing", false))
	while open.size() > max_toasts:
		_close(open.pop_back())  # oldest is at the bottom
	# Enter: fade + short slide (instant slide, short fade with reduce motion).
	panel.modulate.a = 0.0
	var tween := panel.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, Themes.fade("motion.slow"))
	if not toast.get("persistent", false):
		var lifetime_key := "toast.lifetime.action" if not (toast.get("actions", []) as Array).is_empty() else "toast.lifetime.info"
		var seconds := Themes.tokens.num(lifetime_key) if Themes.tokens != null else 5.0
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = seconds
		timer.timeout.connect(_close.bind(panel))
		panel.add_child(timer)
		timer.start()
		panel.mouse_entered.connect(func() -> void: timer.paused = true)
		panel.mouse_exited.connect(func() -> void: timer.paused = false)


## Removes the toast with this key, if shown.
func dismiss(key: String) -> void:
	for child in get_children():
		if child.get_meta("key", "") == key:
			_close(child)


func _close(panel: Node) -> void:
	if not is_instance_valid(panel) or panel.get_meta("closing", false):
		return
	panel.set_meta("closing", true)
	var duration := Themes.fade("motion.base") * 2.0 / 3.0  # exits run at 2/3 of the enter duration
	if duration <= 0.0:
		panel.queue_free()
		return
	var tween := panel.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, duration)
	tween.tween_callback(panel.queue_free)


func _build(toast: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"OverlayPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("key", str(toast.get("key", "")))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	head.add_child(IconView.new(EVENT_ICONS.get(toast.get("event", ""), "ui-notify"), "color.text.primary"))
	var title := Label.new()
	title.text = str(toast.get("title", ""))
	title.theme_type_variation = &"DockTitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title)
	var time := Label.new()
	time.text = tr("now")
	time.theme_type_variation = &"MutedLabel"
	head.add_child(time)
	var close := Button.new()
	close.theme_type_variation = &"IconButton"
	close.icon = Icons.get_icon("ui-close")
	close.tooltip_text = tr("Dismiss")
	close.pressed.connect(_close.bind(panel))
	head.add_child(close)

	var body_text := str(toast.get("body", ""))
	if not body_text.is_empty():
		var body := Label.new()
		body.text = body_text
		body.theme_type_variation = &"SecondaryLabel"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.max_lines_visible = 3
		body.custom_minimum_size.x = 320
		column.add_child(body)

	var actions: Array = toast.get("actions", [])
	if not actions.is_empty():
		var row := HBoxContainer.new()
		column.add_child(row)
		for i in actions.size():
			var action: Array = actions[i]
			var button := Button.new()
			button.text = str(action[0])
			button.theme_type_variation = &"PrimaryButton" if i == 0 else &"GhostButton"
			var callback: Callable = action[1] if action.size() > 1 else Callable()
			button.pressed.connect(func() -> void:
				if callback.is_valid():
					callback.call()
				_close(panel))
			row.add_child(button)
	return panel
