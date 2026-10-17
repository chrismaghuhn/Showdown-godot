class_name StatusDot
extends Control
## A small round status dot (design: 7–8px): filled ("your move", online) or a ring ("waiting").
## An optional outer ring in another color separates it from what it sits on (the bell's dot).

@export var color_token := "color.accent.text":
	set(value):
		color_token = value
		queue_redraw()
@export var hollow := false:
	set(value):
		hollow = value
		queue_redraw()
@export var diameter := 8.0:
	set(value):
		diameter = value
		custom_minimum_size = Vector2(value, value)
		queue_redraw()
## Outer ring color token ("" = none), e.g. the header background around the bell's dot.
var ring_token := ""


func _init(token := "color.accent.text", is_hollow := false, size_px := 8.0) -> void:
	color_token = token
	hollow = is_hollow
	diameter = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var themes := get_node_or_null("/root/Themes")
	if themes == null or themes.tokens == null:
		return
	var center := size / 2.0
	var radius := diameter / 2.0
	if not ring_token.is_empty():
		draw_circle(center, radius + 2.0, themes.color(ring_token), true, -1.0, true)
	var color: Color = themes.color(color_token)
	if hollow:
		draw_circle(center, radius - 0.75, color, false, 1.5, true)
	else:
		draw_circle(center, radius, color, true, -1.0, true)
