extends "res://tests/test_case.gd"
## App shell and start screen (#22): formats, tabs, account, welcome, news, notification
## history, and the room state behind them.

const Main := preload("res://src/app/main.gd")
const FORMATS := "|formats|,LL|,1|S/V Singles|[Gen 9] Random Battle,f|[Gen 9] Unrated Random Battle,b|[Gen 9] OU,e|,2|S/V Doubles|[Gen 9] Random Doubles Battle,f|[Gen 9] Custom Game,c"


func test_format_list() -> void:
	var formats := FormatList.parse(FORMATS.trim_prefix("|formats|"))
	assert_eq(formats.size(), 5, "five formats")
	assert_eq(formats[0], {"id": "gen9randombattle", "name": "[Gen 9] Random Battle", "section": "S/V Singles",
		"preset_team": true, "search": true, "challenge": true, "tournament": true}, "random battle flags")
	assert_eq(formats[2]["preset_team"], false, "OU needs a team")
	assert_eq(formats[3]["section"], "S/V Doubles", "sections")
	assert_eq(formats[4]["search"], false, "custom game is challenge-only")
	var quick: Array = FormatList.quick_battle_formats(formats).map(func(f: Dictionary) -> String: return f["id"])
	assert_eq(quick, ["gen9randombattle", "gen9unratedrandombattle", "gen9randomdoublesbattle"], "no team, searchable")
	assert_eq(FormatList.display_name(formats, "gen9ou"), "[Gen 9] OU", "display name")
	assert_eq(FormatList.parse("|,1|Old|[Gen 9] OU")[0]["search"], true, "no flags: searchable")


func test_first_screen_and_short_formats() -> void:
	assert_eq(Main.first_screen("", true), &"start", "start screen at launch")
	assert_eq(Main.first_screen("", false), &"home", "turned off: Home")
	assert_eq(Main.first_screen("dev-console", true), &"dev-console", "--screen wins")
	assert_eq(Main.short_format("[Gen 9] OU"), "OU", "OU")
	assert_eq(Main.short_format("[Gen 9] Random Battle"), "Random", "random")
	assert_eq(Main.short_format("gen8randombattle"), "Random", "from a room id")
	assert_eq(Main.short_format("[Gen 9] Doubles OU"), "Doubles OU", "doubles")


func test_battle_tab_spec() -> void:
	var battle := BattleState.new("battle-gen9ou-5")
	for line in ["|player|p1|Ash|1|", "|player|p2|Mirebloom|2|", "|tier|[Gen 9] OU", "|turn|7"]:
		battle.apply(PSParser.parse_frame(line)[0])
	battle.apply_request({"side": {"id": "p1", "name": "Ash", "pokemon": []}, "active": [{}], "rqid": 3})
	var spec: Dictionary = Main.battle_tab_spec(battle)
	assert_eq([spec["title"], spec["meta"], spec["dot"]], ["Mirebloom", "OU · T7", "active"], "your move")
	assert_eq(spec["tooltip"], "Battle versus Mirebloom, your move", "tooltip")
	battle.apply_request({"wait": true, "side": {"id": "p1", "name": "Ash", "pokemon": []}})
	assert_eq(Main.battle_tab_spec(battle)["dot"], "waiting", "waiting for the opponent")
	battle.apply(PSParser.parse_frame("|win|Ash")[0])
	assert_eq([Main.battle_tab_spec(battle)["meta"], Main.battle_tab_spec(battle)["dot"]], ["OU · won", ""], "won")
	var watched := BattleState.new("battle-gen9randombattle-9")
	watched.apply(PSParser.parse_frame("|player|p2|Misty|1|")[0])
	assert_eq(Main.battle_tab_spec(watched)["meta"], "Random", "format from the room id")


func test_awaiting_choice_follows_requests() -> void:
	var battle := BattleState.new("battle-x")
	battle.apply_request({"teamPreview": true, "side": {"id": "p1", "pokemon": []}})
	assert_true(battle.awaiting_choice, "team preview needs a choice")
	battle.apply_request({"wait": true, "side": {"id": "p1", "pokemon": []}})
	assert_true(not battle.awaiting_choice, "wait")
	battle.apply_request({"forceSwitch": [true], "side": {"id": "p1", "pokemon": []}})
	assert_true(battle.awaiting_choice, "forced switch")


func test_rooms_track_formats_search_and_attention() -> void:
	var formats_changed: Array[bool] = []
	var on_formats := func() -> void: formats_changed.append(true)
	EventBus.formats_changed.connect(on_formats)
	_feed(FORMATS)
	assert_eq(Rooms.formats.size(), 5, "formats parsed")
	assert_eq(formats_changed.size(), 1, "formats_changed")
	_feed('|updatesearch|{"searching":["gen9randombattle"],"games":null}')
	assert_eq(Rooms.searching, PackedStringArray(["gen9randombattle"]), "searching")
	assert_true(Rooms.is_searching(), "is_searching")

	var attention: Array[bool] = []
	var on_attention := func(b: BattleState) -> void: attention.append(b.awaiting_choice)
	EventBus.battle_attention_changed.connect(on_attention)
	_feed(">battle-gen9randombattle-21\n|init|battle\n|player|p1|Ash|1|\n|turn|1")
	_feed('>battle-gen9randombattle-21\n|request|{"active":[{"moves":[]}],"side":{"id":"p1","name":"Ash","pokemon":[]},"rqid":2}')
	EventBus.choice_sent.emit("battle-gen9randombattle-21", "move 1")
	EventBus.choice_undone.emit("battle-gen9randombattle-21")
	assert_eq(attention, [true, false, true], "request, choice, undo")
	assert_eq(Rooms.running_battles()[0].room_id, "battle-gen9randombattle-21", "running and waiting for you")

	_feed('|updatesearch|{"searching":[],"games":{"battle-gen9randombattle-21":"[Gen 9] Random Battle"}}')
	assert_eq(Rooms.games.keys(), ["battle-gen9randombattle-21"], "games")
	assert_true(not Rooms.is_searching(), "search over")
	EventBus.formats_changed.disconnect(on_formats)
	EventBus.battle_attention_changed.disconnect(on_attention)
	Rooms.battles.erase("battle-gen9randombattle-21")
	Rooms.games.clear()
	Rooms.formats.clear()


