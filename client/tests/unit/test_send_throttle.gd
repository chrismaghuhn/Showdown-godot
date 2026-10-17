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
	throttle.back_off(5000)
	assert_true(not throttle.take(5000 + SendThrottle.BACK_OFF_MS - 1), "paused")
	assert_true(throttle.take(5000 + SendThrottle.BACK_OFF_MS), "sends again after the pause")
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
	Connection._outbox.clear()
	Connection._throttle.reset()
	sent.clear()
	Connection.send("battle-x", "hello\n/forfeit")
	assert_eq(sent, ["battle-x|hello /forfeit"] as Array[String], "a line break can't start another command")
	Connection._outbox.append("|/old")
	Connection._close_socket()
	assert_eq(Connection._outbox.size(), 0, "a lost connection drops what's unsent")
	Connection._transport = Callable()
	Connection.state = was_state


func test_server_throttle_notice_pauses_sending() -> void:
	var was_state: int = Connection.state
	var popups: Array[String] = []
	var on_popup := func(text: String) -> void: popups.append(text)
	EventBus.popup.connect(on_popup)
	Connection._throttle.reset()
	Connection.state = Connection.State.CONNECTED
	for msg in PSParser.parse_frame("|raw|<strong class=\"message-throttle-notice\">Your message was not sent because you've been typing too quickly.</strong>"):
		Connection._handle_session_message(msg)
	assert_true(Connection._throttle.wait_ms(Time.get_ticks_msec()) > 1000, "paused")
	assert_eq(popups.size(), 1, "and the user hears about it")
	EventBus.popup.disconnect(on_popup)
	Connection._throttle.reset()
	Connection.state = was_state
