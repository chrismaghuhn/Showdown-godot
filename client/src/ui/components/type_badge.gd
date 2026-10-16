class_name TypeBadge
extends Label
## Type badge ("GROUND") in the type's colors. Always shows its text, never color alone.

@export var type_name := "Normal":
	set(value):
		type_name = value
		text = value
		theme_type_variation = StringName("TypeBadge_" + PSParser.to_id(value))


func _init(initial_type := "Normal") -> void:
	uppercase = true
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_name = initial_type
