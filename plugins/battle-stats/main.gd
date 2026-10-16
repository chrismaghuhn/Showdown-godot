extends ClientPlugin
## Example plugin: shows simple statistics for the current battle in the sidebar.

var _label := Label.new()
var _moves := {}
var _faints := {}


func _plugin_enable() -> void:
	_label.text = "Battle Stats: no battle yet"
	api.add_panel(&"sidebar", _label)
	api.on(&"battle_started", _on_battle_started)
	api.on(&"battle_updated", _on_battle_updated)


func _on_battle_started(_battle: BattleState) -> void:
	_moves.clear()
	_faints.clear()


func _on_battle_updated(battle: BattleState, msg: PSMessage) -> void:
	var side := msg.arg(0).substr(0, 2)
	match msg.type:
		"move":
			_moves[side] = int(_moves.get(side, 0)) + 1
		"faint":
			_faints[side] = int(_faints.get(side, 0)) + 1
		_:
			return
	var lines := PackedStringArray(["Battle Stats - turn %d" % battle.turn])
	for side_id: String in battle.sides:
		lines.append("%s: %d moves, %d fainted" % [
			battle.side(side_id).player_name, _moves.get(side_id, 0), _faints.get(side_id, 0)])
	_label.text = "\n".join(lines)
