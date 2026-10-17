extends ClientPlugin
## Development plugin: plays battles on its own by picking random legal choices.


func _plugin_enable() -> void:
	api.on(&"battle_request", _on_battle_request)


func _on_battle_request(battle: BattleState, request: Dictionary) -> void:
	if request.get("wait", false):
		return
	var rqid := int(request.get("rqid", -1))
	if request.get("teamPreview", false):
		api.choose(battle.room_id, "default", rqid)
		return

	var choices := legal_choices(request)
	var choice := "default" if choices.is_empty() else choices[randi() % choices.size()]
	api.choose(battle.room_id, choice, rqid)


## What the autopilot picks from: the usable moves, or the switches when there are none or a
## switch is forced. Switch targets follow BattleChoices like the battle screen, so a Revival
## Blessing request offers the fainted Pokémon (the server rejects any other pick and sends no
## new request).
static func legal_choices(request: Dictionary) -> PackedStringArray:
	var choices := PackedStringArray()
	var active: Array = request.get("active", [])
	var force_switch: Array = request.get("forceSwitch", [])
	if force_switch.is_empty() and not active.is_empty():
		var moves: Array = active[0].get("moves", [])
		for i in moves.size():
			if not moves[i].get("disabled", false) and int(moves[i].get("pp", 1)) > 0:
				choices.append("move %d" % (i + 1))
	if choices.is_empty() or not force_switch.is_empty():
		var team: Array = request.get("side", {}).get("pokemon", [])
		for i in team.size():
			var mon := BattlePokemon.new()
			mon.active = team[i].get("active", false)
			mon.apply_condition(str(team[i].get("condition", "")))
			if BattleChoices.can_switch_to(request, mon):
				choices.append("switch %d" % (i + 1))
	return choices
