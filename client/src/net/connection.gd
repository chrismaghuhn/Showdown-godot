extends Node
## Autoload "Connection": the websocket to the Showdown server, plus login.
##
## Incoming frames are parsed and published as EventBus.message_received.
## Everything that interprets messages beyond connection/login lives elsewhere (e.g. Rooms).

enum State { DISCONNECTED, CONNECTING, CONNECTED }

var state: State = State.DISCONNECTED
var server_id := ""
var challstr := ""
var username := ""

var _ws: WebSocketPeer
var _login := LoginClient.new()
var _pending_login := {}


func _ready() -> void:
	add_child(_login)
	_login.assertion_ready.connect(_on_assertion_ready)
	_login.failed.connect(func(reason: String) -> void: EventBus.login_failed.emit(reason))


func connect_to_server(id: String) -> void:
	var server := AppConfig.get_server(id)
	if server.is_empty():
		EventBus.connection_error.emit("Unknown server '%s'" % id)
		return
	disconnect_from_server()
	server_id = id
	_ws = WebSocketPeer.new()
	# Some messages (|formats|, |request|, replays) are larger than the default buffer.
	_ws.inbound_buffer_size = 4 * 1024 * 1024
	_ws.max_queued_packets = 4096
	var err := _ws.connect_to_url(server["url"])
	if err != OK:
		_ws = null
		EventBus.connection_error.emit("Could not connect to %s (error %d)" % [server["url"], err])
		return
	_set_state(State.CONNECTING)


func disconnect_from_server() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	_reset_session()
	_set_state(State.DISCONNECTED)


## Sends `text` to a room. Use room_id "" for global commands like /search or /trn.
func send(room_id: String, text: String) -> void:
	if state != State.CONNECTED:
		push_warning("Connection.send() while not connected: " + text)
		return
	_ws.send_text(room_id + "|" + text)


## Sends a battle decision, e.g. choose("battle-gen9randombattle-1", "move 2", 3).
func choose(room_id: String, choice: String, rqid := -1) -> void:
	send(room_id, "/choose %s|%d" % [choice, rqid] if rqid >= 0 else "/choose " + choice)


## Logs in as soon as the server's challstr is known. Empty password = unregistered name.
func login(name: String, password := "") -> void:
	_pending_login = {"name": name, "password": password}
	if not challstr.is_empty():
		_start_login()


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state != State.CONNECTED:
				_set_state(State.CONNECTED)
			while _ws.get_available_packet_count() > 0:
				_handle_frame(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var reason := _ws.get_close_reason()
			_ws = null
			_reset_session()
			_set_state(State.DISCONNECTED)
			if not reason.is_empty():
				EventBus.connection_error.emit(reason)


func _handle_frame(data: String) -> void:
	for msg in PSParser.parse_frame(data):
		_handle_session_message(msg)
		EventBus.message_received.emit(msg)


func _handle_session_message(msg: PSMessage) -> void:
	match msg.type:
		"challstr":
			challstr = msg.arg(0)
			if not _pending_login.is_empty():
				_start_login()
		"updateuser":
			# |updateuser|USER|NAMED|AVATAR|SETTINGS - USER starts with a rank symbol and may end with "@!" status.
			var user := msg.arg(0).get_slice("@", 0).strip_edges()
			if not user.is_empty() and PSParser.to_id(user[0]).is_empty():
				user = user.substr(1)
			username = user
			if msg.arg(1) == "1":
				EventBus.logged_in.emit(username)
		"nametaken":
			EventBus.login_failed.emit(msg.arg(1, "Name not available"))


func _start_login() -> void:
	var name: String = _pending_login["name"]
	var password: String = _pending_login["password"]
	_pending_login.clear()
	var login_mode: String = AppConfig.get_server(server_id).get("login", "none")
	if login_mode == "none":
		send("", "/trn " + name)
	else:
		_login.request_assertion(login_mode, name, password, challstr)


func _on_assertion_ready(name: String, assertion: String) -> void:
	send("", "/trn %s,0,%s" % [name, assertion])


func _reset_session() -> void:
	challstr = ""
	username = ""


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	EventBus.connection_state_changed.emit(state)
