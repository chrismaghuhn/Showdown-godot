extends Node
## End-to-end check of the lobby against the local server (tools/e2e_ui.sh): the format list
## comes from the server and is searchable; a challenge round trip between the app (A) and a
## bare websocket (B): A's challenge declined by B, A cancels one, A declines B's, A accepts B's
## (the battle opens in its tab); then a ladder battle, after which A's rating shows.

const TIMEOUT_SEC := 90.0
## Not gen9: keeps this away from the bots of tools/e2e_battle.sh on the same server.
const FORMAT := "gen8randombattle"

var _t := 0.0
var _step := 0
var _main: Node
var _lobby: HomeScreen
var _other := WebSocketPeer.new()
var _other_named := false
var _other_room := ""
## Challenge text B received last ("" = none yet), and whether B saw an empty /challenge.
var _b_got_challenge := ""
var _b_got_end := false
var _name := "E2ELobby%d" % randi_range(1000, 9999)
var _opponent := "E2ELobbyOpp%d" % randi_range(1000, 9999)
var _wait_until := 0.0


func _process(delta: float) -> void:
	_t += delta
	_poll_opponent()
	if _t < _wait_until:
		return
	match _step:
		0:
			_main = load("res://src/app/main.tscn").instantiate()
			get_tree().root.add_child(_main)
			_main.show_screen(&"home")
			_lobby = _main._screens[&"home"]
			Connection.connect_to_server("local")
			Connection.login(_name)
			_other.connect_to_url(str(AppConfig.get_server("local")["url"]))
			_step = 1
		1:
			if Connection.signed_in and _other_named and not Rooms.formats.is_empty():
				var found := FormatPicker.entries(Rooms.formats, FormatPicker.Purpose.SEARCH, "random battle")
				# The search looks at names and sections ("Battle Factory" in "Randomized Metas").
				_check(not found.is_empty() and found.all(func(e: Dictionary) -> bool:
					return ("%s %s" % [e["name"], e["section"]]).to_lower().contains("random")),
					"the server's formats are searchable (%d matches for \"random battle\")" % found.size())
				# A challenges B through the dialog.
				var dialog: ChallengeDialog = _lobby._challenge_dialog
				dialog.open_at(_lobby._challenge_button)
				dialog._name.text = _opponent
				dialog._format.select(FORMAT)
				dialog._update()
				dialog._submit()
				_step = 2
		2:
			if _b_got_challenge.begins_with("/challenge " + FORMAT) and _lobby._sent.get_child_count() > 0:
				_check(true, "B got A's challenge; the lobby shows it as sent")
				_other.send_text("|/reject " + _name)
				_step = 3
		3:
			if Rooms.challenges.is_empty():
				_check(true, "B declined: the challenge is gone")
				_b_got_challenge = ""
				Rooms.challenge(_opponent, FORMAT)
				_step = 4
		4:
			if Rooms.challenges.has(PSParser.to_id(_opponent)) and _lobby._sent.get_child_count() > 0 and not _b_got_challenge.is_empty():
				_b_got_end = false
				_press_button(_lobby._sent, "Cancel challenge")
				_step = 5
		5:
			if _b_got_end and Rooms.challenges.is_empty():
				_check(true, "A cancelled its challenge")
				_other.send_text("|/utm null")
				_other.send_text("|/challenge %s, %s" % [_name, FORMAT])
				_step = 6
		6:
			if _lobby._challenges_count.text == "1":
				_b_got_end = false
				_press_button(_lobby._challenges, "Decline")
				_step = 7
		7:
			if _b_got_end and Rooms.challenges.is_empty():
				_check(true, "A declined B's challenge")
				_other.send_text("|/challenge %s, %s" % [_name, FORMAT])
				_step = 8
		8:
			if _lobby._challenges_count.text == "1":
				_press_button(_lobby._challenges, "Accept")
				_step = 9
		9:
			if str(_main.current).begins_with("battle:") and not _other_room.is_empty():
				_check(true, "A accepted: the battle opened in its tab")
				_other.send_text(_other_room + "|/forfeit")
				_step = 10
		10:
			var battle := Rooms.get_battle(_other_room)
			if battle != null and battle.ended:
				_other_room = ""
				_main.show_screen(&"home")
				Rooms.search(FORMAT)
				_other.send_text("|/search " + FORMAT)
				_step = 11
		11:
			if str(_main.current).begins_with("battle:") and not _other_room.is_empty():
				_other.send_text(_other_room + "|/forfeit")
				_step = 12
		12:
			if Rooms.ratings.has(FORMAT):
				_main.show_screen(&"home")
				_check(int(Rooms.ratings[FORMAT]["elo"]) > 0, "A's ladder rating arrived (%d)" % int(Rooms.ratings[FORMAT]["elo"]))
				_check(HomeScreen.rating_rows(Rooms.ratings, Rooms.formats).size() > 0 \
					and _lobby._account.get_child_count() >= 2, "the lobby shows the rating")
				print("[e2e] lobby flow: OK")
				get_tree().quit(0)
				_step = 99
	if _t > TIMEOUT_SEC and _step != 99:
		print("[e2e] TIMEOUT in step %d: challenges %s, current %s, B got '%s'" % [_step, Rooms.challenges,
			_main.current if _main != null else &"", _b_got_challenge])
		get_tree().quit(1)
		_step = 99


func _poll_opponent() -> void:
	_other.poll()
	while _other.get_available_packet_count() > 0:
		var packet := _other.get_packet().get_string_from_utf8()
		if packet.begins_with("|challstr|"):
			_other.send_text("|/trn " + _opponent)
		if packet.contains("|updateuser| " + _opponent):
			_other_named = true
		if packet.begins_with(">battle-") and packet.contains("|init|battle"):
			_other_room = packet.get_slice("\n", 0).trim_prefix(">")
		for line in packet.split("\n"):
			if line.begins_with("|pm|") and line.get_slice("|", 4).begins_with("/challenge"):
				var text := line.substr(line.find("/challenge"))
				if text.strip_edges() == "/challenge":
					_b_got_end = true
				else:
					_b_got_challenge = text


func _press_button(root: Node, label: String) -> void:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == label and not (node as Button).disabled:
			(node as Button).emit_signal("pressed")
			return
	_check(false, "button '%s' not found" % label)


func _check(ok: bool, what: String) -> void:
	print("[e2e] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		get_tree().quit(1)
		_step = 99
