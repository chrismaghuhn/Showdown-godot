class_name HPBar
extends Control
## HP bar with the design's thresholds: high > 50 %, mid 21-50 %, low <= 20 %.
## Colors come from the theme type "HPBar". Always print the number next to the bar.

@export_range(0.0, 100.0) var percent := 100.0:
	set(value):
		percent = clampf(value, 0.0, 100.0)
		queue_redraw()


func _init(initial_percent := 100.0) -> void:
	percent = initial_percent
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		update_minimum_size()
		queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(48, get_theme_constant("height", "HPBar"))


func fill_color() -> Color:
	var level := "high" if percent > 50.0 else ("mid" if percent > 20.0 else "low")
	return get_theme_color(level, "HPBar")


func _draw() -> void:
	var height := size.y
	var radius := int(height / 2.0)
	var track := StyleBoxFlat.new()
	track.bg_color = get_theme_color("track", "HPBar")
	track.set_corner_radius_all(radius)
	track.border_color = get_theme_color("outline", "HPBar")
	track.set_border_width_all(get_theme_constant("outline_width", "HPBar"))
	track.anti_aliasing = true
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	if percent <= 0.0:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color()
	fill.set_corner_radius_all(radius)
	fill.anti_aliasing = true
	draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(maxf(height, size.x * percent / 100.0), height)))
