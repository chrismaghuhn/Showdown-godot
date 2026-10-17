class_name BattlePokemon
extends RefCounted
## What the client knows about one Pokémon in a battle.

var name := ""
var species := ""
var level := 100
var gender := ""
var shiny := false
var hp := 100
var max_hp := 100
var status := ""
var fainted := false
var active := false
var boosts := {}
## Own Pokémon: move ids from |request|.
var moves := PackedStringArray()
## Moves seen in battle (names), mainly for the opponent.
var revealed_moves := PackedStringArray()
## Item and ability: from |request| (ids) for own Pokémon, from protocol (names) once revealed.
var item := ""
var ability := ""
## Its own ability while it has a copied one (Trace, Receiver); "" otherwise.
var base_ability := ""
## The item it lost last (eaten, used up, knocked off); its effect doesn't reveal it again.
var prev_item := ""
## Tera type once terastallized ("" = not terastallized).
var tera_type := ""
## Own Pokémon only: the type it would terastallize into.
var tera_option := ""
## Volatile effects like "Taunt", "Substitute" -> turn they started.
var volatiles := {}
## Own Pokémon only: exact stats from |request| (atk, def, spa, spd, spe).
var stats := {}
## HP and status before its last switch-in, restored when that turns out to be an Illusion.
var before_switch := {}


func _init(nickname := "") -> void:
	name = nickname


## Applies a DETAILS string, e.g. "Pikachu, L50, F, shiny".
func apply_details(details: String) -> void:
	if details.is_empty():
		return
	var parts := details.split(", ")
	species = parts[0]
	level = 100
	for p in parts.slice(1):
		if p.begins_with("L") and p.substr(1).is_valid_int():
			level = p.substr(1).to_int()
		elif p == "M" or p == "F":
			gender = p
		elif p == "shiny":
			shiny = true


## Applies an HP STATUS string, e.g. "45/100 par", "187/250" or "0 fnt".
func apply_condition(condition: String) -> void:
	if condition.is_empty():
		return
	var parts := condition.split(" ")
	var hp_parts := parts[0].split("/")
	hp = hp_parts[0].to_int()
	if hp_parts.size() > 1:
		max_hp = hp_parts[1].to_int()
	status = parts[1] if parts.size() > 1 else ""
	fainted = status == "fnt" or hp == 0
	if status == "fnt":
		status = ""


func hp_percent() -> float:
	return 0.0 if max_hp <= 0 else 100.0 * hp / max_hp


func boost(stat: String, amount: int) -> void:
	boosts[stat] = clampi(int(boosts.get(stat, 0)) + amount, -6, 6)


## Sets a stat stage; 0 removes it.
func set_boost(stat: String, stage: int) -> void:
	if stage == 0:
		boosts.erase(stat)
	else:
		boosts[stat] = stage


## Removes the negative (direction -1) or positive (direction 1) stages.
func clear_boosts(direction: int) -> void:
	for stat: String in boosts.keys():
		if signi(int(boosts[stat])) == direction:
			boosts.erase(stat)


## |replace|: this Pokémon was in battle disguised as `disguise` (Illusion). It takes over what
## happened in the slot, and what was revealed meanwhile; for our own side (`own`) HP, status and
## reveals are exact from |request| already. The disguise goes back to how it was before it
## "switched in".
func take_over_from(disguise: BattlePokemon, own := false) -> void:
	var before := disguise.before_switch
	if not own:
		hp = disguise.hp
		max_hp = disguise.max_hp
		status = disguise.status
		fainted = disguise.fainted
		var seen := int(before.get("moves", disguise.revealed_moves.size()))
		for move_name in disguise.revealed_moves.slice(seen):
			reveal_move(move_name)
		disguise.revealed_moves = disguise.revealed_moves.slice(0, seen)
		if disguise.item != str(before.get("item", disguise.item)):
			item = disguise.item
			disguise.item = str(before["item"])
		if disguise.ability != str(before.get("ability", disguise.ability)):
			ability = disguise.ability
			disguise.ability = str(before["ability"])
	boosts = disguise.boosts.duplicate()
	volatiles = disguise.volatiles.duplicate()
	if not disguise.tera_type.is_empty():
		tera_type = disguise.tera_type
		disguise.tera_type = ""
	disguise.max_hp = int(before.get("max_hp", disguise.max_hp))
	disguise.hp = int(before.get("hp", disguise.max_hp))
	disguise.status = str(before.get("status", ""))
	disguise.fainted = bool(before.get("fainted", false))


func reveal_move(move_name: String) -> void:
	if not move_name.is_empty() and not move_name in revealed_moves:
		revealed_moves.append(move_name)
