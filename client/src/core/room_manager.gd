extends Node
## Autoload "Rooms": routes protocol messages to rooms and battles and publishes
## higher-level events (chat, battle updates) on the EventBus.
##
## After a reconnect the server rejoins a returning user's battle rooms on its own and sends
## each with its full log (|init|). Battles that don't come back within RESTORE_JOIN_DELAY
## (e.g. the server had already dropped the user) are joined again explicitly, including the
## running games listed in |updatesearch|. EventBus.battles_restored reports the count of
## running battles that came back. Battles that had already ended are replayed too, but
## neither counted nor reported as ended a second time.

const RESTORE_JOIN_DELAY := 1.5
const RESTORE_TIMEOUT := 8.0

## room_id -> BattleState
var battles := {}
## The server's formats (FormatList.parse), empty until |formats| arrives.
var formats: Array[Dictionary] = []
## Format ids being searched right now (|updatesearch|).
var searching := PackedStringArray()
## True only while handling a line of an |init| frame (PSMessage.backlog): the chat, results
## etc. being reported happened before we joined.
var replaying := false
## This user's running games {room_id: title} (|updatesearch|), joined or not.
var games := {}
## Open challenges, by the other user's id: {user, format, incoming, time}. They arrive as
## |pm|FROM|TO|/challenge FORMAT|... (both sides); an empty "/challenge" ends one.
var challenges := {}
## The signed-in user's ladder ratings: {format id: {elo, w, l}}. See request_ratings().
var ratings := {}
## Ratings are fetched again this long after a rated battle ends (the ladder updates first).
const RATINGS_AFTER_BATTLE_SEC := 3.0
const RATINGS_MAX_AGE := 60

var _ratings_cache := HttpCache.new("user://cache/ratings")
## /rank was sent and its |raw| reply is expected for this user id.
var _awaiting_rank := ""

## Games that were already running when we signed in (after a restart): their battles come
## back in the background instead of taking over the screen.
var _games_at_sign_in := {}
var _await_games_snapshot := false
## A search the user asked for before signing in; it starts once signed in.
var _pending_search := ""
## A challenge [user, format] the user sent before signing in; it goes out once signed in.
var _pending_challenge: Array = []

## room_id -> true while its |init| is outstanding after a reconnect
var _restoring := {}
var _restored := 0
var _restore_active := false
var _restore_gen := 0
## Rooms whose battle had ended before it was replayed: their |win| is not news.
var _replayed_ended := {}


func _ready() -> void:
	add_child(_ratings_cache)
	EventBus.message_received.connect(_on_message)
	EventBus.battle_ended.connect(func(battle: BattleState, _w: String) -> void:
		if battle.rated:
			get_tree().create_timer(RATINGS_AFTER_BATTLE_SEC).timeout.connect(request_ratings.bind(true)))
	EventBus.reconnected.connect(_on_reconnected)
	EventBus.connection_state_changed.connect(_on_connection_state_changed)
	EventBus.logged_in.connect(func(_username: String) -> void:
		_await_games_snapshot = true
		_games_at_sign_in.clear()
		ratings = {}
		EventBus.ratings_changed.emit()
		request_ratings()
		if not _pending_search.is_empty():
			var format := _pending_search
			_pending_search = ""
			search(format)
		if not _pending_challenge.is_empty():
			var waiting := _pending_challenge
			_pending_challenge = []
			challenge(waiting[0], waiting[1]))
	EventBus.signed_out.connect(func() -> void:
		_pending_search = ""
		_pending_challenge = []
		_clear_ratings())
	EventBus.choice_sent.connect(func(room_id: String, _choice: String) -> void: _set_attention(room_id, false))
	EventBus.choice_undone.connect(func(room_id: String) -> void:
		var battle: BattleState = battles.get(room_id)
		if battle != null and not battle.ended and not battle.request.is_empty() and not battle.request.get("wait", false):
			_set_attention(room_id, true))


func get_battle(room_id: String) -> BattleState:
	return battles.get(room_id)


