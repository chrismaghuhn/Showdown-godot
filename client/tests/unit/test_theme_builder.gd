extends "res://tests/test_case.gd"


func _tokens(id: String) -> ThemeTokens:
	var defs := {}
	for theme_id in ["midnight-dark", "classic-light", "high-contrast"]:
		defs[theme_id] = ThemeTokens.parse_definition(theme_id, FileAccess.get_file_as_string("res://assets/themes/%s.sdtheme.json" % theme_id))
	return ThemeTokens.resolve(id, defs, "midnight-dark")


func _bg(theme: Theme, item: String, type: String) -> Color:
	return (theme.get_stylebox(item, type) as StyleBoxFlat).bg_color


func test_fonts_and_base_size() -> void:
	var theme := ThemeBuilder.build(_tokens("midnight-dark"))
	assert_eq(theme.default_font_size, 13, "base font size")
	assert_true(theme.default_font is FontFile, "bundled font")
	assert_eq((theme.default_font as FontFile).get_font_name(), "Atkinson Hyperlegible Next", "font family")
	assert_true(ThemeBuilder.font("Some System Font", 400) is SystemFont, "unknown family -> system font")


func test_buttons_follow_tokens() -> void:
	var t := _tokens("midnight-dark")
	var theme := ThemeBuilder.build(t)
	assert_eq(_bg(theme, "normal", "Button"), t.color("color.surface.raised"), "secondary bg")
	assert_eq(_bg(theme, "normal", "PrimaryButton"), t.color("color.accent.default"), "primary bg")
	assert_eq(theme.get_color("font_color", "PrimaryButton"), t.color("color.text.on-accent"), "primary text")
	assert_eq(theme.get_type_variation_base("PrimaryButton"), &"Button", "variation base")
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_eq(focus.border_color, t.color("color.focus.ring"), "focus ring color")
	assert_true(not focus.draw_center, "focus ring is an outline")


func test_move_button_type_tint() -> void:
	var t := _tokens("classic-light")
	var theme := ThemeBuilder.build(t)
	var expected := t.color("color.surface.raised").lerp(t.color("color.type.ground.bg"), t.num("mix.type.tint"))
	assert_eq(_bg(theme, "normal", "MoveButton_ground"), expected, "ground tint")
	assert_eq(theme.get_color("font_color", "TypeBadge_fire"), t.color("color.type.fire.fg"), "type badge ink")
	assert_eq(_bg(theme, "normal", "StatusBadge_tox"), t.color("color.status.tox.bg"), "status badge")


func test_high_contrast_borders_and_no_shadows() -> void:
	var theme := ThemeBuilder.build(_tokens("high-contrast"))
	var panel := theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_eq(panel.border_width_left, 2, "2px borders")
	assert_eq((theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat).shadow_size, 0, "no shadow")
	assert_eq(theme.get_constant("outline_width", "HPBar"), 2, "HP bar outline")
