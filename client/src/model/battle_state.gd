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
## Turn the current weather started (for "turns left").
var weather_turn := 0
var field_conditions := PackedStringArray()
## Field condition -> turn it started.
var field_turns := {}
## Battle timer (from |inactive|): seconds left this turn and in total; -1 = unknown.
var timer_on := false
var timer_turn_seconds := -1
var timer_total_seconds := -1
## Latest |request| payload (what we may choose this turn).
var request := {}
var ended := false
## Rejoined after a reconnect or restart (the log was replayed from the start).
var restored := false
## The server asked for a choice that hasn't been sent yet ("your move").
var awaiting_choice := false
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
		"move":
			get_pokemon(msg.arg(0)).reveal_move(msg.arg(1))
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
			var new_weather := "" if msg.arg(0) == "none" else msg.arg(0)
			if new_weather != weather and not msg.kwargs.has("upkeep"):
				weather_turn = turn
			weather = new_weather
		"-fieldstart":
			var effect := effect_name(msg.arg(0))
			if not effect in field_conditions:
				field_conditions.append(effect)
			field_turns[effect] = turn
		"-fieldend":
			var index := field_conditions.find(effect_name(msg.arg(0)))
			if index != -1:
				field_conditions.remove_at(index)
			field_turns.erase(effect_name(msg.arg(0)))
		"-sidestart":
			side(msg.arg(0).substr(0, 2)).add_condition(effect_name(msg.arg(1)), turn)
		"-sideend":
			side(msg.arg(0).substr(0, 2)).conditions.erase(effect_name(msg.arg(1)))
		"-item":
			get_pokemon(msg.arg(0)).item = msg.arg(1)
		"-enditem":
			get_pokemon(msg.arg(0)).item = ""
		"-ability":
			get_pokemon(msg.arg(0)).ability = msg.arg(1)
		"-terastallize":
			get_pokemon(msg.arg(0)).tera_type = msg.arg(1)
		"-start":
			get_pokemon(msg.arg(0)).volatiles[effect_name(msg.arg(1))] = turn
		"-end":
			get_pokemon(msg.arg(0)).volatiles.erase(effect_name(msg.arg(1)))
		"inactive":
			_apply_timer(msg.arg(0))
		"inactiveoff":
			timer_on = false
			timer_turn_seconds = -1
			timer_total_seconds = -1
		"win":
			ended = true
			awaiting_choice = false
			winner = msg.arg(0)
		"tie":
			ended = true
			awaiting_choice = false
	_reveal_from_kwargs(msg)


## "[from] item: Leftovers" / "[from] ability: Intimidate" reveal the holder's item or ability
## (the holder is "[of]" if given, else the message's Pokémon).
func _reveal_from_kwargs(msg: PSMessage) -> void:
	var source := str(msg.kwargs.get("from", ""))
	if not (source.begins_with("item: ") or source.begins_with("ability: ")):
		return
	var holder_ident := str(msg.kwargs.get("of", msg.arg(0)))
	if not holder_ident.contains(": "):
		return
	var holder := get_pokemon(holder_ident)
	if source.begins_with("item: "):
		holder.item = source.substr(6)
	else:
		holder.ability = source.substr(9)


## "Time left: 150 sec this turn | 240 sec total" (only sent to the player it concerns).
func _apply_timer(text: String) -> void:
	var regex := RegEx.create_from_string("Time left: (\\d+) sec this turn \\| (\\d+) sec total")
	var found := regex.search(text)
	if found != null:
		timer_on = true
		timer_turn_seconds = found.get_string(1).to_int()
		timer_total_seconds = found.get_string(2).to_int()
	elif text.contains("timer is ON") or text.contains("timer is now ON"):
		timer_on = true


## Turns left for a 5-turn effect that started in `start_turn` (estimate: 5 turns, items
## like Light Clay or Damp Rock extend it to 8 and are not detected).
func turns_left(start_turn: int, duration := 5) -> int:
	return maxi(duration - (turn - start_turn), 0)


## Applies a parsed |request| JSON. Our own side gets exact HP and move lists from it.
func apply_request(req: Dictionary) -> void:
	request = req
	awaiting_choice = not ended and not req.get("wait", false) \
		and (req.has("active") or req.has("forceSwitch") or req.get("teamPreview", false))
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
		mon.stats = entry.get("stats", {})
		mon.item = str(entry.get("item", mon.item))
		mon.ability = str(entry.get("ability", entry.get("baseAbility", mon.ability)))
		mon.tera_option = str(entry.get("teraType", ""))
		if not str(entry.get("terastallized", "")).is_empty():
			mon.tera_type = str(entry["terastallized"])


## Sets my_side from the player names while it is still unknown, i.e. before the first
## |request| (at battle start, and when (re)joining a battle in progress, where the server replays
## the whole log first). Spectators don't match any player and keep "".
func claim_side_by_name(username: String) -> void:
	if not my_side.is_empty() or username.is_empty():
		return
	var me := PSParser.to_id(username)
	for side_id: String in sides:
		var s: BattleSide = sides[side_id]
		if not s.player_name.is_empty() and PSParser.to_id(s.player_name) == me:
			my_side = side_id
			return


## "move: Stealth Rock" -> "Stealth Rock"
static func effect_name(effect: String) -> String:
	var colon := effect.find(": ")
	return effect if colon == -1 else effect.substr(colon + 2)
