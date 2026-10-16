class_name IconView
extends TextureRect
## A 16px icon tinted with a theme color token. Inside buttons use Button.icon instead
## (the theme's icon colors tint it). Set tooltip_text when there is no visible label.

@export var icon_name := "":
	set(value):
		icon_name = value
		texture = Icons.get_icon(value) if not value.is_empty() else null

@export var color_token := "color.text.secondary":
	set(value):
		color_token = value
		_apply_color()


func _init(initial_icon := "", initial_token := "color.text.secondary") -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = Vector2(Icons.SIZE, Icons.SIZE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_name = initial_icon
	color_token = initial_token


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_THEME_CHANGED:
		_apply_color()


func _apply_color() -> void:
	# The color is resolved once the view is in the tree (Themes is an autoload);
	# until then the texture keeps its white.
	if not is_inside_tree():
		return
	var themes := get_node_or_null("/root/Themes")
	if themes != null and themes.tokens != null:
		self_modulate = themes.color(color_token)
