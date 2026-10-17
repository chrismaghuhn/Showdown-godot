class_name AppLogo
extends TextureRect
## The app mark (design: connecting card): a rounded accent square with a slash and two dots,
## drawn from the theme's tokens so it follows the theme.

const SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 20 20'>" \
	+ "<rect x='1' y='1' width='18' height='18' rx='5' fill='%s'/>" \
	+ "<path d='M6 14.5L14 5.5' stroke='%s' stroke-width='2' stroke-linecap='round' fill='none'/>" \
	+ "<circle cx='6.5' cy='7' r='1.6' fill='%s'/><circle cx='13.5' cy='13' r='1.6' fill='%s'/></svg>"

var logo_size := 40


func _init(size_px := 40) -> void:
	logo_size = size_px
	custom_minimum_size = Vector2(size_px, size_px)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_THEME_CHANGED:
		_render()


func _render() -> void:
	var themes := get_node_or_null("/root/Themes")
	if themes == null or themes.tokens == null:
		return
	var bg := "#" + (themes.color("color.accent.default") as Color).to_html(false)
	var fg := "#" + (themes.color("color.text.on-accent") as Color).to_html(false)
	var image := Image.new()
	# Rendered at 2x the shown size so it stays sharp with UI scaling.
	if image.load_svg_from_string(SVG % [bg, fg, fg, fg], logo_size * 2 / 20.0) == OK:
		texture = ImageTexture.create_from_image(image)
