extends Node
## End-to-end check of the sign-in UI against the local server (tools/e2e_ui.sh, run via
## tests/e2e/run.gd):
## connect without a name -> the sign-in card opens -> sign in -> sign out -> try a name
## another connection holds -> inline error. Drives the real cards, prints [e2e] lines and
## exits 0 when every step passed.

const TIMEOUT_SEC := 40.0

var _t := 0.0
var _step := 0
var _main: Node
var _overlay: ConnectionOverlay
var _other: WebSocketPeer
var _name := "E2ESignIn%d" % randi_range(1000, 9999)
var _taken := "E2ETaken%d" % randi_range(1000, 9999)


func _process(delta: float) -> void:
	_t += delta
	if _other != null:
		_other.poll()
	match _step:
		0:
			_main = load("res://src/app/main.tscn").instantiate()
			get_tree().root.add_child(_main)
			_overlay = _main.connection_overlay
			Connection.connect_to_server("local")
			_step = 1
		1:
			if _overlay.current_card() == &"sign_in" and _card() != null:
				_check(AccountButton.describe(Connection.status(), "")["sub"] == "Sign in", "the account offers Sign in")
				_submit(_name)
				_check(_card()._submit.text == "Signing in…", "the card shows that it's busy")
				_step = 2
		2:
			if Connection.signed_in:
				_check(Connection.username == _name, "signed in as " + _name)
				_check(_overlay.current_card() == &"", "the card closed")
				_check(AccountButton.describe(Connection.status(), "")["name"] == _name, "the account shows the name")
				Connection.sign_out()
				_step = 3
		3:
			# The server answers /logout by renaming the user to "Guest N".
			if Connection.username.begins_with("Guest") and _overlay.current_card() == &"sign_in":
				_check(not Connection.signed_in, "signed out: a guest again, the card is back")
				_other = WebSocketPeer.new()
				_other.connect_to_url(str(AppConfig.get_server("local")["url"]))
				_step = 4
		4:
			while _other.get_available_packet_count() > 0:
				var packet := _other.get_packet().get_string_from_utf8()
				if packet.begins_with("|challstr|"):
					_other.send_text("|/trn " + _taken)
				elif packet.contains("|updateuser| " + _taken):
					_submit(_taken)
					_step = 5
		5:
			var card := _card()
			if card != null and card._error_slot.visible and card._error_slot.get_child_count() > 0:
				var labels: Array = card._error_slot.find_children("*", "Label", true, false)
				_check(not labels.is_empty() and (labels[0] as Label).text.contains(_taken), "name taken: inline error")
				_check(not Connection.signed_in, "still a guest")
				print("[e2e] sign-in flow: OK")
				get_tree().quit(0)
				_step = 99
	if _t > TIMEOUT_SEC and _step != 99:
		print("[e2e] TIMEOUT in step %d: card %s, status %s" % [_step, _overlay.current_card() if _overlay else &"", Connection.status()])
		get_tree().quit(1)
		_step = 99


func _card() -> SignInCard:
	for node in _overlay.find_children("*", "", true, false):
		if node is SignInCard and not node.is_queued_for_deletion():
			return node
	return null


func _submit(name: String) -> void:
	var card := _card()
	card._name.text = name
	card._update_buttons()
	card._submit_form()


func _check(ok: bool, what: String) -> void:
	print("[e2e] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		get_tree().quit(1)
		_step = 99
