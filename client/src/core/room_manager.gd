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


func get_battle(room_id: String) -> BattleState:
	return battles.get(room_id)


func _on_message(msg: PSMessage) -> void:
	var room_id := msg.room_id
	match msg.type:
		"init":
			if msg.arg(0) == "battle":
				var battle := BattleState.new(room_id)
				var previous: BattleState = battles.get(room_id)
				# Every battle that comes back during a restore stays in the background.
				battle.restored = _restore_active and (_restoring.has(room_id) or previous != null)
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
			# |noinit|nonexistent|... - the battle room is gone (expired on the server).
			if _restoring.has(room_id) and msg.arg(0) == "nonexistent" and battles.has(room_id):
				# Anything still showing it (battle screen, tab) sees it as over.
				(battles[room_id] as BattleState).ended = true
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
		"updatesearch":
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
			battle.apply_request(data)
			EventBus.battle_request.emit(battle, data)
		return
	battle.apply(msg)
	if msg.type == "player":
		battle.claim_side_by_name(Connection.username)
	EventBus.battle_updated.emit(battle, msg)
	if msg.type == "win" or msg.type == "tie":
		if _replayed_ended.has(room_id):
			_replayed_ended.erase(room_id)
		else:
			EventBus.battle_ended.emit(battle, battle.winner)


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
