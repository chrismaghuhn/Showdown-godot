class_name ConnectionOverlay
extends Control
## The modal connection cards over the whole app (design: "03 · Motion & app states", frames
## 01, 02 and the blocking error of 05): connecting, choosing a server, signing in, and
## "couldn't connect". ConnectionFlow.card_for() decides which one; reconnecting after a
## drop uses the banner instead (ConnectionBanner).

const DEFAULT_SERVER := "official"

## quiet: connecting in the background at launch - no modal card until the user asks or a
## sign-in needs them (the header shows the status).
var _ui := {"servers_open": false, "sign_in_open": false, "dismissed": false, "quiet": false}
var _card_id := &""
var _card: Control
var _scrim := PanelContainer.new()
var _center := CenterContainer.new()
var _attempt_label: Label
var _sign_in: SignInCard
## The registered name that needs a password ("" = name step), and the inline error.
var _password_for := ""
var _error := ""
## The name last sent from the card, shown again after an error.
var _typed_name := ""
## Dev automation: a fixed Connection.status() to render instead of the live one.
var _preview := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.theme_type_variation = &"Scrim"
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	add_child(_scrim)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	EventBus.connection_state_changed.connect(_on_state_changed)
	EventBus.logged_in.connect(func(_u: String) -> void:
		_password_for = ""
		_error = ""
		_ui["sign_in_open"] = false
		_refresh())
	EventBus.login_failed.connect(func(reason: String) -> void:
		_error = reason
		_ui["sign_in_open"] = true
		_refresh(true))
	EventBus.password_required.connect(func(name: String) -> void:
		_password_for = name
		_error = ""
		_ui["sign_in_open"] = true
		_refresh(true))
	EventBus.signed_out.connect(func() -> void: _refresh())
	EventBus.reconnected.connect(func() -> void: _refresh())
	EventBus.sign_in_requested.connect(open_sign_in)
	var ticker := Timer.new()
	ticker.wait_time = 0.25
	ticker.autostart = true
	ticker.timeout.connect(_refresh)
	add_child(ticker)
	_refresh()
	if should_auto_connect():
		_connect.call_deferred(str(AppConfig.get_setting("connection", "server", "")), true)


## "Stay signed in" with a saved session or name connects to the last server on launch, in
## the background. Not in headless runs, dev automation (--server, --screenshot,
## --app-state) or with --offline.
static func should_auto_connect() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for flag in ["server", "screenshot", "app-state", "offline"]:
		if AppConfig.has_cli(flag):
			return false
	var server_id := str(AppConfig.get_setting("connection", "server", ""))
	var api := str(AppConfig.get_server(server_id).get("login", "none"))
	var has_session := api != "none" and not SessionStore.load_cookie(api).is_empty()
	var has_name := not str(AppConfig.get_setting("account", "username", "")).is_empty()
	return wants_auto_connect(Connection.stay_signed_in, server_id, has_session or has_name)


## There's something to sign in with: a session cookie or a remembered name.
static func wants_auto_connect(stay_signed_in: bool, server_id: String, has_saved_sign_in: bool) -> bool:
	return stay_signed_in and not AppConfig.get_server(server_id).is_empty() and has_saved_sign_in


## Opens the next step: connect when offline, else the sign-in card.
func open_sign_in() -> void:
	_ui["dismissed"] = false
	_ui["quiet"] = false
	match Connection.state:
		Connection.State.DISCONNECTED:
			_connect(str(AppConfig.get_setting("connection", "server", DEFAULT_SERVER)))
		Connection.State.WAITING:
			Connection.retry_now()
		Connection.State.CONNECTED:
			if not Connection.signed_in:
				_ui["sign_in_open"] = true
	_refresh(true)


## Dev automation: shows `card` for a made-up status (see DevAutomation --app-state).
func preview(status: Dictionary, ui: Dictionary, password_for := "", error := "") -> void:
	_preview = status
	_ui.merge(ui, true)
	_password_for = password_for
	_error = error
	_refresh(true)


func current_card() -> StringName:
	return _card_id


func _status() -> Dictionary:
	return _preview if not _preview.is_empty() else Connection.status()


func _on_state_changed(state: int) -> void:
	# A new series of attempts (not an automatic retry) asks again after "Not now".
	if state == Connection.State.CONNECTING and Connection.attempt == 1 and not Connection.reconnecting:
		_ui["dismissed"] = false
		_ui["sign_in_open"] = false
		_error = ""
	if state == Connection.State.CONNECTED and Connection.signed_in:
		_ui["quiet"] = false
	_refresh()


func _refresh(rebuild := false) -> void:
	var status := _status()
	var card := ConnectionFlow.card_for(status, _ui)
	if card != _card_id or rebuild:
		_show_card(card, status)
	elif _card_id == &"connecting" and _attempt_label != null:
		_attempt_label.text = ConnectionFlow.attempt_line(status)
	elif _card_id == &"sign_in" and _sign_in != null:
		_sign_in.set_busy(status.get("signing_in", false))


