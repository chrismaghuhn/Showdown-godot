class_name Spinner
extends IconView
## The "ui-loading" icon turning once per second. Stands still with reduce motion.

const TURN_SECONDS := 1.0


func _init(initial_token := "color.text.secondary") -> void:
	super._init("ui-loading", initial_token)


func _process(delta: float) -> void:
	pivot_offset = size / 2.0
	if Themes.reduce_motion or not is_visible_in_tree():
		rotation = 0.0
		return
	rotation = fmod(rotation + TAU * delta / TURN_SECONDS, TAU)
