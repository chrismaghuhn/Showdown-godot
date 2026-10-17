class_name BattleState
extends RefCounted
## The client's view of one battle, built purely from protocol messages.
##
## No network, UI or autoload dependencies: feed it PSMessages (live, replay or test)
## and read the state. The server does all game mechanics; this only mirrors them.

## Weathers without a duration (they end when the Pokémon that set them leaves).
const ENDLESS_WEATHERS := ["DesolateLand", "PrimordialSea", "DeltaStream"]

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
## Turn whose end-of-turn upkeep (|upkeep|) already ran.
var _upkeep_turn := -1
## The Fling being used: its target and the target's item before it ({} = none).
var _fling := {}
## Battle timer (from |inactive|): seconds left this turn and in total; -1 = unknown.
var timer_on := false
var timer_turn_seconds := -1
var timer_total_seconds := -1
## Counts the timer updates ("Time left" and |inactiveoff|), so a local countdown can resync on
## each one even when the server repeats the same values.
var timer_updates := 0
## Latest |request| payload (what we may choose this turn).
var request := {}
var ended := false
## Rejoined after a reconnect (the log was replayed from the start).
var restored := false
var winner := ""

## Abilities and items whose "[of]" is the other Pokémon involved (the attacker or the victim),
## not the holder: the message's own Pokémon holds them.
const HELD_BY_TARGET := ["Water Absorb", "Volt Absorb", "Dry Skin", "Earth Eater", "Magician", "Pickpocket",
	"Shell Bell"]
## Every stat with a stage.
const BOOST_STATS := ["atk", "def", "spa", "spd", "spe", "accuracy", "evasion"]
## "-ability" sources that copy the "[of]" Pokémon's ability.
const COPIED_ABILITY_SOURCES := ["ability: Trace", "ability: Receiver", "ability: Power of Alchemy"]


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
			# Moves called by another move or ability (Metronome, Magic Bounce, Dancer …) aren't
			# the user's own; a locked-in repeat (Outrage), Sleep Talk's pick and Pursuit on a
			# switch ("[from] move: Pursuit") are.
			var from := str(msg.kwargs.get("from", ""))
			if from.is_empty() or from in ["lockedmove", "move: Sleep Talk", "move: " + msg.arg(1)]:
				get_pokemon(msg.arg(0)).reveal_move(msg.arg(1))
			if msg.arg(1) == "Fling" and msg.arg(2).contains(": "):
				_fling = {"target": msg.arg(2), "item": get_pokemon(msg.arg(2)).item}
		"switch", "drag":
			var ref := parse_ident(msg.arg(0))
			var s := side(ref["side"])
			var mon := s.get_or_add(ref["name"])
			mon.apply_details(msg.arg(1))
			mon.before_switch = {"hp": mon.hp, "max_hp": mon.max_hp, "status": mon.status, "fainted": mon.fainted,
				"moves": mon.revealed_moves.size(), "item": mon.item, "ability": mon.ability}
			mon.apply_condition(msg.arg(2))
			s.set_active(ref["slot"], mon)
		"replace":
			# Illusion ended: the Pokémon in the slot was this one all along (no HP is sent).
			var ref := parse_ident(msg.arg(0))
			var s := side(ref["side"])
			var mon := s.get_or_add(ref["name"])
			var disguise := s.active_pokemon(ref["slot"])
			mon.apply_details(msg.arg(1))
			if disguise != null and disguise != mon:
				# Our own HP and moves come exactly from |request|, not from the disguise.
				mon.take_over_from(disguise, ref["side"] == my_side)
			mon.apply_condition(msg.arg(2))
			s.set_active(ref["slot"], mon)
		"detailschange":
			get_pokemon(msg.arg(0)).apply_details(msg.arg(1))
		"-formechange":
			# Only the species changes; level, gender and shiny stay.
			get_pokemon(msg.arg(0)).species = msg.arg(1).get_slice(", ", 0)
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
		"-clearboost":
			get_pokemon(msg.arg(0)).boosts.clear()
		"-clearnegativeboost":
			get_pokemon(msg.arg(0)).clear_boosts(-1)
		"-clearpositiveboost":
			get_pokemon(msg.arg(0)).clear_boosts(1)
		"-copyboost":
			# Psych Up, Costar: the first Pokémon copies the second one's stages.
			get_pokemon(msg.arg(0)).boosts = get_pokemon(msg.arg(1)).boosts.duplicate()
		"-swapboost":
			# Heart Swap swaps every stat; Guard / Power Swap list theirs ("def, spd").
			var a := get_pokemon(msg.arg(0))
			var other := get_pokemon(msg.arg(1))
			var stats := PackedStringArray(BOOST_STATS) if msg.arg(2).is_empty() else msg.arg(2).split(", ", false)
			for stat in stats:
				var mine: int = a.boosts.get(stat, 0)
				var theirs: int = other.boosts.get(stat, 0)
				a.set_boost(stat, theirs)
				other.set_boost(stat, mine)
		"-invertboost":
			var mon := get_pokemon(msg.arg(0))
			for stat: String in mon.boosts.keys():
				mon.set_boost(stat, -int(mon.boosts[stat]))
		"-clearallboost":
			for s: BattleSide in sides.values():
				for mon: BattlePokemon in s.pokemon.values():
					mon.boosts.clear()
		"-weather":
			var new_weather := "" if msg.arg(0) == "none" else msg.arg(0)
			if new_weather != weather and not msg.kwargs.has("upkeep"):
				weather_turn = _effect_start_turn()
			weather = new_weather
		"-fieldstart":
			var effect := effect_name(msg.arg(0))
			if not effect in field_conditions:
				field_conditions.append(effect)
			field_turns[effect] = _effect_start_turn()
		"-fieldend":
			var index := field_conditions.find(effect_name(msg.arg(0)))
			if index != -1:
				field_conditions.remove_at(index)
			field_turns.erase(effect_name(msg.arg(0)))
		"upkeep":
			_upkeep_turn = turn
		"-sidestart":
			side(msg.arg(0).substr(0, 2)).add_condition(effect_name(msg.arg(1)), _effect_start_turn())
		"-sideend":
			side(msg.arg(0).substr(0, 2)).conditions.erase(effect_name(msg.arg(1)))
		"-item":
			var mon := get_pokemon(msg.arg(0))
			mon.item = msg.arg(1)
			mon.prev_item = ""
			# Magician: the victim ("[of]") loses the item it stole.
			if str(msg.kwargs.get("from", "")) == "ability: Magician" and str(msg.kwargs.get("of", "")).contains(": "):
				get_pokemon(msg.kwargs["of"]).item = ""
		"-enditem":
			var mon := get_pokemon(msg.arg(0))
			mon.item = ""
			mon.prev_item = msg.arg(1)
			# Bug Bite / Pluck: the eater gets the berry's effect, but never held it.
			if str(msg.kwargs.get("from", "")) == "stealeat" and str(msg.kwargs.get("of", "")).contains(": "):
				get_pokemon(msg.kwargs["of"]).prev_item = msg.arg(1)
			# Fling: the target used the flung item before this message; it never held it.
			if str(msg.kwargs.get("from", "")) == "move: Fling" and not _fling.is_empty():
				var target := get_pokemon(_fling["target"])
				if target.item == msg.arg(1) and _fling["item"] != msg.arg(1):
					target.item = _fling["item"]
				_fling = {}
		"-ability":
			var mon := get_pokemon(msg.arg(0))
			var from := str(msg.kwargs.get("from", ""))
			# Trace, Receiver, Power of Alchemy: the copied ability is also "[of]"'s own, and
			# the copier gets its own ability back when it switches out.
			if from in COPIED_ABILITY_SOURCES:
				if mon.base_ability.is_empty():
					mon.base_ability = msg.arg(2) if not msg.arg(2).is_empty() else effect_name(from)
				if str(msg.kwargs.get("of", "")).contains(": "):
					get_pokemon(msg.kwargs["of"]).ability = msg.arg(1)
			mon.ability = msg.arg(1)
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
			timer_updates += 1
		"win":
			ended = true
			winner = msg.arg(0)
		"tie":
			ended = true
	_reveal_from_kwargs(msg)