## Challenges a user to a battle in `format_id`. Names are sent as ids, so nothing typed can
## smuggle in another command.
func challenge(user: String, format_id: String) -> void:
	var userid := PSParser.to_id(user)
	if userid.is_empty():
		return
	if not Connection.signed_in:
		_pending_challenge = [userid, format_id]
		EventBus.sign_in_requested.emit()
		return
	Connection.send("", "/utm null")
	Connection.send("", "/challenge %s, %s" % [userid, PSParser.to_id(format_id)])


func accept_challenge(user: String) -> void:
	# The ladder search would go on and could start a second battle.
	if not searching.is_empty():
		cancel_search()
	Connection.send("", "/utm null")
	Connection.send("", "/accept " + PSParser.to_id(user))


func reject_challenge(user: String) -> void:
	Connection.send("", "/reject " + PSParser.to_id(user))


func cancel_challenge(user: String) -> void:
	Connection.send("", "/cancelchallenge " + PSParser.to_id(user))


## Asks for the signed-in user's ladder ratings (server setting "ratings"); they arrive as
## EventBus.ratings_changed. `fresh`: skip the cache (right after a rated battle).
func request_ratings(fresh := false) -> void:
	if not Connection.signed_in:
		return
	var userid := PSParser.to_id(Connection.username)
	var source := str(AppConfig.get_server(Connection.server_id).get("ratings", "rank"))
	if source == "rank":
		_awaiting_rank = userid
		Connection.send("", "/rank")
		return
	if AppConfig.has_cli("no-data-fetch"):
		return
	var bytes := await _ratings_cache.fetch(source % userid, 0 if fresh else RATINGS_MAX_AGE)
	if not bytes.is_empty() and Connection.signed_in and PSParser.to_id(Connection.username) == userid:
		ratings = parse_ratings_json(bytes.get_string_from_utf8())
		EventBus.ratings_changed.emit()


## Remembers the last format with its name - or with no name while the server's list isn't
## known, so the remembered name never belongs to another format.
func remember_format(format_id: String) -> void:
	AppConfig.set_setting("play", "last_format", format_id)
	AppConfig.set_setting("play", "last_format_name", FormatList.display_name(formats, format_id))


## Searches a battle in `format_id` (e.g. "gen9randombattle"). Not signed in yet: asks for a
## name first and searches right after.
func search(format_id: String) -> void:
	remember_format(format_id)
	if not Connection.signed_in:
		_pending_search = format_id
		EventBus.sign_in_requested.emit()
		return
	Connection.send("", "/utm null")
	Connection.send("", "/search " + format_id)


func cancel_search() -> void:
	_pending_search = ""
	if not searching.is_empty() and Connection.state == Connection.State.CONNECTED:
		Connection.send("", "/cancelsearch")


## Forgets a search or challenge that was waiting for the sign-in ("Not now", "Work offline").
func drop_pending() -> void:
	_pending_search = ""
	_pending_challenge = []


## True while a search runs or waits for the sign-in.
func is_searching() -> bool:
	return not searching.is_empty() or not _pending_search.is_empty()


## Opens a running game: joins its room if the client isn't in it yet (after a restart).
func rejoin(room_id: String) -> void:
	if not battles.has(room_id) and Connection.state == Connection.State.CONNECTED:
		Connection.send("", "/join " + room_id)


## Leaves a battle room; forfeits first if `forfeit` (a running battle you play in).
func leave(room_id: String, forfeit := false) -> void:
	if Connection.state == Connection.State.CONNECTED:
		if forfeit:
			Connection.send(room_id, "/forfeit")
		Connection.send("", "/leave " + room_id)
	else:
		forget(room_id)


## Drops a room locally (the server confirms leaving with |deinit|, offline nobody does).
func forget(room_id: String) -> void:
	if battles.erase(room_id):
		EventBus.room_left.emit(room_id)


func _on_message(msg: PSMessage) -> void:
	replaying = msg.backlog
	_route(msg)
	replaying = false


