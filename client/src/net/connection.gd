extends Node
## Autoload "Connection": the websocket to the Showdown server, sign-in, and reconnecting.
##
## Incoming frames are parsed and published as EventBus.message_received.
## Everything that interprets messages beyond connection/login lives elsewhere (e.g. Rooms).
##
## Reconnecting: when the socket closes, or an attempt doesn't open, without
## disconnect_from_server(), the next attempt is scheduled with ReconnectPolicy (state
## WAITING). A dead link without a close (pulled cable) is noticed by the websocket
## heartbeat. Once the server answers again the client signs in again with the same name
## (no password: the session cookie or the unregistered name) and emits
## EventBus.reconnected; Rooms then restores the battles.

## WAITING: the connection is gone and the next attempt is scheduled (see retry_in()).
## New states are only ever appended - plugins see the number in connection_state_changed.
enum State { DISCONNECTED, CONNECTING, CONNECTED, WAITING }

## Websocket ping interval. A ping without pong closes the socket (Godot's heartbeat), so a
## dead link is noticed after about one to two intervals. Tests shorten it with --heartbeat=2.
const HEARTBEAT_SEC := 10.0
## An attempt that hasn't reached |challstr| after this long counts as failed.
const CONNECT_TIMEOUT_SEC := 12.0
## A socket stuck in the closing handshake this long counts as closed.
const CLOSING_TIMEOUT_SEC := 5.0
## After a reconnect the server may still hold the old connection, and with it the name.
const RENAME_RETRY_SEC := 5.0
const RENAME_RETRIES := 6
## A session that drops sooner than this (and wasn't signed in yet) counts as a failed
## attempt, so a server that accepts and then closes right away is eventually given up on.
const STABLE_SESSION_SEC := 10.0

var state: State = State.DISCONNECTED
var server_id := ""
var challstr := ""
## The name on the server right now ("Guest 123" until signed in).
var username := ""
## True once the server confirmed a chosen name (|updateuser| with named = 1).
var signed_in := false
## A sign-in is running (login server request, or /trn sent and no answer yet).
var signing_in := false
## The name to sign in with again after a reconnect ("" = stay a guest).
var session_name := ""
## 1-based number of the running (CONNECTING) or next (WAITING) attempt.
var attempt := 0
## True while recovering a session that was established before (banner, not the card).
var reconnecting := false
## True after the last allowed attempt failed; retry_now() starts over.
var gave_up := false
var last_error := ""
## Keep the session cookie and the name across restarts (settings: account/stay_signed_in).
var stay_signed_in := false

var _ws: WebSocketPeer
## Outgoing messages wait here when the throttle says "not yet" (see SendThrottle).
var _outbox: Array[String] = []
var _throttle := SendThrottle.new()
## Tests send through this instead of the websocket.
var _transport := Callable()
var _login := LoginClient.new()
var _pending_login := {}
var _retry_at_msec := 0
var _attempt_started_msec := 0
var _closing_since_msec := -1
## |challstr| arrived on this socket: the server accepted the connection.
var _session_up := false
var _session_started_msec := 0
## The running sign-in restores the session after a reconnect.
var _relogin := false
var _rename_retries := 0
## Bumped whenever the socket is replaced, so late timers can tell they're stale.
var _socket_gen := 0


func _ready() -> void:
	add_child(_login)
	_login.assertion_ready.connect(_on_assertion_ready)
	_login.password_required.connect(_on_password_required)
	_login.failed.connect(_on_login_failed)
	_login.session_changed.connect(_on_session_changed)
	_login.session_expired.connect(_on_session_expired)
	stay_signed_in = bool(AppConfig.get_setting("account", "stay_signed_in", false))


# --- Public API -----------------------------------------------------------------------

func connect_to_server(id: String) -> void:
	var server := AppConfig.get_server(id)
	if server.is_empty():
		last_error = "Unknown server '%s'" % id
		EventBus.connection_error.emit(last_error)
		return
	_close_socket()
	_reset_session()
	server_id = id
	session_name = ""
	attempt = 1
	reconnecting = false
	gave_up = false
	last_error = ""
	_relogin = false
	_rename_retries = 0
	_pending_login.clear()
	var api := api_base()
	_login.session_cookie = SessionStore.load_cookie(api) if stay_signed_in and not api.is_empty() else ""
	_open()


