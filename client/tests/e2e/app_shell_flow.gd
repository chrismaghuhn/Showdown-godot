extends Node
## End-to-end check of the app shell against the local server (tools/e2e_ui.sh):
## start screen -> Quick battle -> the battle opens in its own tab with a "your move" dot ->
## a move clears the dot -> the app "restarts" -> the start screen offers the running battle
## -> Enter rejoins it -> Ctrl+W asks before forfeiting -> Ctrl+1 goes Home.
## The opponent is a bare websocket that searches the same format and then idles.

const TIMEOUT_SEC := 60.0
## Not gen9: keeps this away from the bots of tools/e2e_battle.sh on the same server.
const FORMAT := "gen8randombattle"

var _t := 0.0
var _step := 0
var _main: Node
var _other := WebSocketPeer.new()
var _other_named := false
var _room := ""
var _name := "E2EShell%d" % randi_range(1000, 9999)
var _opponent := "E2EShellOpp%d" % randi_range(1000, 9999)
var _wait_until := 0.0
## Settings this flow changes on the way; put back at the end.
var _saved_play := {}


func _process(delta: float) -> void:
	_t += delta
	_poll_opponent()
	if _t < _wait_until:
		return
	match _step:
		0:
			for key in ["last_format", "last_format_name"]:
				_saved_play[key] = AppConfig.get_setting("play", key, null)
			_start_app()
			_check(_main.current == &"start", "launch shows the start screen")
			Connection.connect_to_server("local")
			Connection.login(_name)
			_other.connect_to_url(str(AppConfig.get_server("local")["url"]))
			_step = 1
		1:
			if Connection.signed_in and _other_named and not Rooms.formats.is_empty():
				var quick: QuickBattleCard = _find(_main, QuickBattleCard)
				quick._select(FORMAT)
				_check(quick.selected_format() == FORMAT, "quick battle offers " + FORMAT)
				_other.send_text("|/search " + FORMAT)
				_wait_until = _t + 0.5
				_step = 2
		2:
			var quick: QuickBattleCard = _find(_main, QuickBattleCard)
			quick.battle()
			_step = 3
		3:
			if str(_main.current).begins_with("battle:"):
				_room = str(_main.current).trim_prefix("battle:")
				_check(_main.tabs.has_tab(_main.current), "the battle opened in its own tab")
				_step = 4
		4:
			var battle := Rooms.get_battle(_room)
			if battle != null and battle.awaiting_choice:
				var spec: Dictionary = _main.battle_tab_spec(battle)
				_check(spec["dot"] == "active", "tab dot: your move")
				_check(spec["title"] == _opponent, "tab names the opponent")
				var request_has_moves: bool = battle.request.has("active")
				Connection.choose(_room, "move 1" if request_has_moves else "default", int(battle.request.get("rqid", -1)))
				_check(_main.battle_tab_spec(battle)["dot"] == "waiting", "after the choice: waiting")
				_step = 5
		5:
			# "Restart": drop the app and the client's room state, connect again with the same name.
			_main.queue_free()
			_main = null
			Connection.disconnect_from_server()
			Rooms.battles.clear()
			Rooms.games.clear()
			_wait_until = _t + 1.0
			_step = 6
		6:
			_start_app()
			Connection.connect_to_server("local")
			Connection.login(_name)
			_step = 7
		7:
			var battle := Rooms.get_battle(_room)
			var card: RunningBattleCard = _find(_main, RunningBattleCard)
			if battle != null and card != null and card.visible and card.room_id == _room:
				_check(battle.restored, "the server sent the running battle back after the restart")
				_check(_main.current == &"start", "it waits on the start screen")
				_press(KEY_ENTER)
				_step = 8
		8:
			if _main.current == StringName("battle:" + _room):
				_check(true, "Enter rejoined the battle")
				_press(KEY_W, true)
				_step = 9
		9:
			var dialog: ConfirmationDialog = _main._close_dialog
			_check(dialog.visible, "Ctrl+W on a running battle asks before forfeiting")
			dialog.hide()
			_press(KEY_1, true)
			_step = 10
		10:
			_check(_main.current == &"home", "Ctrl+1 goes to Home")
			Connection.send(_room, "/forfeit")
			for key: String in _saved_play:
				if _saved_play[key] != null:
					AppConfig.set_setting("play", key, _saved_play[key])
			print("[e2e] app shell flow: OK")
			get_tree().quit(0)
			_step = 99
	if _t > TIMEOUT_SEC and _step != 99:
		print("[e2e] TIMEOUT in step %d: current %s, room %s, status %s" % [_step,
			_main.current if _main != null else &"", _room, Connection.status()])
		get_tree().quit(1)
		_step = 99


func _start_app() -> void:
	_main = load("res://src/app/main.tscn").instantiate()
	get_tree().root.add_child(_main)


func _poll_opponent() -> void:
	_other.poll()
	while _other.get_available_packet_count() > 0:
		var packet := _other.get_packet().get_string_from_utf8()
		if packet.begins_with("|challstr|"):
			_other.send_text("|/trn " + _opponent)
		elif packet.contains("|updateuser| " + _opponent):
			_other_named = true


func _press(keycode: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		Input.parse_input_event(event)


func _find(root: Node, type: Variant) -> Node:
	if root == null:
		return null
	for node in root.find_children("*", "", true, false):
		if is_instance_of(node, type) and not node.is_queued_for_deletion():
			return node
	return null


func _check(ok: bool, what: String) -> void:
	print("[e2e] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		get_tree().quit(1)
		_step = 99
