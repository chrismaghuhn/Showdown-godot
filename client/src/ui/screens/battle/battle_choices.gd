class_name BattleChoices
extends RefCounted
## Pure rules behind the battle screen's choice panel (switch slots, timer button), kept
## out of BattleScreen so they can be tested without building the screen.


## Whether the switch slot of `mon` (own Pokémon, from the |request| team) may be picked,
## not counting whether it is our turn. Only "trapped" blocks switching: "maybeTrapped" means
## the foe might have an unrevealed trapping ability, and the server rejects the switch if so.
## After Revival Blessing (a side.pokemon entry has "reviving") the pick is a fainted Pokémon.
## Singles only (like the screen): the active Pokémon is excluded, doubles slots aren't handled.
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


## The request asks which fainted Pokémon Revival Blessing brings back. Singles only: in doubles
## the "reviving" entry would also say which slot asks.
static func is_reviving(request: Dictionary) -> bool:
	for entry: Variant in request.get("side", {}).get("pokemon", []):
		if entry is Dictionary and entry.get("reviving", false):
			return true
	return false


## One second of the local timer countdown; -1 (unknown, e.g. when spectating) stays -1.
static func count_down(seconds: int) -> int:
	return seconds if seconds < 0 else maxi(seconds - 1, 0)


## What the local countdown last synced to: it resyncs whenever this changes, i.e. on every
## timer update of the battle (also one that repeats the values) and for another battle.
static func timer_sync_key(battle: BattleState) -> Array:
	return [battle, battle.timer_updates]


static func needs_timer_resync(last_key: Array, battle: BattleState) -> bool:
	return last_key != timer_sync_key(battle)


## Text and tooltip of the timer button: the countdown while our seconds are known, otherwise
## "Timer" (also when it runs but we don't know the seconds, e.g. when spectating).
static func timer_button(timer_on: bool, turn_seconds: int, total_seconds: int) -> PackedStringArray:
	if timer_on and turn_seconds >= 0:
		return PackedStringArray(["%s / %s" % [clock(turn_seconds), clock(total_seconds)],
			_t("Your time this turn / in total. Click to turn the timer off.")])
	if timer_on:
		return PackedStringArray([_t("Timer"), _t("The battle timer is on. Click to turn it off.")])
	return PackedStringArray([_t("Timer"), _t("Start the battle timer")])


## 125 -> "2:05"
static func clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func _t(text: String) -> String:
	return TranslationServer.translate(text)