func _route(msg: PSMessage) -> void:
	var room_id := msg.room_id
	match msg.type:
		"init":
			if msg.arg(0) == "battle":
				var battle := BattleState.new(room_id)
				var previous: BattleState = battles.get(room_id)
				# Every battle that comes back during a restore, or that was already running when
				# we signed in, stays in the background.
				battle.restored = (_restore_active and (_restoring.has(room_id) or previous != null)) \
					or (previous == null and _games_at_sign_in.has(room_id))
				if previous != null and previous.ended:
					_replayed_ended[room_id] = true
				battles[room_id] = battle
				if _restoring.has(room_id):
					_restored += 1
					_restoring.erase(room_id)
			EventBus.room_joined.emit(room_id, msg.arg(0))
			if battles.has(room_id):
				EventBus.battle_started.emit(battles[room_id])
			if _restore_active and _restoring.is_empty():
				_finish_restore(_restore_gen)
			return
		"noinit":
			EventBus.join_failed.emit(room_id, msg.arg(1, msg.arg(0)))
			# |noinit|nonexistent|... - the battle room is gone (expired on the server).
			if _restoring.has(room_id) and msg.arg(0) == "nonexistent" and battles.has(room_id):
				# Anything still showing it (battle screen, tab) sees it as over.
				(battles[room_id] as BattleState).ended = true
				(battles[room_id] as BattleState).expired = true
				battles.erase(room_id)
				EventBus.room_left.emit(room_id)
			_restoring.erase(room_id)
			if _restore_active and _restoring.is_empty():
				_finish_restore(_restore_gen)
		"deinit":
			battles.erase(room_id)
			_replayed_ended.erase(room_id)
			EventBus.room_left.emit(room_id)
			return
		"formats":
			formats = FormatList.parse(msg.raw.trim_prefix("|formats|"))
			EventBus.formats_changed.emit()
		"sentchoice":
			# Rejoining after the choice went out: the request is replayed, the choice too.
			_set_attention(room_id, false)
		"error":
			# The server rejected the choice and waits for another one (no new |request|), or the
			# first choice stands after all (an undo came too late).
			var rejected: BattleState = battles.get(room_id)
			var kind := BattleState.choice_error(msg.arg(0))
			if rejected != null and (kind == "rejected" or kind == "stands") and not rejected.ended \
					and not rejected.request.is_empty() and not rejected.request.get("wait", false):
				_set_attention(room_id, kind == "rejected")
		"updatesearch":
			_on_updatesearch(msg.arg(0))
			if _restore_active:
				_add_running_games(msg.arg(0))
		"c", "chat":
			EventBus.chat_message.emit(room_id, msg.arg(0).strip_edges(), msg.arg(1))
		"c:":
			EventBus.chat_message.emit(room_id, msg.arg(1).strip_edges(), msg.arg(2))
		"pm":
			_on_challenge_pm(msg.arg(0), msg.arg(1), msg.arg(2))
			# Outside a room, /rank answers as a server PM: |pm| NAME|~|/raw <div class="ladder">...
			if msg.arg(2).begins_with("/raw "):
				_on_rank_reply(msg.arg(2).trim_prefix("/raw "))
			EventBus.private_message.emit(msg.arg(0).strip_edges(), msg.arg(1).strip_edges(), msg.arg(2))
		"raw":
			_on_rank_reply(msg.arg(0))
		"popup":
			EventBus.popup.emit(msg.arg(0).replace("||", "\n"))

	var battle: BattleState = battles.get(room_id)
	if battle == null:
		return
	if msg.type == "request":
		var data: Variant = JSON.parse_string(msg.arg(0)) if not msg.arg(0).is_empty() else null
		if data is Dictionary:
			var was_awaiting := battle.awaiting_choice
			battle.apply_request(data)
			EventBus.battle_request.emit(battle, data)
			if battle.awaiting_choice != was_awaiting:
				EventBus.battle_attention_changed.emit(battle)
		return
	var was_awaiting_choice := battle.awaiting_choice
	battle.apply(msg)
	if battle.awaiting_choice != was_awaiting_choice:
		EventBus.battle_attention_changed.emit(battle)
	if msg.type == "player":
		battle.claim_side_by_name(Connection.username)
	EventBus.battle_updated.emit(battle, msg)
	if msg.type == "win" or msg.type == "tie":
		if _replayed_ended.has(room_id):
			_replayed_ended.erase(room_id)
		else:
			EventBus.battle_ended.emit(battle, battle.winner)


