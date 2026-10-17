extends "res://tests/test_case.gd"


func test_all_icons_from_the_manifest_load_at_double_resolution() -> void:
	var names := Icons.names()
	assert_eq(names.size(), 95, "icon count (icons.json)")
	for icon_name in names:
		var texture := Icons.get_icon(icon_name)
		assert_true(texture != null, icon_name + " loads")
		if texture != null:
			assert_eq(texture.get_size(), Vector2(Icons.SIZE * 2, Icons.SIZE * 2), icon_name + " imported at 2x")


func test_manifest_labels_and_groups() -> void:
	assert_eq(Icons.label("ui-close"), "Close · KO", "label")
	assert_eq(Icons.group("weather-rain"), "Field · Weather", "group")
	assert_eq(Icons.label("not-an-icon"), "not-an-icon", "unknown label falls back to the name")
	assert_eq(Icons.groups().size(), 10, "groups")
	assert_eq(Icons.groups()[0], "Navigation", "design order")


func test_field_condition_icons_exist() -> void:
	var names := Icons.names()
	for icon_name: String in FieldConditions.CONDITION_ICONS.values():
		assert_true(icon_name in names, icon_name)
	for weather: Array in FieldConditions.WEATHER.values():
		assert_true(weather[1] in names, weather[1])


func test_icon_view_shows_texture() -> void:
	var view := IconView.new("ui-settings")
	assert_true(view.texture != null, "texture set")
	assert_eq(view.custom_minimum_size, Vector2(16, 16), "displayed at 16px")
	view.free()
