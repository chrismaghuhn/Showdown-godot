class_name BoostChip
extends Label
## Stat stage chip, e.g. "+2 SpA" or "−1 Def".

const STAT_LABELS := {"atk": "Atk", "def": "Def", "spa": "SpA", "spd": "SpD", "spe": "Spe",
	"accuracy": "Acc", "evasion": "Eva"}


func _init(stat := "atk", amount := 1) -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_boost(stat, amount)


func set_boost(stat: String, amount: int) -> void:
	var prefix := "+" if amount > 0 else "−"
	text = "%s%d %s" % [prefix, absi(amount), STAT_LABELS.get(stat, stat)]
	theme_type_variation = &"BoostUpChip" if amount > 0 else &"BoostDownChip"
