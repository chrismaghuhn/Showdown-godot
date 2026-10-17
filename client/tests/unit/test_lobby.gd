extends "res://tests/test_case.gd"
## The lobby (#23): challenges, ratings, the format picker, battle cards.

const FORMATS := "|formats|,LL|,1|S/V Singles|[Gen 9] Random Battle,f|[Gen 9] Unrated Random Battle,b|[Gen 9] OU,e|,2|S/V Doubles|[Gen 9] Random Doubles Battle,f|[Gen 9] Custom Game,c"


func _formats() -> Array[Dictionary]:
	return FormatList.parse(FORMATS.trim_prefix("|formats|"))


func test_challenges_from_private_messages() -> void:
	assert_eq(Rooms.challenge_from_pm(" Misty", " Ash", "/challenge gen9randombattle|gen9randombattle|||", "Ash"),
		{"id": "misty", "user": "Misty", "format": "gen9randombattle", "incoming": true,
			"time": Rooms.challenge_from_pm(" Misty", " Ash", "/challenge gen9randombattle", "Ash")["time"]}, "incoming")
	var sent := Rooms.challenge_from_pm("+Ash@!", " Brock", "/challenge gen9ou|gen9ou|||", "ash")
	assert_eq([sent["id"], sent["user"], sent["incoming"]], ["brock", "Brock", false], "outgoing, rank and away marks")
	assert_eq(Rooms.challenge_from_pm(" Misty", " Ash", "/challenge", "Ash"), {"id": "misty", "ended": true}, "ended")
	assert_eq(Rooms.challenge_from_pm(" Misty", " Brock", "/challenge gen9ou", "Ash"), {}, "not about us")
	assert_eq(Rooms.identity_name("@Moderator@!"), "Moderator", "rank and away")


func test_challenges_tracked_from_messages() -> void:
	var was: String = Connection.username
	Connection.username = "Ash"
	var changes: Array[bool] = []
	var on_change := func() -> void: changes.append(true)
	EventBus.challenges_changed.connect(on_change)
	_feed("|pm| Misty| Ash|/challenge gen9randombattle|gen9randombattle|||")
	assert_true(Rooms.challenges.has("misty") and Rooms.challenges["misty"]["incoming"], "incoming challenge")
	_feed("|pm| Misty| Ash|/challenge")
	assert_true(not Rooms.challenges.has("misty"), "ended")
	_feed("|pm| Misty| Ash|/challenge")
	assert_eq(changes.size(), 2, "ending an unknown challenge changes nothing")
	EventBus.challenges_changed.disconnect(on_change)
	Connection.username = was


func test_ratings_from_rank_and_user_json() -> void:
	var html := "<div class=\"ladder\"><div>User: <strong>Ash</strong></div><div style=\"overflow-x: auto;\"><table>" \
		+ "<tr><th>Format</th><th><abbr title=\"Elo rating\">Elo</abbr></th><th>W</th><th>L</th><th>Total</th>" \
		+ "<tr><td>gen9randombattle</td><td><strong>1048</strong></td><td>3</td><td>1</td><td>4</td></tr>" \
		+ "<tr><td>gen8randombattle</td><td><strong>1016</strong></td><td>1</td><td>0</td><td>1</td></tr></table></div></div>"
	assert_eq(Rooms.parse_rank_html(html), {"user": "Ash", "ratings": {
		"gen9randombattle": {"elo": 1048, "w": 3, "l": 1}, "gen8randombattle": {"elo": 1016, "w": 1, "l": 0}}}, "rank")
	var empty := "<div class=\"ladder\"><div>User: <strong>Ash</strong></div><table><tr><td colspan=\"8\"><em>This user has not played any ladder games yet.</em></td></tr></table></div>"
	assert_eq(Rooms.parse_rank_html(empty)["ratings"], {}, "no games")
	var json := '{"username":"Ash","userid":"ash","ratings":{"gen9ou":{"elo":1621.4,"gxe":63.2,"w":40,"l":31,"coil":null},"bad":"x"}}'
	assert_eq(Rooms.parse_ratings_json(json), {"gen9ou": {"elo": 1621, "w": 40, "l": 31}}, "user json")
	assert_eq(Rooms.parse_ratings_json("<html>"), {}, "not json")


