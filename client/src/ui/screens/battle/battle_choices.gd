class_name BattleChoices
extends RefCounted
## Pure rules behind the battle screen's choice panel (switch slots), kept
## out of BattleScreen so they can be tested without building the screen.


## Whether the switch slot of `mon` (own Pokémon, from the |request| team) may be picked,
## not counting whether it is our turn. Only "trapped" blocks switching: "maybeTrapped" means
## the foe might have an unrevealed trapping ability, and the server rejects the switch if so.
## After Revival Blessing (a side.pokemon entry has "reviving") the pick is a fainted Pokémon.
static func can_switch_to(request: Dictionary, mon: BattlePokemon) -> bool:
	if mon == null or mon.active:
		return false
	if is_reviving(request):
		return mon.fainted
	if mon.fainted:
		return false
	var active: Array = request.get("active", [])
	var trapped: bool = not active.is_empty() and active[0].get("trapped", false)
	return not trapped or not (request.get("forceSwitch", []) as Array).is_empty()


## The request asks which fainted Pokémon Revival Blessing brings back.
static func is_reviving(request: Dictionary) -> bool:
	for entry: Variant in request.get("side", {}).get("pokemon", []):
		if entry is Dictionary and entry.get("reviving", false):
			return true
	return false

