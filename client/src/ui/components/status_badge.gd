class_name StatusBadge
extends Label
## Status badge ("PAR") for brn, par, slp, frz, psn, tox; always with its 3-letter label.

@export var status := "par":
	set(value):
		status = value.to_lower()
		text = status
		theme_type_variation = StringName("StatusBadge_" + status)


func _init(initial_status := "par") -> void:
	uppercase = true
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	status = initial_status
