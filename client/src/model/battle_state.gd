class_name BattleState
extends RefCounted
## The client's view of one battle, built purely from protocol messages.
##
## No network, UI or autoload dependencies: feed it PSMessages (live, replay or test)
## and read the state. The server does all game mechanics; this only mirrors them.

var room_id := ""
var format := ""
var gen := 0
var game_type := "singles"
var turn := 0
## Our side id ("p1"/"p2") once the server sent a |request|; "" when spectating.
var my_side := ""
## "p1" -> BattleSide
var sides := {}
var weather := ""
var field_conditions := PackedStringArray()
## Latest |request| payload (what we may choose this turn).
var request := {}
var ended := false
var winner := ""


func _init(id := "") -> void:
	room_id = id


func side(side_id: String) -> BattleSide:
	if not sides.has(side_id):
		sides[side_id] = BattleSide.new(side_id)
	return sides[side_id]


## Splits "p1a: Pikachu" into {"side": "p1", "slot": 0, "name": "Pikachu"}.
static func parse_ident(ident: String) -> Dictionary:
	var colon := ident.find(": ")
	var position := ident if colon == -1 else ident.substr(0, colon)
	var slot := 0
	if position.length() >= 3:
		slot = position.unicode_at(2) - "a".unicode_at(0)
	return {
		"side": position.substr(0, 2),
		"slot": slot,
		"name": "" if colon == -1 else ident.substr(colon + 2),
	}


func get_pokemon(ident: String) -> BattlePokemon:
	var ref := parse_ident(ident)
	return side(ref["side"]).get_or_add(ref["name"])


func apply(msg: PSMessage) -> void:
	match msg.type:
		"player":
			if not msg.arg(1).is_empty():
				side(msg.arg(0)).player_name = msg.arg(1)
		"teamsize":
			side(msg.arg(0)).team_size = msg.arg(1).to_int()
		"gametype":
			game_type = msg.arg(0)
		"gen":
			gen = msg.arg(0).to_int()
		"tier":
			format = msg.arg(0)
		"turn":
			turn = msg.arg(0).to_int()
		"switch", "drag", "replace":
			var ref := parse_ident(msg.arg(0))
			var s := side(ref["side"])
			var mon := s.get_or_add(ref["name"])
			mon.apply_details(msg.arg(1))
			mon.apply_condition(msg.arg(2))
			s.set_active(ref["slot"], mon)
		"detailschange", "-formechange":
			get_pokemon(msg.arg(0)).apply_details(msg.arg(1))
		"-damage", "-heal", "-sethp":
			get_pokemon(msg.arg(0)).apply_condition(msg.arg(1))
		"faint":
			var mon := get_pokemon(msg.arg(0))
			mon.hp = 0
			mon.fainted = true
			mon.status = ""
		"-status":
			get_pokemon(msg.arg(0)).status = msg.arg(1)
		"-curestatus":
			get_pokemon(msg.arg(0)).status = ""
		"-boost":
			get_pokemon(msg.arg(0)).boost(msg.arg(1), msg.arg(2).to_int())
		"-unboost":
			get_pokemon(msg.arg(0)).boost(msg.arg(1), -msg.arg(2).to_int())
		"-setboost":
			get_pokemon(msg.arg(0)).boosts[msg.arg(1)] = msg.arg(2).to_int()
		"-clearboost", "-clearnegativeboost":
			get_pokemon(msg.arg(0)).boosts.clear()
		"-clearallboost":
			for s: BattleSide in sides.values():
				for mon: BattlePokemon in s.pokemon.values():
					mon.boosts.clear()
		"-weather":
			weather = "" if msg.arg(0) == "none" else msg.arg(0)
		"-fieldstart":
			var effect := effect_name(msg.arg(0))
			if not effect in field_conditions:
				field_conditions.append(effect)
		"-fieldend":
			var index := field_conditions.find(effect_name(msg.arg(0)))
			if index != -1:
				field_conditions.remove_at(index)
		"-sidestart":
			side(msg.arg(0).substr(0, 2)).conditions[effect_name(msg.arg(1))] = true
		"-sideend":
			side(msg.arg(0).substr(0, 2)).conditions.erase(effect_name(msg.arg(1)))
		"win":
			ended = true
			winner = msg.arg(0)
		"tie":
			ended = true


## Applies a parsed |request| JSON. Our own side gets exact HP and move lists from it.
func apply_request(req: Dictionary) -> void:
	request = req
	var side_data: Variant = req.get("side")
	if not side_data is Dictionary:
		return
	my_side = str(side_data.get("id", my_side))
	var s := side(my_side)
	s.player_name = str(side_data.get("name", s.player_name))
	for entry: Variant in side_data.get("pokemon", []):
		if not entry is Dictionary:
			continue
		var mon := s.get_or_add(parse_ident(str(entry.get("ident", "")))["name"])
		mon.apply_details(str(entry.get("details", "")))
		mon.apply_condition(str(entry.get("condition", "")))
		mon.moves = PackedStringArray(entry.get("moves", []))


## "move: Stealth Rock" -> "Stealth Rock"
static func effect_name(effect: String) -> String:
	var colon := effect.find(": ")
	return effect if colon == -1 else effect.substr(colon + 2)
