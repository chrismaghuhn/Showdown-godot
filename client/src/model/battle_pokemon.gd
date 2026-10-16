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
var moves := PackedStringArray()


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