## Closes the connection on purpose ("Work offline", "Disconnect"): no reconnect.
func disconnect_from_server() -> void:
	_close_socket()
	_reset_session()
	_pending_login.clear()
	_relogin = false
	attempt = 0
	reconnecting = false
	gave_up = false
	_set_state(State.DISCONNECTED, true)


## Skips the countdown, or starts a new series of attempts after giving up.
func retry_now() -> void:
	if server_id.is_empty() or state == State.CONNECTED or state == State.CONNECTING:
		return
	if gave_up or state == State.DISCONNECTED:
		attempt = 1
		gave_up = false
	_open()


## Seconds until the next attempt while WAITING, else 0.
func retry_in() -> float:
	if state != State.WAITING:
		return 0.0
	return maxf((_retry_at_msec - Time.get_ticks_msec()) / 1000.0, 0.0)


## Sends `text` to a room. Use room_id "" for global commands like /search or /trn.
## Messages go out at the server's pace (SendThrottle) and in order; line breaks become
## spaces, because the server runs every line of a message as its own command.
func send(room_id: String, text: String) -> void:
	if state != State.CONNECTED:
		push_warning("Connection.send() while not connected: " + text)
		return
	var line := room_id.replace("|", "").replace("\n", "").replace("\r", "") + "|" \
		+ text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
	_outbox.append(line)
	_flush_outbox()


## Sends what the throttle allows right now; the rest waits for _process.
func _flush_outbox() -> void:
	var now := Time.get_ticks_msec()
	while not _outbox.is_empty() and _throttle.take(now):
		var line: String = _outbox.pop_front()
		if _transport.is_valid():
			_transport.call(line)
		elif _ws != null:
			_ws.send_text(line)


## Sends a battle decision, e.g. choose("battle-gen9randombattle-1", "move 2", 3).
func choose(room_id: String, choice: String, rqid := -1) -> void:
	send(room_id, "/choose %s|%d" % [choice, rqid] if rqid >= 0 else "/choose " + choice)
	if state == State.CONNECTED:
		EventBus.choice_sent.emit(room_id, choice)


## Takes the last choice back while the turn hasn't started.
func undo_choice(room_id: String) -> void:
	send(room_id, "/undo")
	if state == State.CONNECTED:
		EventBus.choice_undone.emit(room_id)


## Signs in as soon as the server's challstr is known. Empty password = an unregistered name
## (or the registered name the session cookie belongs to).
func login(name: String, password := "") -> void:
	_pending_login = {"name": name, "password": password}
	if _session_up:
		_start_login()


## Ends the login server session, forgets the saved one and becomes a guest.
func sign_out() -> void:
	var api := api_base()
	if not api.is_empty():
		_login.logout(api, PSParser.to_id(username))
		SessionStore.clear(api)
	session_name = ""
	signing_in = false
	# Signing out also means: don't sign in again on the next start.
	AppConfig.set_setting("account", "username", "")
	if state == State.CONNECTED and signed_in:
		send("", "/logout")
	signed_in = false
	EventBus.signed_out.emit()


func set_stay_signed_in(enabled: bool) -> void:
	stay_signed_in = enabled
	AppConfig.set_setting("account", "stay_signed_in", enabled)
	var api := api_base()
	if not enabled:
		AppConfig.set_setting("account", "username", "")
		if not api.is_empty():
			SessionStore.clear(api)
	elif not api.is_empty() and not _login.session_cookie.is_empty():
		SessionStore.save_cookie(api, _login.session_cookie)


## "sim3.psim.us", or "localhost:8000" for a non-standard port.
func server_host() -> String:
	var url := str(AppConfig.get_server(server_id).get("url", ""))
	var host := url.get_slice("://", 1).get_slice("/", 0)
	return host.trim_suffix(":443").trim_suffix(":80")


## The login server's API base URL, or "" for servers without one (--no-security).
func api_base() -> String:
	var mode := str(AppConfig.get_server(server_id).get("login", "none"))
	return "" if mode == "none" else mode


## Everything the connection UI needs, in one dictionary (see ConnectionFlow.view_for()).
func status() -> Dictionary:
	return {
		"state": state, "attempt": attempt, "max_attempts": ReconnectPolicy.MAX_ATTEMPTS,
		"retry_in": retry_in(), "reconnecting": reconnecting, "gave_up": gave_up,
		"session_up": _session_up, "signed_in": signed_in,
		"signing_in": signing_in or not _pending_login.is_empty(),
		"username": username, "session_name": session_name, "server_host": server_host(),
		"last_error": last_error,
	}


