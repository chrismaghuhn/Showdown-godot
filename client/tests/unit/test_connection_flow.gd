extends "res://tests/test_case.gd"
## Which connection card / banner / header status the app shows (design frames 01-03).

const NONE := {"servers_open": false, "sign_in_open": false, "dismissed": false}


func _status(overrides: Dictionary) -> Dictionary:
	var base := {"state": Connection.State.CONNECTED, "attempt": 1, "max_attempts": 5, "retry_in": 0.0,
		"reconnecting": false, "gave_up": false, "signed_in": false, "signing_in": false,
		"username": "Guest 12", "session_name": "", "server_host": "sim3.psim.us", "last_error": ""}
	return base.merged(overrides, true)


func test_first_connection_uses_the_card() -> void:
	assert_eq(ConnectionFlow.card_for(_status({"state": Connection.State.CONNECTING}), NONE), &"connecting", "connecting")
	assert_eq(ConnectionFlow.card_for(_status({"state": Connection.State.WAITING, "attempt": 2}), NONE), &"connecting",
		"failed first attempt: still the card, with a countdown")
	assert_eq(ConnectionFlow.card_for(_status({"state": Connection.State.DISCONNECTED, "gave_up": true}), NONE),
		&"gave_up", "gave up")
	assert_eq(ConnectionFlow.card_for(_status({"state": Connection.State.DISCONNECTED}), NONE), &"", "offline on purpose")
	assert_eq(ConnectionFlow.card_for(_status({"state": Connection.State.CONNECTING}), NONE.merged({"servers_open": true}, true)),
		&"servers", "server list")


func test_sign_in_card() -> void:
	assert_eq(ConnectionFlow.card_for(_status({}), NONE), &"sign_in", "connected as a guest")
	assert_eq(ConnectionFlow.card_for(_status({"signing_in": true}), NONE), &"", "automatic sign-in running")
	assert_eq(ConnectionFlow.card_for(_status({"signing_in": true}), NONE.merged({"sign_in_open": true}, true)),
		&"sign_in", "the open card stays while its sign-in runs")
	assert_eq(ConnectionFlow.card_for(_status({}), NONE.merged({"dismissed": true}, true)), &"", "Not now")
	assert_eq(ConnectionFlow.card_for(_status({"signed_in": true, "username": "Alice"}), NONE), &"", "signed in")


func test_reconnect_uses_the_banner() -> void:
	var waiting := _status({"state": Connection.State.WAITING, "attempt": 2, "retry_in": 3.2, "reconnecting": true})
	assert_eq(ConnectionFlow.card_for(waiting, NONE), &"", "no card while reconnecting")
	var banner := ConnectionFlow.banner_for(waiting)
	assert_eq(banner["tone"], "warning", "tone")
	assert_eq(banner["title"], "Connection lost — reconnecting in 4 s", "countdown rounds up")
	assert_true(str(banner["sub"]).begins_with("Attempt 2 of 5."), "attempt line")
	assert_eq(banner["action"], "Retry now", "action")
	var failed := ConnectionFlow.banner_for(_status({"state": Connection.State.DISCONNECTED, "reconnecting": true, "gave_up": true}))
	assert_eq([failed["tone"], failed["action"]], ["danger", "Try again"], "gave up while reconnecting")
	assert_eq(ConnectionFlow.banner_for(_status({})), {}, "no banner normally")
	assert_eq(ConnectionFlow.card_for(_status({"reconnecting": true}), NONE), &"", "signing in again: no card")


func test_header_status() -> void:
	assert_eq(ConnectionFlow.status_label(_status({"state": Connection.State.DISCONNECTED}))["text"], "Offline", "offline")
	assert_eq(ConnectionFlow.status_label(_status({"state": Connection.State.WAITING, "reconnecting": true}))["text"],
		"Offline", "reconnecting shows Offline (design frame 03)")
	assert_eq(ConnectionFlow.status_label(_status({"state": Connection.State.CONNECTING}))["text"], "Connecting…", "connecting")
	assert_eq(ConnectionFlow.status_label(_status({}))["text"], "Sign in", "guest")
	assert_eq(ConnectionFlow.status_label(_status({"signed_in": true, "username": "Alice"})),
		{"text": "Alice", "color_token": "color.success.text"}, "signed in")


func test_texts() -> void:
	assert_eq(ConnectionFlow.attempt_line(_status({"state": Connection.State.CONNECTING})), "sim3.psim.us · attempt 1", "attempt")
	assert_eq(ConnectionFlow.attempt_line(_status({"state": Connection.State.WAITING, "attempt": 2, "retry_in": 4.0})),
		"sim3.psim.us · attempt 2 of 5 in 4 s", "waiting")
	assert_eq(ConnectionFlow.restored_text(0), "You’re back online.", "no battles")
	assert_eq(ConnectionFlow.restored_text(1), "1 battle restored.", "one")
	assert_eq(ConnectionFlow.restored_text(2), "2 battles restored.", "two")
	assert_eq(DataProgressPanel.format_bytes(18400000), "18.4 MB", "MB")
	assert_eq(DataProgressPanel.format_bytes(5300), "5 KB", "KB")
	assert_eq(DataProgressPanel.files_line([{"label": "Pokédex", "state": "done"}, {"label": "Moves", "state": "loading"}]),
		"Pokédex ✓ · Moves", "files")
