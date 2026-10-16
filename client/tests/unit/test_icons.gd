extends "res://tests/test_case.gd"


func test_all_icons_load_at_double_resolution() -> void:
	var names := Icons.names()
	assert_eq(names.size(), 37, "icon count")
	for icon_name in names:
		var texture := Icons.get_icon(icon_name)
		assert_true(texture != null, icon_name + " loads")
		if texture != null:
			assert_eq(texture.get_size(), Vector2(Icons.SIZE * 2, Icons.SIZE * 2), icon_name + " imported at 2x")


func test_field_condition_icons_exist() -> void:
	var names := Icons.names()
	for icon_name in ["weather-rain", "weather-sun", "weather-sandstorm", "weather-snow", "terrain-grassy",
			"terrain-electric", "terrain-psychic", "terrain-misty", "hazard-stealth-rock", "hazard-spikes",
			"hazard-toxic-spikes", "hazard-sticky-web", "screen-reflect", "screen-light-screen", "screen-aurora-veil"]:
		assert_true(icon_name in names, icon_name)


func test_icon_view_shows_texture() -> void:
	var view := IconView.new("ui-settings")
	assert_true(view.texture != null, "texture set")
	assert_eq(view.custom_minimum_size, Vector2(16, 16), "displayed at 16px")
	view.free()
