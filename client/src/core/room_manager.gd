extends Node
## Autoload "Rooms": routes protocol messages to rooms and battles and publishes
## higher-level events (chat, battle updates) on the EventBus.

## room_id -> BattleState
var battles := {}


func _ready() -> void:
	EventBus.message_received.connect(_on_message)


func get_battle(room_id: String) -> BattleState:
	return battles.get(room_id)


func _on_message(msg: PSMessage) -> void:
	var room_id := msg.room_id
	match msg.type:
		"init":
			if msg.arg(0) == "battle":
				battles[room_id] = BattleState.new(room_id)
			EventBus.room_joined.emit(room_id, msg.arg(0))
			if battles.has(room_id):
				EventBus.battle_started.emit(battles[room_id])
			return
		"deinit":
			battles.erase(room_id)
			EventBus.room_left.emit(room_id)
			return
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
	EventBus.battle_updated.emit(battle, msg)
	if msg.type == "win" or msg.type == "tie":
		EventBus.battle_ended.emit(battle, battle.winner)