## "[from] item: Leftovers" / "[from] ability: Intimidate" reveal the holder's item or ability
## (the holder is "[of]" if given, else the message's Pokémon).
func _reveal_from_kwargs(msg: PSMessage) -> void:
	var source := str(msg.kwargs.get("from", ""))
	if not (source.begins_with("item: ") or source.begins_with("ability: ")):
		return
	# -ability names the new ability itself; Pickpocket's -enditem names the thief's victim.
	if source.begins_with("ability: ") and (msg.type == "-ability" or msg.type == "-enditem"):
		return
	var holder_ident := str(msg.kwargs.get("of", msg.arg(0)))
	if effect_name(source) in HELD_BY_TARGET:
		holder_ident = msg.arg(0)
	if not holder_ident.contains(": "):
		return
	var holder := get_pokemon(holder_ident)
	if source.begins_with("item: "):
		# A used-up item announces itself first (-enditem), then its effect.
		if source.substr(6) != holder.prev_item:
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
		timer_updates += 1
	elif text.contains("timer is ON") or text.contains("timer is now ON"):
		timer_on = true


## Turns left for a 5-turn effect that started in `start_turn` (estimate: 5 turns, items
## like Light Clay or Damp Rock extend it to 8 and are not detected).
func turns_left(start_turn: int, duration := 5) -> int:
	return clampi(duration - (turn - start_turn), 0, duration)


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


## Turns left for the current weather; -1 for weathers that last until their setter leaves.
func weather_turns_left() -> int:
	return -1 if weather in ENDLESS_WEATHERS else turns_left(weather_turn)


## The turn a new effect counts from: its first countdown is this turn's upkeep, or the next
## one's if it starts before turn 1 (lead abilities) or after this turn's upkeep (replacements).
func _effect_start_turn() -> int:
	return turn + 1 if turn == 0 or _upkeep_turn == turn else turn


## "move: Stealth Rock" -> "Stealth Rock"
static func effect_name(effect: String) -> String:
	var colon := effect.find(": ")
	return effect if colon == -1 else effect.substr(colon + 2)
