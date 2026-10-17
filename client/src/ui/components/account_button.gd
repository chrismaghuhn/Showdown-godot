class_name AccountButton
extends RichButton
## The account in the app header (design: avatar with initials, name and a second line): signed
## in, a guest, or offline. Its menu signs in or out and leads to the start screen. Ratings
## come with the lobby (#23); until then the second line names the server.

signal start_screen_requested

enum Item { SIGN_IN, SIGN_OUT, STAY_SIGNED_IN, START_SCREEN, QUIT }

var _avatar := PanelContainer.new()
var _initials := Label.new()
var _name := Label.new()
var _sub := Label.new()
var _menu := PopupMenu.new()


func _init() -> void:
	super(&"HeaderButton", 4, 4)
	custom_minimum_size.y = 32
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.theme_type_variation = &"AvatarPanel"
	_avatar.custom_minimum_size = Vector2(28, 28)
	_initials.theme_type_variation = &"AvatarLabel"
	_initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar.add_child(_initials)
	add(_avatar)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name.theme_type_variation = &"SmallBoldLabel"
	_sub.theme_type_variation = &"TabMetaLabel"
	text.add_child(_name)
	text.add_child(_sub)
	add(text)
	pressed.connect(_open_menu)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func _ready() -> void:
	EventBus.connection_state_changed.connect(func(_s: int) -> void: refresh())
	EventBus.logged_in.connect(func(_u: String) -> void: refresh())
	EventBus.signed_out.connect(refresh)
	EventBus.reconnected.connect(refresh)
	refresh()


func refresh() -> void:
	var view := describe(Connection.status(), str(AppConfig.get_setting("account", "username", "")))
	_initials.text = view["initials"]
	_name.text = view["name"]
	_sub.text = view["sub"]
	tooltip_text = tr("Account: %s") % view["name"]


## {initials, name, sub} for the header, from Connection.status().
static func describe(status: Dictionary, remembered: String) -> Dictionary:
	var host := str(status.get("server_host", "")).get_slice(".", 0).get_slice(":", 0)
	if status.get("signed_in", false):
		var name := str(status.get("username", ""))
		return {"initials": initials(name), "name": name, "sub": host}
	if int(status.get("state", 0)) == Connection.State.CONNECTED:
		return {"initials": "?", "name": str(TranslationServer.translate("Guest")),
			"sub": str(TranslationServer.translate("Sign in"))}
	var offline_name := remembered if not remembered.is_empty() else str(TranslationServer.translate("Offline"))
	return {"initials": initials(remembered) if not remembered.is_empty() else "–", "name": offline_name,
		"sub": str(TranslationServer.translate("Not connected"))}


## "Iron Quill" -> "IQ", "ironquill" -> "IR", "x" -> "X".
static func initials(name: String) -> String:
	var words := name.strip_edges().split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return words[0].left(2).to_upper()


func _open_menu() -> void:
	_menu.clear()
	if Connection.signed_in:
		_menu.add_item(tr("Sign out"), Item.SIGN_OUT)
	else:
		_menu.add_item(tr("Sign in…"), Item.SIGN_IN)
	_menu.add_check_item(tr("Stay signed in"), Item.STAY_SIGNED_IN)
	_menu.set_item_checked(_menu.get_item_index(Item.STAY_SIGNED_IN), Connection.stay_signed_in)
	_menu.add_separator()
	_menu.add_item(tr("Start screen"), Item.START_SCREEN)
	_menu.add_item(tr("Quit"), Item.QUIT)
	_menu.reset_size()
	_menu.position = Vector2i(get_screen_position() + Vector2(size.x - _menu.size.x, size.y + 4))
	_menu.popup()


func _on_menu(id: int) -> void:
	match id:
		Item.SIGN_IN:
			EventBus.sign_in_requested.emit()
		Item.SIGN_OUT:
			Connection.sign_out()
		Item.STAY_SIGNED_IN:
			Connection.set_stay_signed_in(not Connection.stay_signed_in)
		Item.START_SCREEN:
			start_screen_requested.emit()
		Item.QUIT:
			get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			get_tree().quit()