func test_games_running_at_sign_in_come_back_in_the_background() -> void:
	EventBus.logged_in.emit("Ash")
	_feed('|updatesearch|{"searching":[],"games":{"battle-gen9randombattle-31":"[Gen 9] Random Battle"}}')
	_feed(">battle-gen9randombattle-31\n|init|battle\n|turn|4")
	_feed(">battle-gen9randombattle-32\n|init|battle\n|turn|1")
	assert_true(Rooms.get_battle("battle-gen9randombattle-31").restored, "already running: background")
	assert_true(not Rooms.get_battle("battle-gen9randombattle-32").restored, "a new battle opens")
	Rooms.battles.erase("battle-gen9randombattle-31")
	Rooms.battles.erase("battle-gen9randombattle-32")
	Rooms.games.clear()


func test_account_and_welcome() -> void:
	var signed_in := {"state": Connection.State.CONNECTED, "signed_in": true, "username": "Iron Quill", "server_host": "sim3.psim.us"}
	assert_eq(AccountButton.describe(signed_in, ""), {"initials": "IQ", "name": "Iron Quill", "sub": "sim3"}, "signed in")
	assert_eq(AccountButton.describe({"state": Connection.State.CONNECTED}, "")["name"], "Guest", "guest")
	assert_eq(AccountButton.describe({"state": Connection.State.DISCONNECTED}, "ash")["initials"], "AS", "offline, remembered")
	assert_eq(AccountButton.initials(""), "?", "no name")
	assert_eq(StartScreen.welcome("", 0, 1000, 0)["title"], "Welcome to Showdown Desktop", "first launch")
	var back := StartScreen.welcome("ironquill", 1000, 1000 + 7200, 1)
	assert_eq(back, {"title": "Welcome back, ironquill", "sub": "Last session 2 h ago · 1 battle still running"}, "back")
	assert_eq(StartScreen.welcome("ironquill", 0, 50, 2)["sub"], "2 battles still running", "no last session")


func test_news_from_releases() -> void:
	var json := JSON.stringify([
		{"tag_name": "v0.1.0", "name": "First playable", "draft": false, "published_at": "2026-10-20T18:00:00Z",
			"body": "## Highlights\n- **Start screen** and [battle tabs](https://example.com)\n", "html_url": NewsFeed.REPO_URL + "/releases/tag/v0.1.0"},
		{"tag_name": "v0.2.0", "name": "", "draft": true, "body": "secret"},
		{"tag_name": "v0.0.9", "name": "", "published_at": "2026-10-01T00:00:00Z", "body": "", "html_url": "https://evil.example/x"},
	])
	var items := NewsFeed.parse_releases(json)
	assert_eq(items.size(), 2, "drafts are skipped")
	assert_eq([items[0]["title"], items[0]["summary"], NewsFeed.short_date(items[0]["date"])],
		["First playable", "Highlights", "Oct 20"], "first release")
	assert_eq(items[1]["title"], "v0.0.9", "tag when there's no name")
	assert_eq(items[1]["url"], NewsFeed.REPO_URL + "/releases", "only this repository's pages open")
	assert_eq(NewsFeed.summary("<!-- note -->\n**Start screen** and [battle tabs](https://x.y)"), "Start screen and battle tabs", "markup")
	assert_eq(NewsFeed.parse_releases("not json"), [] as Array[Dictionary], "bad json")


func test_notification_history() -> void:
	var before := Notifier.history.duplicate()
	var unread_before := Notifier.unread
	Notifier._remember("your_turn", "Your turn · Turn 3", "vs Misty", Notifier._screen_for_key("your_turn:battle-gen9ou-4"))
	assert_eq(Notifier.history[0]["screen"], "battle:battle-gen9ou-4", "leads to the battle")
	assert_eq(Notifier.unread, unread_before + 1, "unread")
	Notifier.mark_all_read()
	assert_eq(Notifier.unread, 0, "read")
	assert_eq(Notifier._screen_for_key("challenge:misty"), "", "no screen for a challenge")
	assert_eq([NotificationBell.time_ago(30), NotificationBell.time_ago(300), NotificationBell.time_ago(90000)],
		["now", "5 min", "1 d"], "time ago")
	Notifier.history = before
	Notifier.unread = unread_before


func _feed(frame: String) -> void:
	for msg in PSParser.parse_frame(frame):
		EventBus.message_received.emit(msg)
