extends "res://tests/test_case.gd"


func test_backoff_doubles_and_caps() -> void:
	var delays: Array[float] = []
	for attempt in range(1, 7):
		delays.append(ReconnectPolicy.delay(attempt))
	assert_eq(delays, [2.0, 4.0, 8.0, 16.0, 30.0, 30.0] as Array[float], "2, 4, 8, 16, then capped at 30")
	assert_eq(ReconnectPolicy.delay(0), 2.0, "attempt below 1 counts as the first")


func test_jitter_stays_within_twenty_percent() -> void:
	assert_eq(ReconnectPolicy.delay(2, 0.0), 3.2, "lowest roll: -20 %")
	assert_eq(ReconnectPolicy.delay(2, 1.0), 4.8, "highest roll: +20 %")
	assert_eq(ReconnectPolicy.delay(2, 0.5), 4.0, "middle roll: no jitter")
	assert_eq(ReconnectPolicy.delay(2, 7.0), 4.8, "rolls are clamped")


func test_gives_up_after_five_attempts() -> void:
	assert_true(ReconnectPolicy.can_retry(4), "4 failed attempts: one more")
	assert_true(not ReconnectPolicy.can_retry(5), "5 failed attempts: give up")


func test_rooms_restore_battles_after_reconnect() -> void:
	var restored: Array[int] = []
	var on_restored := func(count: int) -> void: restored.append(count)
	EventBus.battles_restored.connect(on_restored)
	_feed(">battle-gen9randombattle-7\n|init|battle\n|player|p1|Alice|1|\n|turn|1")
	assert_true(not Rooms.get_battle("battle-gen9randombattle-7").restored, "a new battle is not restored")

	EventBus.reconnected.emit()
	_feed('|updatesearch|{"searching":[],"games":{"battle-gen9randombattle-7":"[Gen 9] Random Battle","battle-gen9ou-8":"[Gen 9] OU"}}')
	_feed(">battle-gen9randombattle-7\n|init|battle\n|player|p1|Alice|1|\n|turn|1\n|turn|2")
	assert_true(Rooms.get_battle("battle-gen9randombattle-7").restored, "the replayed battle is marked restored")
	assert_eq(Rooms.get_battle("battle-gen9randombattle-7").turn, 2, "and rebuilt from its log")
	assert_eq(restored, [] as Array[int], "still waiting for the game listed in updatesearch")
	_feed(">battle-gen9ou-8\n|init|battle\n|turn|5")
	assert_eq(restored, [2] as Array[int], "both battles came back")

	EventBus.battles_restored.disconnect(on_restored)
	Rooms.battles.erase("battle-gen9randombattle-7")
	Rooms.battles.erase("battle-gen9ou-8")


func test_rooms_skip_battles_that_no_longer_exist() -> void:
	var restored: Array[int] = []
	var on_restored := func(count: int) -> void: restored.append(count)
	EventBus.battles_restored.connect(on_restored)
	_feed(">battle-gen9randombattle-9\n|init|battle\n|turn|3")
	EventBus.reconnected.emit()
	_feed(">battle-gen9randombattle-9\n|noinit|nonexistent|The room \"battle-gen9randombattle-9\" does not exist.")
	assert_eq(restored, [0] as Array[int], "nothing to restore")
	EventBus.battles_restored.disconnect(on_restored)
	Rooms.battles.erase("battle-gen9randombattle-9")


func _feed(frame: String) -> void:
	for msg in PSParser.parse_frame(frame):
		EventBus.message_received.emit(msg)
