class_name ConnectionStatus
extends Button
## The connection status at the right of the app header (design: frame 03, "● Offline"):
## a colored dot and "Offline", "Connecting…", "Sign in" or the signed-in name. Clicking
## connects or opens the sign-in card; when signed in it offers "Sign out".

var _menu := PopupMenu.new()
var _dot: ImageTexture


func _init() -> void:
	theme_type_variation = &"GhostButton"
	focus_mode = Control.FOCUS_ALL
	_dot = _make_dot()
	icon = _dot
	pressed.connect(_on_pressed)
	_menu.add_item(tr("Sign out"), 0)
	_menu.id_pressed.connect(func(_id: int) -> void: Connection.sign_out())
	add_child(_menu)


func _ready() -> void:
	EventBus.connection_state_changed.connect(func(_s: int) -> void: _refresh())
	EventBus.logged_in.connect(func(_u: String) -> void: _refresh())
	EventBus.signed_out.connect(_refresh)
	EventBus.reconnected.connect(_refresh)
	EventBus.theme_changed.connect(func(_id: String) -> void: _refresh())
	var ticker := Timer.new()
	ticker.wait_time = 0.5
	ticker.autostart = true
	ticker.timeout.connect(_refresh)
	add_child(ticker)
	_refresh()


func _refresh() -> void:
	var label := ConnectionFlow.status_label(Connection.status())
	text = label["text"]
	var color := Themes.color(label["color_token"])
	for item in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		add_theme_color_override(item, color)
	var warning: bool = label["color_token"] == "color.warning.text"
	for item in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		if warning:
			add_theme_color_override(item, color)
		else:
			remove_theme_color_override(item)
	tooltip_text = tr("Connected to %s") % Connection.server_host() if Connection.state == Connection.State.CONNECTED \
		else tr("Connect to Showdown")


func _on_pressed() -> void:
	if Connection.state == Connection.State.CONNECTED and Connection.signed_in:
		_menu.position = Vector2i(get_screen_position() + Vector2(0, size.y))
		_menu.popup()
	else:
		EventBus.sign_in_requested.emit()


## An 8px dot, drawn at 2x so it stays round when scaled.
static func _make_dot() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
			image.set_pixel(x, y, Color(1, 1, 1, clampf(8.0 - d, 0.0, 1.0)))
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(8, 8))
	return texture