## |updatesearch|{"searching": ["gen9randombattle"], "games": {"battle-...": "[Gen 9] Random Battle"}}
func _on_updatesearch(json: String) -> void:
	var data: Variant = JSON.parse_string(json) if not json.is_empty() else null
	if not data is Dictionary:
		return
	searching = PackedStringArray()
	for format: Variant in data.get("searching", []) if data.get("searching") is Array else []:
		searching.append(str(format))
	games = data["games"].duplicate() if data.get("games") is Dictionary else {}
	if _await_games_snapshot:
		_await_games_snapshot = false
		_games_at_sign_in = games.duplicate()
	EventBus.search_changed.emit(searching, games)


func _on_rank_reply(html: String) -> void:
	if _awaiting_rank.is_empty() or not html.begins_with("<div class=\"ladder\">"):
		return
	var parsed := parse_rank_html(html)
	if PSParser.to_id(parsed["user"]) == _awaiting_rank:
		_awaiting_rank = ""
		ratings = parsed["ratings"]
		EventBus.ratings_changed.emit()


func _on_challenge_pm(from: String, to: String, text: String) -> void:
	if not text.begins_with("/challenge"):
		return
	var change := challenge_from_pm(from, to, text, Connection.username)
	if change.is_empty():
		return
	if change.get("ended", false):
		if not challenges.erase(change["id"]):
			return
	else:
		challenges[change["id"]] = change
	EventBus.challenges_changed.emit()


## |pm|FROM|TO|/challenge FORMAT|... between us and someone else -> {id, user, format,
## incoming, time}; an empty "/challenge" -> {id, ended: true}; anything else -> {}.
static func challenge_from_pm(from: String, to: String, text: String, me: String) -> Dictionary:
	var sender := identity_name(from)
	var receiver := identity_name(to)
	var incoming := PSParser.to_id(receiver) == PSParser.to_id(me)
	if not incoming and PSParser.to_id(sender) != PSParser.to_id(me):
		return {}
	var other := sender if incoming else receiver
	var format := text.trim_prefix("/challenge").strip_edges().get_slice("|", 0).strip_edges()
	if format.is_empty():
		return {"id": PSParser.to_id(other), "ended": true}
	return {"id": PSParser.to_id(other), "user": other, "format": format, "incoming": incoming,
		"time": int(Time.get_unix_time_from_system())}


## " ironquill", "+Voice@!" -> the plain name (rank symbol and away marker removed).
static func identity_name(identity: String) -> String:
	var name := identity.strip_edges().get_slice("@!", 0)
	if not name.is_empty() and PSParser.to_id(name[0]).is_empty():
		name = name.substr(1)
	return name.strip_edges()


## The local server's /rank reply: <div class="ladder"><div>User: <strong>NAME</strong></div>
## <table>...<tr><td>FORMAT</td><td><strong>ELO</strong></td><td>W</td><td>L</td>... ->
## {user, ratings: {format: {elo, w, l}}}. Only numbers and ids are taken from it.
static func parse_rank_html(html: String) -> Dictionary:
	var user_match := RegEx.create_from_string("User: <strong>([^<]*)</strong>").search(html)
	var result := {"user": user_match.get_string(1) if user_match != null else "", "ratings": {}}
	var row := RegEx.create_from_string("<tr><td>([a-z0-9]+)</td><td><strong>(\\d+)</strong></td><td>(\\d+)</td><td>(\\d+)</td>")
	for found in row.search_all(html):
		result["ratings"][found.get_string(1)] = {"elo": found.get_string(2).to_int(),
			"w": found.get_string(3).to_int(), "l": found.get_string(4).to_int()}
	return result


