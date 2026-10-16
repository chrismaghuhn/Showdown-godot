extends "res://tests/test_case.gd"

const BUILTIN := ["midnight-dark", "classic-light", "high-contrast"]


func _builtin_definitions() -> Dictionary:
	var defs := {}
	for id: String in BUILTIN:
		defs[id] = ThemeTokens.parse_definition(id, FileAccess.get_file_as_string("res://assets/themes/%s.sdtheme.json" % id))
	return defs


func _with(extra_id: String, json: String) -> Dictionary:
	var defs := _builtin_definitions()
	defs[extra_id] = ThemeTokens.parse_definition(extra_id, json)
	return defs


func test_builtin_themes_load_without_warnings() -> void:
	var defs := _builtin_definitions()
	for id: String in BUILTIN:
		assert_true(defs[id]["ok"], id + " parses")
		var tokens := ThemeTokens.resolve(id, defs, "midnight-dark")
		assert_true(tokens != null, id + " resolves")
		assert_eq(tokens.warnings, PackedStringArray(), id + " warnings (incl. contrast)")


func test_light_extends_dark() -> void:
	var defs := _builtin_definitions()
	var light := ThemeTokens.resolve("classic-light", defs, "midnight-dark")
	var dark := ThemeTokens.resolve("midnight-dark", defs, "midnight-dark")
	assert_eq(light.name, "Classic Light", "name")
	assert_eq(light.color("color.surface.panel"), Color.html("#FFFFFF"), "overridden token")
	assert_eq(light.color("color.type.fire.bg"), dark.color("color.type.fire.bg"), "inherited token")
	assert_eq(light.px("space.md"), 12, "inherited foundation")
	assert_eq(ThemeTokens.resolve("high-contrast", defs, "midnight-dark").px("border.width.default"), 2, "HC border width")


func test_community_theme_overrides_only_valid_tokens() -> void:
	var defs := _with("sandstorm", JSON.stringify({"format": 1, "name": "Sandstorm", "extends": "midnight-dark", "tokens": {
		"color.surface.app": "#15120E",
		"color.text.primary": "not a color",
		"color.does.not.exist": "#FFFFFF",
		"space.md": "12px",
		"font.size.md": 500,
		"font.family.ui": "Comic Sans MS",
	}}))
	var tokens := ThemeTokens.resolve("sandstorm", defs, "midnight-dark")
	assert_eq(tokens.color("color.surface.app"), Color.html("#15120E"), "valid override")
	assert_eq(tokens.color("color.text.primary"), Color.html("#F2F2F3"), "invalid color falls back")
	assert_eq(tokens.px("space.md"), 12, "wrong type falls back")
	assert_eq(tokens.px("font.size.md"), 13, "out of range falls back")
	assert_eq(tokens.text("font.family.ui"), "Comic Sans MS", "font family string allowed")
	assert_true(tokens.values.has("color.does.not.exist") == false, "unknown key not added")
	var joined := "\n".join(tokens.warnings)
	assert_true(joined.contains("unknown token 'color.does.not.exist'"), "warns unknown key")
	assert_true(joined.contains("invalid value for 'color.text.primary'"), "warns invalid color")
	assert_true(joined.contains("invalid value for 'font.size.md'"), "warns out of range")


func test_extends_cycle_and_missing_parent() -> void:
	var defs := _builtin_definitions()
	defs["a"] = ThemeTokens.parse_definition("a", "{\"format\":1,\"extends\":\"b\",\"tokens\":{}}")
	defs["b"] = ThemeTokens.parse_definition("b", "{\"format\":1,\"extends\":\"a\",\"tokens\":{}}")
	defs["orphan"] = ThemeTokens.parse_definition("orphan", "{\"format\":1,\"extends\":\"nope\",\"tokens\":{}}")
	var cyclic := ThemeTokens.resolve("a", defs, "midnight-dark")
	assert_true(cyclic != null, "cycle still resolves to base")
	assert_true("\n".join(cyclic.warnings).contains("cycle"), "cycle warned")
	var orphan := ThemeTokens.resolve("orphan", defs, "midnight-dark")
	assert_true("\n".join(orphan.warnings).contains("'nope' not found"), "missing parent warned")
	assert_true(ThemeTokens.resolve("unknown", defs, "midnight-dark") == null, "unknown theme is null")


func test_parse_rejects_bad_files() -> void:
	assert_true(not ThemeTokens.parse_definition("x", "not json")["ok"], "invalid json")
	assert_true(not ThemeTokens.parse_definition("x", "{\"format\":2,\"tokens\":{}}")["ok"], "wrong format")
	assert_true(not ThemeTokens.parse_definition("x", "{\"format\":1,\"tokens\":[]}")["ok"], "tokens not an object")
	var huge := "{\"format\":1,\"tokens\":{},\"pad\":\"%s\"}" % "x".repeat(ThemeTokens.MAX_FILE_BYTES)
	assert_true(not ThemeTokens.parse_definition("x", huge)["ok"], "too large")


func test_contrast_ratio_and_check() -> void:
	assert_eq(snappedf(ThemeTokens.contrast_ratio(Color.BLACK, Color.WHITE), 0.01), 21.0, "black on white")
	assert_eq(ThemeTokens.contrast_ratio(Color.RED, Color.RED), 1.0, "same color")
	var defs := _with("low", JSON.stringify({"format": 1, "tokens": {"color.text.muted": "#2A2A2D"}}))
	var low := ThemeTokens.resolve("low", defs, "midnight-dark")
	assert_true("\n".join(low.warnings).contains("low contrast") and "\n".join(low.warnings).contains("color.text.muted"), "contrast warning")
