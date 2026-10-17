class_name ConnectionStatus
extends RichButton
## The connection pill in the app header (design: start screen "● Online · sim3", frame 03
## "● Offline"). Clicking it connects, retries or opens the sign-in card.

var _dot := StatusDot.new("color.text.muted")
var _text := RichButton.label("", &"SmallBoldLabel")


func _init() -> void:
	super(&"StatusPill", 8, 12)
	custom_minimum_size.y = 28
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add(_dot)
	add(_text)
	pressed.connect(func() -> void: EventBus.sign_in_requested.emit())


func _ready() -> void:
	EventBus.connection_state_changed.connect(func(_s: int) -> void: _refresh())
	EventBus.logged_in.connect(func(_u: String) -> void: _refresh())
	EventBus.signed_out.connect(_refresh)
	EventBus.reconnected.connect(_refresh)
	var ticker := Timer.new()
	ticker.wait_time = 0.5
	ticker.autostart = true
	ticker.timeout.connect(_refresh)
	add_child(ticker)
	_refresh()


## True when the pill has something to say in the main header (it always shows on the start
## screen): offline, connecting or reconnecting.
func needs_attention() -> bool:
	var status := Connection.status()
	return status["state"] != Connection.State.CONNECTED or status["reconnecting"] or not status["session_up"]


func _refresh() -> void:
	var label := ConnectionFlow.status_label(Connection.status())
	_text.text = label["text"]
	_dot.color_token = label["color_token"]
	tooltip_text = tr("Connected to %s") % Connection.server_host() if Connection.state == Connection.State.CONNECTED \
		else tr("Connect to Showdown")
