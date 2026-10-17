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


func test_restore_stops_when_the_connection_drops_again() -> void:
	var restored: Array[int] = []
	var on_restored := func(count: int) -> void: restored.append(count)
	EventBus.battles_restored.connect(on_restored)
	_feed(">battle-gen9randombattle-11\n|init|battle\n|turn|4")
	EventBus.reconnected.emit()
	EventBus.connection_state_changed.emit(Connection.State.WAITING)
	_feed(">battle-gen9randombattle-11\n|init|battle\n|turn|4")
	assert_eq(restored, [] as Array[int], "no 'Reconnected' while offline again")
	assert_true(not Rooms.get_battle("battle-gen9randombattle-11").restored, "not part of a cancelled restore")
	EventBus.battles_restored.disconnect(on_restored)
	Rooms.battles.erase("battle-gen9randombattle-11")


func test_replayed_ended_battle_is_not_news() -> void:
	var restored: Array[int] = []
	var ended: Array[String] = []
	var on_restored := func(count: int) -> void: restored.append(count)
	var on_ended := func(battle: BattleState, _winner: String) -> void: ended.append(battle.room_id)
	EventBus.battles_restored.connect(on_restored)
	EventBus.battle_ended.connect(on_ended)
	var log := ">battle-gen9randombattle-12\n|init|battle\n|player|p1|Alice|1|\n|turn|9\n|win|Alice"
	_feed(log)
	assert_eq(ended, ["battle-gen9randombattle-12"] as Array[String], "ended once")
	EventBus.reconnected.emit()
	_feed(log)
	assert_eq(ended, ["battle-gen9randombattle-12"] as Array[String], "the replayed |win| is not reported again")
	assert_true(Rooms.get_battle("battle-gen9randombattle-12").restored, "stays in the background")
	assert_eq(restored, [0] as Array[int], "an ended battle is not counted as restored")
	EventBus.battles_restored.disconnect(on_restored)
	EventBus.battle_ended.disconnect(on_ended)
	Rooms.battles.erase("battle-gen9randombattle-12")


func test_gone_battle_rooms_are_removed() -> void:
	_feed(">battle-gen9randombattle-13\n|init|battle\n|turn|2")
	EventBus.reconnected.emit()
	_feed(">battle-gen9randombattle-13\n|noinit|nonexistent|The room \"battle-gen9randombattle-13\" does not exist.")
	assert_eq(Rooms.get_battle("battle-gen9randombattle-13"), null, "removed")


func test_plugin_error_paths() -> void:
	assert_true(Plugins.is_inside("user://plugins/calc/main.gd", "user://plugins/calc"), "script in the plugin")
	assert_true(Plugins.is_inside("user://plugins/calc/lib/x.gd", "user://plugins/calc/"), "nested, trailing slash")
	assert_true(not Plugins.is_inside("user://plugins/calc-extra/main.gd", "user://plugins/calc"), "similar name")
	assert_true(not Plugins.is_inside("res://src/net/connection.gd", "user://plugins/calc"), "app script")
	assert_true(Plugins.is_inside(ProjectSettings.globalize_path("user://plugins/calc/main.gd"), "user://plugins/calc"),
		"absolute path from a backtrace")
	assert_eq(Plugins.plugin_for_paths(PackedStringArray(["res://src/app/main.gd", ""])), "", "no plugin")
