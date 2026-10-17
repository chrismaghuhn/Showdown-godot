class_name StatCalc
extends RefCounted
## Stat formulas (Gen 3+). Used to show the possible range of an opponent's stat until it is
## revealed: 0-31 IV, 0-252 EV, any nature. Pure.

const STATS := ["hp", "atk", "def", "spa", "spd", "spe"]


static func stat(stat_id: String, base: int, level: int, iv: int, ev: int, nature := 1.0) -> int:
	var core := floori((2 * base + iv + floori(ev / 4.0)) * level / 100.0)
	if stat_id == "hp":
		return 1 if base == 1 else core + level + 10
	return floori((core + 5) * nature)


## [min, max] for a stat at a level across all IVs, EVs and natures.
static func stat_range(stat_id: String, base: int, level: int) -> Vector2i:
	var low_nature := 1.0 if stat_id == "hp" else 0.9
	var high_nature := 1.0 if stat_id == "hp" else 1.1
	return Vector2i(stat(stat_id, base, level, 0, 0, low_nature), stat(stat_id, base, level, 31, 252, high_nature))


## Stat stage multiplier for boosts -6..+6 (attack/defense/special/speed).
static func boost_multiplier(stage: int) -> float:
	var s := clampi(stage, -6, 6)
	return (2.0 + s) / 2.0 if s >= 0 else 2.0 / (2.0 - s)
