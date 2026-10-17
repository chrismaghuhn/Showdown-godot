extends "res://tests/test_case.gd"


func test_defaults_match_design() -> void:
	assert_eq(NotificationEvents.default_value("challenge.desktop"), false, "challenge desktop off")
	assert_eq(NotificationEvents.default_value("mention.sound"), false, "mention sound off")
	assert_eq(NotificationEvents.default_value("your_turn.desktop"), true, "your turn desktop on")
	assert_eq(NotificationEvents.default_value("timer_warning"), 30, "timer warning 30 s")
	assert_eq(NotificationEvents.default_value("volume"), 0.7, "volume 70 %")
	assert_eq(NotificationEvents.default_value("nope.toast"), null, "unknown key")


func test_only_background_quiets_sound_and_desktop() -> void:
	var focused := NotificationEvents.channels("your_turn", {}, true)
	assert_eq(focused, {"toast": true, "sound": false, "desktop": false}, "focused: toast only")
	var background := NotificationEvents.channels("your_turn", {}, false)
	assert_eq(background, {"toast": true, "sound": true, "desktop": true}, "background: everything")
	var always := NotificationEvents.channels("your_turn", {"only_background": false}, true)
	assert_eq(always["sound"], true, "setting off: sound while focused")


func test_toast_skipped_when_subject_on_screen() -> void:
	assert_eq(NotificationEvents.channels("your_turn", {}, true, true)["toast"], false, "battle visible")
	assert_eq(NotificationEvents.channels("your_turn", {}, false, true)["toast"], true, "window in background")
	assert_eq(NotificationEvents.channels("your_turn", {"your_turn.toast": false}, false)["toast"], false, "disabled")


func test_challenge_detection() -> void:
	var me := "ironquill"
	assert_eq(NotificationEvents.challenge_format(" Mirebloom", " ironquill", "/challenge gen9ou|gen9ou|||", me), "gen9ou", "incoming")
	assert_eq(NotificationEvents.challenge_format(" Mirebloom", " ironquill", "/challenge", me), "", "cancelled")
	assert_eq(NotificationEvents.challenge_format(" ironquill", " Mirebloom", "/challenge gen9ou|||", me), "", "sent by me")


func test_private_messages_ignore_commands() -> void:
	var me := "ironquill"
	assert_true(NotificationEvents.is_private_message(" Mirebloom", "gg!", me), "plain message")
	assert_true(NotificationEvents.is_private_message(" Mirebloom", "/me waves", me), "/me counts")
	assert_true(not NotificationEvents.is_private_message(" Mirebloom", "/challenge gen9ou|||", me), "challenge")
	assert_true(not NotificationEvents.is_private_message(" Mirebloom", "/raw <b>hi</b>", me), "raw")
	assert_true(not NotificationEvents.is_private_message(" ironquill", "hello", me), "own message")


func test_mentions_match_whole_words() -> void:
	assert_true(NotificationEvents.is_mention("Mirebloom", "gg IronQuill, nice", "ironquill"), "case-insensitive")
	assert_true(not NotificationEvents.is_mention("Mirebloom", "ironquills are cool", "ironquill"), "part of a word")
	assert_true(not NotificationEvents.is_mention("ironquill", "ironquill here", "ironquill"), "own message")
	assert_true(NotificationEvents.is_mention("A", "look at c++ now", "x", PackedStringArray(["c++"])), "regex chars escaped")


func test_default_sound_pack_loads() -> void:
	for event: String in NotificationEvents.EVENTS:
		assert_true(Sounds.stream_for(event) != null, event + " has a sound")
	assert_true(Sounds.stream_for("your_turn").get_length() < 1.0, "trimmed")


func test_custom_sound_validation() -> void:
	var dir := "user://test-sounds"
	DirAccess.make_dir_recursive_absolute(dir)
	var text_file := FileAccess.open(dir.path_join("not-audio.wav"), FileAccess.WRITE)
	text_file.store_string("definitely not a wav")
	text_file.close()
	assert_true(not Sounds.import_custom("mention", dir.path_join("not-audio.wav")).is_empty(), "invalid wav rejected")
	assert_true(not Sounds.import_custom("mention", dir.path_join("x.exe")).is_empty(), "wrong extension rejected")
	assert_eq(Sounds.get_choice("mention"), "pack", "choice unchanged after errors")



func test_audio_signatures() -> void:
	assert_true(Sounds.looks_like(FileAccess.get_file_as_bytes("res://assets/sounds/default/message.wav"), "wav"), "real wav")
	assert_true(not Sounds.looks_like("definitely not audio".to_utf8_buffer(), "wav"), "text as wav")
	assert_true(Sounds.looks_like("OggS........".to_utf8_buffer(), "ogg"), "ogg magic")
	assert_true(not Sounds.looks_like("RIFF....WAVE".to_utf8_buffer(), "ogg"), "wav is not ogg")
