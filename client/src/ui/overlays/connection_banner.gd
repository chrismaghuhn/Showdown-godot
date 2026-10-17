class_name ConnectionBanner
extends StatusBanner
## "Connection lost — reconnecting in 4 s · Attempt 2 of 5" under the app header (design:
## frame 03), and the "Reconnected · 2 battles restored." toast once the battles are back.

## Dev automation: a fixed Connection.status() to render instead of the live one.
var _preview := {}


func _ready() -> void:
	visible = false
	action_pressed.connect(func() -> void:
		if _preview.is_empty():
			Connection.retry_now())
	EventBus.connection_state_changed.connect(func(_s: int) -> void: _refresh())
	EventBus.reconnected.connect(_refresh)
	EventBus.battles_restored.connect(_on_battles_restored)
	var ticker := Timer.new()
	ticker.wait_time = 0.25
	ticker.autostart = true
	ticker.timeout.connect(_refresh)
	add_child(ticker)
	_refresh()


func preview(status: Dictionary) -> void:
	_preview = status
	_refresh()


func _refresh() -> void:
	var content := ConnectionFlow.banner_for(_preview if not _preview.is_empty() else Connection.status())
	visible = not content.is_empty()
	if visible:
		set_content(content["tone"], content["title"], content["sub"], content["action"])


func _on_battles_restored(count: int) -> void:
	EventBus.toast_requested.emit({
		"event": "reconnected", "title": tr("Reconnected"), "body": ConnectionFlow.restored_text(count),
		"key": "reconnected",
	})