## pokemonshowdown.com/users/<id>.json: {"ratings": {"gen9ou": {"elo": 1621, "gxe": 63.2, "w": 40,
## "l": 31, ...}}} -> {format: {elo, w, l}}.
static func parse_ratings_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary or not json.data.get("ratings") is Dictionary:
		return {}
	var result := {}
	for format: Variant in json.data["ratings"]:
		var entry: Variant = json.data["ratings"][format]
		if entry is Dictionary and (entry.get("elo") is float or entry.get("elo") is int):
			result[str(format)] = {"elo": roundi(float(entry["elo"])), "w": int(entry.get("w", 0)), "l": int(entry.get("l", 0))}
	return result


func _set_attention(room_id: String, awaiting: bool) -> void:
	var battle: BattleState = battles.get(room_id)
	if battle != null and battle.awaiting_choice != awaiting:
		battle.awaiting_choice = awaiting
		EventBus.battle_attention_changed.emit(battle)


## Battles that are running (not ended), most urgent first: waiting for your choice, then newest.
func running_battles() -> Array[BattleState]:
	var urgent: Array[BattleState] = []
	var others: Array[BattleState] = []
	var ids := battles.keys()
	ids.reverse()
	for room_id: String in ids:
		var battle: BattleState = battles[room_id]
		if battle.ended:
			continue
		if battle.awaiting_choice:
			urgent.append(battle)
		else:
			others.append(battle)
	urgent.append_array(others)
	return urgent


# --- Restoring battles after a reconnect -----------------------------------------------------

func _on_reconnected() -> void:
	_restore_gen += 1
	_restore_active = true
	_restored = 0
	_restoring.clear()
	for room_id: String in battles:
		if not (battles[room_id] as BattleState).ended:
			_restoring[room_id] = true
	var gen := _restore_gen
	get_tree().create_timer(RESTORE_JOIN_DELAY).timeout.connect(_join_missing.bind(gen))
	get_tree().create_timer(RESTORE_TIMEOUT).timeout.connect(_finish_restore.bind(gen))


## The connection dropped again before the battles were back: start over after the next
## reconnect instead of sending /join into the void.
func _on_connection_state_changed(state: int) -> void:
	if state != Connection.State.CONNECTED and _restore_active:
		_restore_gen += 1
		_restore_active = false
		_restoring.clear()
	if state != Connection.State.CONNECTED and not searching.is_empty():
		searching = PackedStringArray()
		EventBus.search_changed.emit(searching, games)
	# Challenges live on the server per connection; the server resends them after a sign-in.
	if state != Connection.State.CONNECTED and not challenges.is_empty():
		challenges.clear()
		EventBus.challenges_changed.emit()
	if state != Connection.State.CONNECTED:
		_clear_ratings()


func _clear_ratings() -> void:
	_awaiting_rank = ""
	if not ratings.is_empty():
		ratings = {}
		EventBus.ratings_changed.emit()


## True unless the server provides the team: a format that isn't known (custom rules such as
## "gen9ou@@@-Swagger") counts as needing one.
static func format_needs_team(formats: Array[Dictionary], format: String) -> bool:
	var format_id := PSParser.to_id(format.get_slice("@@@", 0))
	for known in formats:
		if known["id"] == format_id:
			return not known["preset_team"] or format.contains("@@@")
	return true


## |updatesearch|{"searching": [...], "games": {"battle-...": "[Gen 9] Random Battle", ...}}
func _add_running_games(json: String) -> void:
	var data: Variant = JSON.parse_string(json)
	if not data is Dictionary or not data.get("games") is Dictionary:
		return
	for room_id: String in data["games"]:
		if room_id.begins_with("battle-") and not battles.has(room_id):
			_restoring[room_id] = true


func _join_missing(gen: int) -> void:
	if gen != _restore_gen or not _restore_active:
		return
	if _restoring.is_empty():
		_finish_restore(gen)
		return
	for room_id: String in _restoring:
		Connection.send("", "/join " + room_id)


func _finish_restore(gen: int) -> void:
	if gen != _restore_gen or not _restore_active:
		return
	_restore_active = false
	_restoring.clear()
	EventBus.battles_restored.emit(_restored)