# --- Socket -----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if state == State.WAITING:
		if Time.get_ticks_msec() >= _retry_at_msec:
			_open()
		return
	if _ws == null:
		return
	_ws.poll()
	var ready := _ws.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN:
		var gen := _socket_gen
		if state != State.CONNECTED:
			_set_state(State.CONNECTED)
		while gen == _socket_gen and _ws.get_available_packet_count() > 0:
			_handle_frame(_ws.get_packet().get_string_from_utf8())
		if gen != _socket_gen:
			return
		if not _outbox.is_empty():
			_flush_outbox()
	elif ready == WebSocketPeer.STATE_CLOSED:
		var reason := _ws.get_close_reason()
		_on_socket_lost(reason if not reason.is_empty() else tr("The connection closed (code %d)") % _ws.get_close_code())
		return
	elif ready == WebSocketPeer.STATE_CLOSING:
		if _closing_since_msec < 0:
			_closing_since_msec = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _closing_since_msec > CLOSING_TIMEOUT_SEC * 1000:
			_on_socket_lost(tr("The connection closed"))
			return
	if not _session_up and Time.get_ticks_msec() - _attempt_started_msec > CONNECT_TIMEOUT_SEC * 1000:
		_on_socket_lost(tr("%s did not answer") % server_host())


func _open() -> void:
	var server := AppConfig.get_server(server_id)
	_close_socket()
	_ws = WebSocketPeer.new()
	# Some messages (|formats|, |request|, replays) are larger than the default buffer.
	_ws.inbound_buffer_size = 4 * 1024 * 1024
	_ws.max_queued_packets = 4096
	_ws.heartbeat_interval = AppConfig.cli("heartbeat", str(HEARTBEAT_SEC)).to_float()
	_ws.handshake_headers = PackedStringArray([LoginClient.user_agent()])
	_attempt_started_msec = Time.get_ticks_msec()
	_closing_since_msec = -1
	_set_state(State.CONNECTING)
	var err := _ws.connect_to_url(str(server.get("url", "")))
	if err != OK:
		_on_socket_lost(tr("Could not connect to %s (error %d)") % [server_host(), err])


## The socket closed or an attempt failed: schedule the next attempt, or give up.
func _on_socket_lost(reason: String) -> void:
	var stable := _session_up and (signed_in
		or Time.get_ticks_msec() - _session_started_msec >= STABLE_SESSION_SEC * 1000)
	_close_socket()
	_reset_session()
	last_error = reason
	_relogin = false
	_rename_retries = 0
	if stable:
		# An established session dropped: a fresh series of attempts.
		reconnecting = true
		attempt = 1
	elif ReconnectPolicy.can_retry(attempt):
		attempt += 1
	else:
		gave_up = true
		# A typed password must not wait for a connection that may never come.
		_pending_login.clear()
		_set_state(State.DISCONNECTED, true)
		EventBus.connection_error.emit(reason)
		return
	var delay := ReconnectPolicy.delay(attempt, randf())
	_retry_at_msec = Time.get_ticks_msec() + int(delay * 1000.0)
	_set_state(State.WAITING, true)
	EventBus.reconnect_scheduled.emit(attempt, ReconnectPolicy.MAX_ATTEMPTS, delay)


func _close_socket() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	# A sign-in answer belongs to the challstr of this socket; a late one is useless.
	_login.cancel()
	# Unsent messages belong to the old session (a choice for an old request, a stale search).
	_outbox.clear()
	_throttle.reset()
	_socket_gen += 1


func _handle_frame(data: String) -> void:
	for msg in PSParser.parse_frame(data):
		_handle_session_message(msg)
		EventBus.message_received.emit(msg)


