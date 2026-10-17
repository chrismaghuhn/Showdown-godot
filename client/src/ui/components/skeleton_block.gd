class_name SkeletonBlock
extends PanelContainer
## A flat block standing in for content while it loads (design: ".ms-skel"). Pulses its
## opacity 1 <-> 0.6 every 1.2 s; static with reduce motion.

const PULSE_SECONDS := 1.2


func _init(width := 0.0, height := 12.0) -> void:
	theme_type_variation = &"SkeletonBlock"
	custom_minimum_size = Vector2(width, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	if Themes.reduce_motion:
		return
	var tween := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 0.6, PULSE_SECONDS / 2.0)
	tween.tween_property(self, "modulate:a", 1.0, PULSE_SECONDS / 2.0)


## A line that takes `fraction` of the row's width (the design's "width: 40%").
static func line(fraction: float, height := 12.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var block := SkeletonBlock.new(0.0, height)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.size_flags_stretch_ratio = clampf(fraction, 0.01, 1.0)
	row.add_child(block)
	if fraction < 1.0:
		var rest := Control.new()
		rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rest.size_flags_stretch_ratio = 1.0 - fraction
		rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(rest)
	return row
