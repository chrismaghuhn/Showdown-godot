extends "res://tests/test_case.gd"
## The Connection autoload's state machine, driven directly (no sockets).


func _reset() -> void:
	Connection.disconnect_from_server()
	Connection.server_id = ""
	Connection.reconnecting = false
	Connection._session_up = false


func test_attempts_count_up_and_give_up() -> void:
	var errors: Array[String] = []
	var on_error := func(reason: String) -> void: errors.append(reason)
	EventBus.connection_error.connect(on_error)
	Connection.server_id = "local"
	Connection.attempt = 1
	Connection._on_socket_lost("refused")
	assert_eq([Connection.state, Connection.attempt, Connection.reconnecting], [Connection.State.WAITING, 2, false],
		"a failed first attempt: attempt 2 is scheduled, still the first connection")
	assert_true(Connection.retry_in() > 3.0 and Connection.retry_in() <= 4.8, "4 s ±20 %")
	for i in 3:
		Connection._on_socket_lost("refused")
	assert_eq(Connection.attempt, 5, "attempt 5")
	assert_true(errors.is_empty(), "no error before the last attempt")
	Connection._on_socket_lost("refused")
	assert_eq([Connection.state, Connection.gave_up], [Connection.State.DISCONNECTED, true], "gave up")
	assert_eq(errors, ["refused"] as Array[String], "one error when giving up")
	EventBus.connection_error.disconnect(on_error)
	_reset()


func test_only_a_stable_session_restarts_the_count() -> void:
	Connection.server_id = "local"
	Connection.attempt = 3
	Connection._session_up = true
	Connection._session_started_msec = Time.get_ticks_msec()
	Connection._on_socket_lost("closed")
	assert_eq([Connection.attempt, Connection.reconnecting], [4, false], "accepted and closed right away: a failed attempt")
	Connection._session_up = true
	Connection._session_started_msec = Time.get_ticks_msec() - 60000
	Connection._on_socket_lost("closed")
	assert_eq([Connection.attempt, Connection.reconnecting], [1, true], "a session that lasted: reconnect from attempt 1")
	_reset()


func test_late_login_answers_are_ignored() -> void:
	var reconnected: Array[bool] = []
	var on_reconnected := func() -> void: reconnected.append(true)
	EventBus.reconnected.connect(on_reconnected)
	Connection.server_id = "local"
	Connection.state = Connection.State.WAITING
	Connection.reconnecting = true
	Connection._relogin = true
	Connection._session_up = false
	Connection._on_login_failed("Login server not reachable")
	Connection._on_password_required("Alice")
	Connection._on_session_expired()
	# Would warn "send() while not connected" (and fail this test) if it tried to send.
	Connection._on_assertion_ready("Alice", "abc,alice")
	assert_true(reconnected.is_empty(), "the reconnect isn't finished by an answer for an old socket")
	assert_true(Connection.reconnecting, "still reconnecting")
	EventBus.reconnected.disconnect(on_reconnected)
	_reset()


func test_sign_out_forgets_the_name() -> void:
	var before: Variant = AppConfig.get_setting("account", "username", "")
	AppConfig.set_setting("account", "username", "Ash")
	Connection.session_name = "Ash"
	Connection.sign_out()
	assert_eq(str(AppConfig.get_setting("account", "username", "")), "", "not signed in again on the next start")
	assert_eq(Connection.session_name, "", "not signed in again after a reconnect")
	AppConfig.set_setting("account", "username", before)


func test_card_waits_for_the_server_greeting() -> void:
	var status := Connection.status().merged({"state": Connection.State.CONNECTED, "session_up": false}, true)
	assert_eq(ConnectionFlow.card_for(status, {}), &"connecting", "socket open, no challstr yet")
	status["session_up"] = true
	assert_eq(ConnectionFlow.card_for(status, {}), &"sign_in", "greeted: sign in")
