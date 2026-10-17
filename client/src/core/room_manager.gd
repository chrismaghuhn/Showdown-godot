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
## This user's running games {room_id: title} (|updatesearch|), joined or not.
var games := {}

## Games that were already running when we signed in (after a restart): their battles come
## back in the background instead of taking over the screen.
var _games_at_sign_in := {}
var _await_games_snapshot := false
## A search the user asked for before signing in; it starts once signed in.
var _pending_search := ""

## room_id -> true while its |init| is outstanding after a reconnect
var _restoring := {}
var _restored := 0
var _restore_active := false
var _restore_gen := 0
## Rooms whose battle had ended before it was replayed: their |win| is not news.
var _replayed_ended := {}


func _ready() -> void:
	EventBus.message_received.connect(_on_message)
	EventBus.reconnected.connect(_on_reconnected)
	EventBus.connection_state_changed.connect(_on_connection_state_changed)
	EventBus.logged_in.connect(func(_username: String) -> void:
		_await_games_snapshot = true
		_games_at_sign_in.clear()
		if not _pending_search.is_empty():
			var format := _pending_search
			_pending_search = ""
			search(format))
	EventBus.signed_out.connect(func() -> void: _pending_search = "")
	EventBus.choice_sent.connect(func(room_id: String, _choice: String) -> void: _set_attention(room_id, false))
	EventBus.choice_undone.connect(func(room_id: String) -> void:
		var battle: BattleState = battles.get(room_id)
		if battle != null and not battle.ended and not battle.request.is_empty() and not battle.request.get("wait", false):
			_set_attention(room_id, true))


func get_battle(room_id: String) -> BattleState:
	return battles.get(room_id)


## Searches a battle in `format_id` (e.g. "gen9randombattle"). Not signed in yet: asks for a
## name first and searches right after.
func search(format_id: String) -> void:
	AppConfig.set_setting("play", "last_format", format_id)
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
			EventBus.private_message.emit(msg.arg(0).strip_edges(), msg.arg(1).strip_edges(), msg.arg(2))
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