func _show_card(card_id: StringName, status: Dictionary) -> void:
	var previous := _card_id
	_card_id = card_id
	if _card != null:
		_card.queue_free()
		_card = null
	_attempt_label = null
	_sign_in = null
	_scrim.visible = card_id != &""
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP if card_id != &"" else Control.MOUSE_FILTER_IGNORE
	match card_id:
		&"connecting":
			_card = _build_connecting(status)
		&"servers":
			_card = _build_servers()
		&"sign_in":
			_card = _build_sign_in(status)
		&"gave_up":
			_card = _build_gave_up(status)
	if _card == null:
		return
	_center.add_child(_card)
	if previous == &"":
		_card.modulate.a = 0.0
		var tween := _card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_card, "modulate:a", 1.0, Themes.fade("motion.base"))
	if _sign_in != null:
		_sign_in.focus_first.call_deferred()


# --- Cards ------------------------------------------------------------------------------------

func _build_connecting(status: Dictionary) -> Control:
	var card := StateCard.new()
	card.rows.add_child(AppLogo.new(40))
	var title_row := card.add_row(true)
	title_row.add_child(Spinner.new("color.text.secondary"))
	var title := Label.new()
	title.text = tr("Connecting to Showdown…")
	title.theme_type_variation = &"CardTitleLabel"
	title_row.add_child(title)
	_attempt_label = card.add_text(ConnectionFlow.attempt_line(status), &"SecondaryLabel", true)
	var buttons := card.add_row(true)
	buttons.add_child(StateCard.make_button(tr("Work offline"), &"Button", _work_offline))
	buttons.add_child(StateCard.make_button(tr("Change server"), &"GhostButton", func() -> void:
		_ui["servers_open"] = true
		_refresh()))
	card.add_text(tr("Offline: Teambuilder, replays and plugins still work."), &"MutedLabel", true)
	return card


func _build_servers() -> Control:
	var card := StateCard.new()
	card.add_title(tr("Choose a server"))
	for id: String in AppConfig.SERVERS:
		var server: Dictionary = AppConfig.SERVERS[id]
		var button := Button.new()
		button.theme_type_variation = &"SlotButton"
		button.toggle_mode = true
		button.button_pressed = id == Connection.server_id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = str(server["name"])
		button.tooltip_text = str(server["url"])
		button.pressed.connect(func() -> void:
			_ui["servers_open"] = false
			_connect(id))
		card.rows.add_child(button)
	var buttons := card.add_row()
	buttons.add_child(StateCard.make_button(tr("Back"), &"GhostButton", func() -> void:
		_ui["servers_open"] = false
		_refresh()))
	return card


func _build_sign_in(status: Dictionary) -> Control:
	_sign_in = SignInCard.new()
	var name := _typed_name
	if name.is_empty():
		name = str(status.get("session_name", ""))
	if name.is_empty():
		name = str(AppConfig.get_setting("account", "username", ""))
	_sign_in.setup(name, _password_for, _error, Connection.stay_signed_in, status.get("signing_in", false))
	_sign_in.submitted.connect(_on_sign_in_submitted)
	_sign_in.dismissed.connect(func() -> void:
		_ui["sign_in_open"] = false
		_ui["dismissed"] = true
		# "Battle!" or a challenge while signed out waits for a name; "Not now" means: neither.
		Rooms.drop_pending()
		Rooms.cancel_search()
		_error = ""
		_refresh())
	_sign_in.other_name.connect(func() -> void:
		_password_for = ""
		_typed_name = ""
		_error = ""
		_refresh(true)
		if _sign_in != null:
			_sign_in.clear_name())
	return _sign_in


func _build_gave_up(status: Dictionary) -> Control:
	var text := tr("%s didn’t answer after %d attempts.") % [status.get("server_host", ""), int(status.get("max_attempts", 5))]
	var box := ErrorBox.blocking(tr("Couldn’t connect to Showdown"), text, [
		[tr("Try again"), func() -> void: Connection.retry_now()],
		[tr("Work offline"), _work_offline],
		[tr("Change server"), func() -> void:
			_ui["servers_open"] = true
			_refresh()],
	])
	box.custom_minimum_size.x = StateCard.WIDTH
	box.tooltip_text = str(status.get("last_error", ""))
	return box


# --- Actions ----------------------------------------------------------------------------------

func _connect(server_id: String, quiet := false) -> void:
	if AppConfig.get_server(server_id).is_empty():
		server_id = DEFAULT_SERVER
	_ui["quiet"] = quiet
	AppConfig.set_setting("connection", "server", server_id)
	_preview = {}
	Connection.connect_to_server(server_id)


func _work_offline() -> void:
	Rooms.drop_pending()
	Rooms.cancel_search()
	_ui["servers_open"] = false
	_preview = {}
	Connection.disconnect_from_server()
	_refresh()


func _on_sign_in_submitted(name: String, password: String, stay: bool) -> void:
	_error = ""
	if stay != Connection.stay_signed_in:
		Connection.set_stay_signed_in(stay)
	if _password_for != "" and PSParser.to_id(name) != PSParser.to_id(_password_for):
		_password_for = ""
	_typed_name = name
	# Keep the card open (busy) while this sign-in runs.
	_ui["sign_in_open"] = true
	Connection.login(name, password)
	_refresh()
