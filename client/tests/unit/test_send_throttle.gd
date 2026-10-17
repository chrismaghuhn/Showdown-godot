extends "res://tests/test_case.gd"
## Outgoing messages at the server's pace (#24): SendThrottle and Connection's outbox.


func test_burst_then_one_per_interval() -> void:
	var throttle := SendThrottle.new()
	var sent := 0
	for i in 10:
		if throttle.take(1000):
			sent += 1
	assert_eq(sent, SendThrottle.CAPACITY, "a short burst goes out at once")
	assert_eq(throttle.wait_ms(1000), SendThrottle.INTERVAL_MS, "then one per interval")
	assert_true(not throttle.take(1000 + SendThrottle.INTERVAL_MS - 1), "not before")
	assert_true(throttle.take(1000 + SendThrottle.INTERVAL_MS), "on time")
	assert_true(throttle.take(1000 + 10 * SendThrottle.INTERVAL_MS), "refills over time")
	var full := 0
	for i in 10:
		if throttle.take(1000 + 100 * SendThrottle.INTERVAL_MS):
			full += 1
	assert_eq(full, SendThrottle.CAPACITY, "never more than the capacity")


func test_back_off_after_a_dropped_message() -> void:
	var throttle := SendThrottle.new()
	throttle.take(5000)
	throttle.back_off(5000)
	var pause_end := 5000 + SendThrottle.BACK_OFF_MS
	assert_true(not throttle.take(pause_end - 1), "paused")
	assert_true(not throttle.take(pause_end), "no burst right after the pause: nothing refilled")
	assert_true(throttle.take(pause_end + SendThrottle.INTERVAL_MS), "then one per interval again")
	assert_true(not throttle.take(pause_end + SendThrottle.INTERVAL_MS), "just one")
	assert_true(not throttle.take(1000), "a clock going back gives nothing")
	throttle.reset()
	assert_eq(throttle.wait_ms(0), 0, "a new connection starts fresh")


func test_connection_queues_and_cleans_lines() -> void:
	var was_state: int = Connection.state
	var sent: Array[String] = []
	Connection._outbox.clear()
	Connection._throttle.reset()
	Connection._transport = func(line: String) -> void: sent.append(line)
	Connection.state = Connection.State.CONNECTED
	for i in 6:
		Connection.send("", "/msg %d" % i)
	assert_eq(sent.size(), SendThrottle.CAPACITY, "the burst went out")
	assert_eq(Connection._outbox.size(), 6 - SendThrottle.CAPACITY, "the rest waits, in order")
	assert_eq(sent[0], "|/msg 0", "first one first")
	var later := Time.get_ticks_msec() + SendThrottle.INTERVAL_MS * 2
	Connection._flush_outbox(later)
	assert_eq(sent.slice(SendThrottle.CAPACITY), ["|/msg 4", "|/msg 5"] as Array[String], "the rest drains in order")
	Connection._outbox.clear()
	Connection._throttle.reset()
	sent.clear()
	Connection.send("battle-x", "hello\n/forfeit")
	assert_eq(sent, ["battle-x|hello /forfeit"] as Array[String], "a line break can't start another command")
	sent.clear()
	Connection.send("bat|tle\r", "a\r\nb\rc")
	assert_eq(sent, ["battle|a b c"] as Array[String], "no | or line breaks in the room id, none in the text")
	Connection._outbox.append("|/old")
	Connection._close_socket()
	assert_eq(Connection._outbox.size(), 0, "a lost connection drops what's unsent")
	sent.clear()
	for i in 6:
		Connection.send("battle-x", "/choose move %d" % (i % 4 + 1))
	Connection.disconnect_from_server()
	assert_eq(sent.size(), 6, "closing on purpose sends what was waiting first")
	assert_eq(Connection._outbox.size(), 0, "nothing left")
	Connection._transport = Callable()
	Connection.state = was_state


func test_server_throttle_notice_pauses_sending() -> void:
	var was_state: int = Connection.state
	var popups: Array[String] = []
	var on_popup := func(text: String) -> void: popups.append(text)
	EventBus.popup.connect(on_popup)
	Connection._throttle.reset()
	Connection.state = Connection.State.CONNECTED
	for msg in PSParser.parse_frame(">battle-gen9randombattle-3\n|raw|<div class=\"broadcast-blue\"><b>message-throttle-notice</b></div>"):
		Connection._handle_session_message(msg)
	assert_true(not Connection._throttle.is_paused(Time.get_ticks_msec()), "someone's /declare text doesn't count")
	var notice := ">battle-gen9randombattle-3\n|raw|<strong class=\"message-throttle-notice\">Your message was not sent because you've been typing too quickly.</strong>"
	for i in 3:
		for msg in PSParser.parse_frame(notice):
			Connection._handle_session_message(msg)
	assert_true(Connection._throttle.wait_ms(Time.get_ticks_msec()) > 1000, "paused")
	assert_eq(popups.size(), 1, "the user hears about it once, not once per dropped message")
	EventBus.popup.disconnect(on_popup)
	Connection._throttle.reset()
	Connection.state = was_state
