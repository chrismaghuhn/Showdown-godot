class_name BattleLogBuilder
extends RefCounted
## Turns battle messages into log entries for the battle screen (design: "Battle log").
## Call push() after BattleState.apply(); read new entries with take_new().
##
## Entry kinds:
##   {"kind": "turn", "turn": int, "time": "21:43"}
##   {"kind": "row", "text": String (BBCode, every name escaped), "indent": bool,
##    "chips": [[text, "up" | "down" | "neutral"]]}
## Effectiveness, crits and damage are attached as chips to the move row they belong to.
## Indented rows are secondary effects; the compact view hides them.

## Damage sources that arrive as status ids ("[from] brn").
const STATUS_NAMES := {"brn": "Burn", "psn": "Poison", "tox": "Poison", "par": "Paralysis",
	"slp": "Sleep", "frz": "Freeze"}

var entries: Array[Dictionary] = []
var _taken := 0
## "p1: Name" -> last known HP percent, to show damage as a delta.
var _hp := {}
var _last_move: Dictionary = {}
var _last_boost_row: Dictionary = {}
var _last_boost_ident := ""


func take_new() -> Array[Dictionary]:
	var result: Array[Dictionary] = entries.slice(_taken)
	_taken = entries.size()
	return result


func push(msg: PSMessage, battle: BattleState) -> void:
	if msg.type != "-boost" and msg.type != "-unboost":
		_last_boost_ident = ""
	match msg.type:
		"turn":
			_last_move = {}
			entries.append({"kind": "turn", "turn": msg.arg(0).to_int(), "time": Time.get_time_string_from_system().left(5)})
		"switch", "drag":
			var ref := BattleState.parse_ident(msg.arg(0))
			var player := battle.side(ref["side"]).player_name
			_row("%s sent out %s!" % [esc(player), b(ref["name"])])
			_remember_hp(msg.arg(0), battle)
		"replace":
			# Illusion ended: the revealed Pokémon has the disguise's HP now.
			_remember_hp(msg.arg(0), battle)
		"move":
			_last_move = _row("%s used %s!" % [_name(msg.arg(0), battle, true), b(msg.arg(1))])
		"-supereffective":
			_chip_on_move("×2", "up")
		"-resisted":
			_chip_on_move("×0.5", "down")
		"-crit":
			_chip_on_move("Crit", "up")
		"-damage", "-heal":
			_on_hp_change(msg, battle)
		"-boost", "-unboost":
			_on_boost(msg, battle)
		"-status":
			_row("%s is now %s." % [_name(msg.arg(0), battle, true), esc(msg.arg(1).to_upper())], true)
		"-curestatus":
			_row("%s was cured of %s." % [_name(msg.arg(0), battle, true), esc(msg.arg(1).to_upper())], true)
		"faint":
			_row("%s fainted!" % _name(msg.arg(0), battle, true))
		"-weather":
			if msg.kwargs.has("upkeep"):
				return
			if msg.arg(0) == "none":
				_row("The weather cleared.", true)
			else:
				_row("%s started." % b(FieldConditions.weather_name(msg.arg(0))), true)
		"-fieldstart":
			_row("%s started." % b(BattleState.effect_name(msg.arg(0))), true)
		"-fieldend":
			_row("%s ended." % esc(BattleState.effect_name(msg.arg(0))), true)
		"-sidestart":
			var side_player := battle.side(msg.arg(0).substr(0, 2)).player_name
			_row("%s on %s's side." % [b(BattleState.effect_name(msg.arg(1))), esc(side_player)], true)
		"-sideend":
			var side_player := battle.side(msg.arg(0).substr(0, 2)).player_name
			_row("%s ended on %s's side." % [esc(BattleState.effect_name(msg.arg(1))), esc(side_player)], true)
		"-terastallize":
			_row("%s has Terastallized into the %s-type!" % [_name(msg.arg(0), battle, true), b(msg.arg(1))])
		"-start":
			_row("%s: %s" % [_name(msg.arg(0), battle, true), esc(BattleState.effect_name(msg.arg(1)))], true)
		"-end":
			_row("%s: %s ended" % [_name(msg.arg(0), battle, true), esc(BattleState.effect_name(msg.arg(1)))], true)
		"-miss":
			_row("%s avoided the attack!" % _name(msg.arg(1), battle, true), true)
		"-fail":
			_row("But it failed!", true)
		"-immune":
			_row("It doesn't affect %s…" % _name(msg.arg(0), battle, false), true)
		"cant":
			_row("%s can't move (%s)." % [_name(msg.arg(0), battle, true), esc(BattleState.effect_name(msg.arg(1)))])
		"-item":
			_row("%s's item: %s" % [_name(msg.arg(0), battle, true), b(msg.arg(1))], true)
		"-enditem":
			_row("%s's %s was used up." % [_name(msg.arg(0), battle, true), esc(msg.arg(1))], true)
		"-ability":
			_row("%s's Ability: %s" % [_name(msg.arg(0), battle, true), b(msg.arg(1))], true)
		"-message", "-hint":
			_row(esc(msg.arg(0)), true)
		"win":
			_row("%s won the battle!" % b(msg.arg(0)))
		"tie":
			_row("The battle ended in a tie.")