func test_format_picker_entries() -> void:
	var formats := _formats()
	var search: Array = FormatPicker.entries(formats, FormatPicker.Purpose.SEARCH, "").map(func(e: Dictionary) -> String: return e["id"])
	assert_eq(search, ["gen9randombattle", "gen9unratedrandombattle", "gen9ou", "gen9randomdoublesbattle"], "ladder formats")
	var challenge: Array = FormatPicker.entries(formats, FormatPicker.Purpose.CHALLENGE, "custom").map(func(e: Dictionary) -> String: return e["id"])
	assert_eq(challenge, ["gen9customgame"], "challenge-only formats, searchable by name")
	var doubles := FormatPicker.entries(formats, FormatPicker.Purpose.SEARCH, "random doubles")
	assert_eq([doubles.size(), doubles[0]["section"]], [1, "S/V Doubles"], "every word must match")
	var ou := FormatPicker.entries(formats, FormatPicker.Purpose.SEARCH, "ou")
	assert_eq([ou[0]["id"], ou[0]["enabled"]], ["gen9ou", false], "needs a team: shown, not pickable")


func test_rated_line_and_rating_rows() -> void:
	var formats := _formats()
	var ratings := {"gen9randombattle": {"elo": 1048, "w": 3, "l": 1}, "gen9ou": {"elo": 1621, "w": 40, "l": 31}}
	assert_eq(HomeScreen.rated_line("gen9randombattle", formats[0], ratings), "Rated · your ladder rating 1048", "rated")
	assert_eq(HomeScreen.rated_line("gen9randomdoublesbattle", formats[3], ratings), "Rated · no rating in this format yet", "none yet")
	assert_eq(HomeScreen.rated_line("gen9unratedrandombattle", formats[1], ratings), "Unrated", "unrated")
	assert_eq(HomeScreen.rating_rows(ratings, formats), [["[Gen 9] OU", 1621], ["[Gen 9] Random Battle", 1048]], "highest first")
	var signed_in := {"state": Connection.State.CONNECTED, "signed_in": true, "username": "Ash", "server_host": "localhost:8000"}
	assert_eq(AccountButton.describe(signed_in, "", "OU 1621")["sub"], "OU 1621", "header shows the rating")
	assert_eq(AccountButton.describe(signed_in, "")["sub"], "localhost", "or the server")


func test_player_rating_and_teams_left() -> void:
	var battle := BattleState.new("battle-gen9ou-3")
	for line in ["|player|p1|Ash|1|1621", "|player|p2|Misty|2|1588", "|player|p2|", "|teamsize|p2|6",
			"|switch|p2a: Gholdengo|Gholdengo, L100|100/100", "|faint|p2a: Gholdengo"]:
		battle.apply(PSParser.parse_frame(line)[0])
	assert_eq([battle.side("p1").rating, battle.side("p2").rating], [1621, 1588], "ratings from |player|")
	assert_eq(LobbyBattleCard._left(battle.side("p2")), 5, "one fainted")
	assert_eq(LobbyBattleCard._left(battle.side("p1")), 6, "team size unknown: 6")


func _feed(frame: String) -> void:
	for msg in PSParser.parse_frame(frame):
		EventBus.message_received.emit(msg)


func test_rank_reply_as_server_pm() -> void:
	var was_awaiting: String = Rooms._awaiting_rank
	var was_ratings: Dictionary = Rooms.ratings
	Rooms._awaiting_rank = "ash"
	_feed("|pm| Ash|~|/raw <div class=\"ladder\"><div>User: <strong>Ash</strong></div><table><tr><td>gen9randombattle</td><td><strong>1031</strong></td><td>1</td><td>0</td><td>1</td></tr></table></div>")
	assert_eq(Rooms.ratings, {"gen9randombattle": {"elo": 1031, "w": 1, "l": 0}}, "parsed from the server's PM")
	assert_eq(Rooms._awaiting_rank, "", "answered")
	Rooms._awaiting_rank = was_awaiting
	Rooms.ratings = was_ratings


func test_challenge_toast_goes_when_the_challenge_ends() -> void:
	var was: String = Connection.username
	Connection.username = "Ash"
	var dismissed: Array[String] = []
	var on_dismiss := func(key: String) -> void: dismissed.append(key)
	EventBus.toast_dismissed.connect(on_dismiss)
	_feed("|pm| Misty| Ash|/challenge gen9randombattle|gen9randombattle|||")
	# Declined or accepted on our side: the server sends the end from us to them.
	_feed("|pm| Ash| Misty|/challenge")
	assert_true("challenge:misty" in dismissed, "the toast goes")
	EventBus.toast_dismissed.disconnect(on_dismiss)
	Connection.username = was


func test_ratings_and_challenges_cleared() -> void:
	Rooms.ratings = {"gen9ou": {"elo": 1500, "w": 1, "l": 0}}
	EventBus.signed_out.emit()
	assert_eq(Rooms.ratings, {}, "signed out: no ratings")
	Rooms.challenges = {"misty": {"id": "misty", "user": "Misty", "format": "gen9ou", "incoming": true, "time": 0}}
	Rooms.ratings = {"gen9ou": {"elo": 1500, "w": 1, "l": 0}}
	EventBus.connection_state_changed.emit(Connection.State.WAITING)
	assert_eq([Rooms.challenges, Rooms.ratings], [{}, {}], "connection lost: neither")