func _handle_session_message(msg: PSMessage) -> void:
	match msg.type:
		"challstr":
			challstr = msg.arg(0)
			_session_up = true
			_session_started_msec = Time.get_ticks_msec()
			gave_up = false
			_on_session_ready()
		"updateuser":
			# |updateuser|USER|NAMED|AVATAR|SETTINGS - USER starts with a rank symbol and may end with "@!" status.
			var user := msg.arg(0).get_slice("@", 0).strip_edges()
			if not user.is_empty() and PSParser.to_id(user[0]).is_empty():
				user = user.substr(1)
			var previous := username
			var was_signed_in := signed_in
			username = user
			signed_in = msg.arg(1) == "1"
			if not signed_in:
				return
			signing_in = false
			session_name = username
			if stay_signed_in:
				AppConfig.set_setting("account", "username", username)
			# |updateuser| repeats on every settings change; only a (re-)sign-in or a new name
			# counts. After a reconnect this fires again.
			if not was_signed_in or PSParser.to_id(previous) != PSParser.to_id(username):
				EventBus.logged_in.emit(username)
			if reconnecting:
				_finish_reconnect()
		"raw":
			# The server dropped a message anyway ("...typing too quickly"): pause, and say so,
			# because it may have been a move.
			if msg.arg(0).contains("message-throttle-notice"):
				_throttle.back_off(Time.get_ticks_msec())
				EventBus.popup.emit(tr("Showdown dropped a message because too many were sent at once. If a move didn't go through, choose it again."))
		"nametaken":
			signing_in = false
			if _relogin and _rename_retries < RENAME_RETRIES:
				# Most likely the server still holds the old connection with this name.
				_rename_retries += 1
				var gen := _socket_gen
				get_tree().create_timer(RENAME_RETRY_SEC).timeout.connect(func() -> void:
					if gen == _socket_gen and _session_up and not signed_in:
						_sign_in_again())
				return
			_end_relogin()
			EventBus.login_failed.emit(msg.arg(1, "Name not available"))


# --- Sign-in ------------------------------------------------------------------------------

## The server accepted the connection: sign in as requested, as before a reconnect, or with
## the saved session.
func _on_session_ready() -> void:
	if not _pending_login.is_empty():
		_start_login()
	elif reconnecting and not session_name.is_empty():
		_sign_in_again()
	elif reconnecting:
		_finish_reconnect()
	elif stay_signed_in and not _login.session_cookie.is_empty():
		signing_in = true
		_login.request_upkeep(api_base(), challstr)
	elif stay_signed_in and not str(AppConfig.get_setting("account", "username", "")).is_empty():
		login(str(AppConfig.get_setting("account", "username", "")))


func _start_login() -> void:
	var name: String = _pending_login["name"]
	var password: String = _pending_login["password"]
	_pending_login.clear()
	_relogin = false
	signing_in = true
	if api_base().is_empty():
		send("", "/trn " + name)
	else:
		_login.request_assertion(api_base(), name, password, challstr)


func _sign_in_again() -> void:
	_relogin = true
	signing_in = true
	if api_base().is_empty():
		send("", "/trn " + session_name)
	elif PSParser.to_id(LoginClient.cookie_username(_login.session_cookie)) == PSParser.to_id(session_name):
		_login.request_upkeep(api_base(), challstr)
	else:
		_login.request_assertion(api_base(), session_name, "", challstr)


func _finish_reconnect() -> void:
	reconnecting = false
	_relogin = false
	_rename_retries = 0
	EventBus.reconnected.emit()


## A sign-in after a reconnect failed: the connection itself is back all the same.
func _end_relogin() -> void:
	if _relogin or reconnecting:
		_finish_reconnect()


## Login server answers. _close_socket() cancels running requests, and these guards drop
## anything that still arrives without a live session - it belonged to an older socket.
func _on_assertion_ready(name: String, assertion: String) -> void:
	if not _session_up:
		return
	send("", "/trn %s,0,%s" % [name, assertion])


func _on_password_required(name: String) -> void:
	if not _session_up:
		return
	signing_in = false
	_end_relogin()
	EventBus.password_required.emit(name)


func _on_login_failed(reason: String) -> void:
	if not _session_up:
		return
	signing_in = false
	_end_relogin()
	EventBus.login_failed.emit(reason)


func _on_session_changed(sid: String) -> void:
	var api := api_base()
	if not api.is_empty() and (sid.is_empty() or stay_signed_in):
		SessionStore.save_cookie(api, sid)


func _on_session_expired() -> void:
	if not _session_up:
		return
	signing_in = false
	if not session_name.is_empty() and _session_up:
		# Reconnect with an expired cookie: an unregistered name still works without it.
		signing_in = true
		_login.request_assertion(api_base(), session_name, "", challstr)
	else:
		_end_relogin()


func _reset_session() -> void:
	challstr = ""
	username = ""
	signed_in = false
	signing_in = false
	_session_up = false


func _set_state(new_state: State, force := false) -> void:
	if state == new_state and not force:
		return
	state = new_state
	EventBus.connection_state_changed.emit(state)