## Escapes text for RichTextLabel BBCode ("[" can't open a tag).
static func esc(text: String) -> String:
	return text.replace("[", "[lb]")


static func b(text: String) -> String:
	return "[b]" + esc(text) + "[/b]"


func _row(text: String, indent := false) -> Dictionary:
	var entry := {"kind": "row", "text": text, "indent": indent, "chips": []}
	entries.append(entry)
	return entry


func _chip_on_move(text: String, kind: String) -> void:
	if not _last_move.is_empty():
		_last_move["chips"].append([text, kind])


func _on_hp_change(msg: PSMessage, battle: BattleState) -> void:
	var key := _key(msg.arg(0))
	var before: float = _hp.get(key, 100.0)
	_remember_hp(msg.arg(0), battle)
	var after: float = _hp[key]
	var delta := roundi(after - before)
	if delta == 0:
		return
	var name := esc(BattleState.parse_ident(msg.arg(0))["name"])
	var chip := ["%s %s%d%%" % [name, "+" if delta > 0 else "−", absi(delta)], "up" if delta > 0 else "down"]
	var source := str(msg.kwargs.get("from", ""))
	if source.is_empty() and not _last_move.is_empty():
		_last_move["chips"].append(chip)
		return
	var label: String = STATUS_NAMES.get(source, BattleState.effect_name(source)) if not source.is_empty() \
		else ("Damage" if delta < 0 else "Healed")
	var entry := _row(esc(label), true)
	entry["chips"].append(chip)


func _on_boost(msg: PSMessage, battle: BattleState) -> void:
	var amount := msg.arg(2).to_int() * (1 if msg.type == "-boost" else -1)
	var stat: String = BoostChip.STAT_LABELS.get(msg.arg(1), msg.arg(1))
	var chip := ["%s%d %s" % ["+" if amount >= 0 else "−", absi(amount), stat], "up" if amount >= 0 else "down"]
	if _last_boost_ident == msg.arg(0) and not _last_boost_row.is_empty():
		_last_boost_row["chips"].append(chip)
		return
	_last_boost_row = _row(_name(msg.arg(0), battle, true), true)
	_last_boost_row["chips"].append(chip)
	_last_boost_ident = msg.arg(0)


func _remember_hp(ident: String, battle: BattleState) -> void:
	_hp[_key(ident)] = battle.get_pokemon(ident).hp_percent()


## "p1a: Name" and "p1: Name" refer to the same Pokémon.
static func _key(ident: String) -> String:
	var ref := BattleState.parse_ident(ident)
	return "%s: %s" % [ref["side"], ref["name"]]


## "The opposing Gholdengo" at the start of a sentence, "the opposing …" inside it.
static func _name(ident: String, battle: BattleState, sentence_start: bool) -> String:
	var ref := BattleState.parse_ident(ident)
	var plain := esc(ref["name"])
	if battle.my_side.is_empty() or ref["side"] == battle.my_side:
		return plain
	return ("The opposing " if sentence_start else "the opposing ") + plain