func test_rank_replies_for_others_are_ignored() -> void:
	var was_awaiting: String = Rooms._awaiting_rank
	Rooms._awaiting_rank = "ash"
	Rooms.ratings = {}
	_feed("|raw|<div class=\"ladder\"><div>User: <strong>Brock</strong></div><table><tr><td>gen9ou</td><td><strong>1700</strong></td><td>9</td><td>1</td><td>10</td></tr></table></div>")
	assert_eq(Rooms.ratings, {}, "someone else's /rank")
	_feed("|raw|<div class=\"ladder\"><div>User: <strong>Ash</strong></div><table><tr><td>gen9ou</td><td><strong>1520</strong></td><td>2</td><td>1</td><td>3</td></tr></table></div>")
	assert_eq(Rooms.ratings, {"gen9ou": {"elo": 1520, "w": 2, "l": 1}}, "ours, as |raw| in a room")
	Rooms._awaiting_rank = was_awaiting
	Rooms.ratings = {}


func test_which_formats_need_a_team() -> void:
	var formats := _formats()
	assert_true(not Rooms.format_needs_team(formats, "gen9randombattle"), "random battle")
	assert_true(Rooms.format_needs_team(formats, "gen9ou"), "OU")
	assert_true(Rooms.format_needs_team(formats, "gen9ou@@@-Swagger"), "custom rules")
	assert_true(Rooms.format_needs_team(formats, "gen1nonsense"), "unknown")


func test_challenge_before_signing_in_waits() -> void:
	var asked: Array[bool] = []
	var on_ask := func() -> void: asked.append(true)
	EventBus.sign_in_requested.connect(on_ask)
	Rooms.challenge("Misty", "gen9randombattle")
	assert_eq([Rooms._pending_challenge, asked.size()], [["misty", "gen9randombattle"], 1], "waits for a name")
	EventBus.signed_out.emit()
	assert_eq(Rooms._pending_challenge, [], "dropped with the sign-out")
	EventBus.sign_in_requested.disconnect(on_ask)


func test_rated_battles_are_marked() -> void:
	var battle := BattleState.new("battle-gen9randombattle-5")
	battle.apply(PSParser.parse_frame("|rated|")[0])
	assert_true(battle.rated, "|rated|")
	var tour := BattleState.new("battle-gen9randombattle-6")
	tour.apply(PSParser.parse_frame("|rated|Tournament battle")[0])
	assert_true(not tour.rated, "|rated|MESSAGE is only a note")
	assert_true(not BattleState.new("x").rated, "challenge battles aren't")


func test_format_label_before_the_server_list() -> void:
	var formats := _formats()
	assert_eq(FormatPicker.label_for("gen9ou", formats, "", ""), "[Gen 9] OU", "the server's name")
	assert_eq(FormatPicker.label_for("gen9randombattle", [] as Array[Dictionary], "", ""), "[Gen 9] Random Battle",
		"first launch, offline: the default's name, not its id")
	assert_eq(FormatPicker.label_for("gen8randombattle", [] as Array[Dictionary], "gen8randombattle", "[Gen 8] Random Battle"),
		"[Gen 8] Random Battle", "offline: the remembered name")
	assert_eq(FormatPicker.label_for("gen8randombattle", [] as Array[Dictionary], "gen9ou", "[Gen 9] OU"),
		"gen8randombattle", "nothing known: the id")
	assert_eq(FormatPicker.label_for("", formats, "", ""), "Choose a format", "nothing picked")
	assert_eq(FormatPicker.label_for("gen8randombattle", [] as Array[Dictionary], "gen8randombattle", ""),
		"gen8randombattle", "remembered without a name: the id")
	assert_eq(FormatPicker.label_for("gen9randombattle", [] as Array[Dictionary], "gen9randombattle", "[Gen 8] Random Battle"),
		"[Gen 9] Random Battle", "the default's name wins over a stale remembered one")


func test_remembered_format_and_name_stay_together() -> void:
	var was_formats: Array[Dictionary] = Rooms.formats
	Rooms.formats = _formats()
	Rooms.remember_format("gen9ou")
	assert_eq([AppConfig.get_setting("play", "last_format"), AppConfig.get_setting("play", "last_format_name")],
		["gen9ou", "[Gen 9] OU"], "known format: id and name")
	Rooms.formats = [] as Array[Dictionary]
	Rooms.remember_format("gen8randombattle")
	assert_eq([AppConfig.get_setting("play", "last_format"), AppConfig.get_setting("play", "last_format_name")],
		["gen8randombattle", ""], "unknown name: none, rather than the last format's")
	Rooms.formats = was_formats
