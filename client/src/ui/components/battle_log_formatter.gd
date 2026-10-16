class_name BattleLogFormatter
extends RefCounted
## Turns battle protocol messages into readable log lines.
## Called after BattleState.apply(), so the state already reflects the message.
## Returns "" for messages that should not appear in the log.


static func format(msg: PSMessage, battle: BattleState) -> String:
	match msg.type:
		"turn":
			return _t("=== Turn %s ===") % msg.arg(0)
		"switch", "drag":
			var ref := BattleState.parse_ident(msg.arg(0))
			var mon := battle.get_pokemon(msg.arg(0))
			return _t("%s sent out %s (%s)!") % [
				battle.side(ref["side"]).player_name, mon.name, mon.species]
		"move":
			return _t("%s used %s!") % [_mon(msg.arg(0), battle), msg.arg(1)]
		"-damage", "-heal":
			var mon := battle.get_pokemon(msg.arg(0))
			var line := _t("%s: %d%% HP") % [_mon(msg.arg(0), battle), roundi(mon.hp_percent())]
			return line + (_t(" (from %s)") % msg.kwargs["from"] if msg.kwargs.has("from") else "")
		"faint":
			return _t("%s fainted!") % _mon(msg.arg(0), battle)
		"-status":
			return _t("%s is now %s.") % [_mon(msg.arg(0), battle), msg.arg(1)]
		"-curestatus":
			return _t("%s is cured of %s.") % [_mon(msg.arg(0), battle), msg.arg(1)]
		"-boost":
			return _t("%s: %s +%s") % [_mon(msg.arg(0), battle), msg.arg(1), msg.arg(2)]
		"-unboost":
			return _t("%s: %s -%s") % [_mon(msg.arg(0), battle), msg.arg(1), msg.arg(2)]
		"-weather":
			if msg.kwargs.has("upkeep"):
				return ""
			return _t("Weather cleared.") if msg.arg(0) == "none" else _t("Weather: %s") % msg.arg(0)
		"-supereffective":
			return _t("It's super effective!")
		"-resisted":
			return _t("It's not very effective...")
		"-immune":
			return _t("%s is not affected.") % _mon(msg.arg(0), battle)
		"-crit":
			return _t("A critical hit!")
		"-miss":
			return _t("%s avoided the attack!") % _mon(msg.arg(1), battle)
		"-fail":
			return _t("But it failed!")
		"cant":
			return _t("%s can't move (%s).") % [_mon(msg.arg(0), battle), msg.arg(1)]
		"-ability":
			return _t("[%s's %s]") % [_mon(msg.arg(0), battle), msg.arg(1)]
		"-terastallize":
			return _t("%s terastallized into %s!") % [_mon(msg.arg(0), battle), msg.arg(1)]
		"win":
			return _t("%s won the battle!") % msg.arg(0)
		"tie":
			return _t("The battle ended in a tie.")
		"error":
			return _t("Error: %s") % msg.arg(0)
	return ""


static func _mon(ident: String, battle: BattleState) -> String:
	var ref := BattleState.parse_ident(ident)
	if not battle.my_side.is_empty() and ref["side"] != battle.my_side:
		return _t("the opposing %s") % ref["name"]
	return ref["name"]


static func _t(text: String) -> String:
	return TranslationServer.translate(text)
