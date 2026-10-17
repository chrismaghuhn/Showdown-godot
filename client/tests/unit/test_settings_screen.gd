extends "res://tests/test_case.gd"
## Settings screen and theme gallery (#52): the UI scale slider applies from the keyboard and
## follows changes made elsewhere, cancelling the sound file dialog restores the dropdown, and
## new community themes show up without a restart. Restores the scale, theme and settings.

const SettingsScene := preload("res://src/ui/screens/settings/settings_screen.tscn")
const GalleryScene := preload("res://src/ui/screens/theme_gallery/theme_gallery.tscn")
const TEST_THEME := "zz-test-settings-screen"


func test_settings_scale_applies_from_keyboard() -> void:
	var saved := _save_scale()
	var screen := _open(SettingsScene)
	screen.show_page("appearance")
	var slider: HSlider = _live(screen._page_holder, "HSlider")[0]
	var target := 110.0 if not is_equal_approx(Themes.ui_scale, 1.1) else 120.0
	# Arrow keys and clicks call set_value: value_changed, no drag_ended.
	slider.value = target
	_assert_near(Themes.ui_scale, target / 100.0, "applied")
	_assert_near(AppConfig.get_setting("appearance", "ui_scale", -1.0), target / 100.0, "saved")
	assert_true(not slider.scrollable, "the mouse wheel scrolls the page, not the scale")
	screen.free()
	_restore_scale(saved)


func test_settings_slider_follows_scale_changes() -> void:
	var saved := _save_scale()
	var screen := _open(SettingsScene)
	screen.show_page("appearance")
	var slider: HSlider = _live(screen._page_holder, "HSlider")[0]
	var target := 0.9 if not is_equal_approx(Themes.ui_scale, 0.9) else 0.8
	Themes.set_ui_scale(target)
	assert_eq(slider.value, target * 100.0, "slider follows the scale set in the gallery")
	screen.free()
	_restore_scale(saved)


func test_gallery_scale_applies_and_follows() -> void:
	var saved := _save_scale()
	var gallery := _open(GalleryScene)
	var slider: HSlider = _live(gallery, "HSlider")[0]
	var target := 125.0 if not is_equal_approx(Themes.ui_scale, 1.25) else 130.0
	slider.value = target
	_assert_near(Themes.ui_scale, target / 100.0, "applied")
	assert_true(not slider.scrollable, "not scrollable")
	Themes.set_ui_scale(0.85)
	assert_eq(slider.value, 85.0, "follows the settings slider")
	gallery.free()
	_restore_scale(saved)


func test_cancelling_custom_sound_restores_the_choice() -> void:
	var screen := _open(SettingsScene)
	screen.show_page("sounds")
	var event: String = NotificationEvents.EVENTS[0]
	var choices := _sound_choices(screen)
	var choice: OptionButton = choices[0]
	var saved_index := choice.selected
	# The user picks "Custom file…" (the dialog opens) and cancels it.
	choice.select(2)
	screen._import_event = event
	screen._file_dialog.canceled.emit()
	assert_eq(_sound_choices(screen)[0].selected, saved_index, "back on the saved choice")
	screen.free()


func test_new_theme_shows_up_without_restart() -> void:
	var path := Themes.USER_DIR.path_join(TEST_THEME + ".sdtheme.json")
	var settings := _open(SettingsScene)
	settings.show_page("appearance")
	var gallery := _open(GalleryScene)
	_write_test_theme(path)
	# Coming back to the screens (tab switch) picks up the file.
	for screen: Control in [settings, gallery]:
		screen.visible = false
		screen.visible = true
	assert_true(_has_theme(_live(settings._page_holder, "OptionButton")[0]), "listed in settings")
	assert_true(_has_theme(gallery._theme_select), "listed in the theme gallery")
	settings.free()
	gallery.free()
	DirAccess.remove_absolute(path)
	Themes.discover()


func test_scale_drag_applies_when_it_ends() -> void:
	var saved := _save_scale()
	var gallery := _open(GalleryScene)
	var slider: HSlider = _live(gallery, "HSlider")[0]
	var before := Themes.ui_scale
	var target := 115.0 if not is_equal_approx(before, 1.15) else 120.0
	slider.drag_started.emit()
	slider.value = target
	_assert_near(Themes.ui_scale, before, "not applied while dragging")
	slider.drag_ended.emit(true)
	_assert_near(Themes.ui_scale, target / 100.0, "applied when the drag ends")
	_assert_near(AppConfig.get_setting("appearance", "ui_scale", -1.0), target / 100.0, "saved")
	gallery.free()
	_restore_scale(saved)


func test_scale_drag_interrupted_by_hiding_still_applies() -> void:
	var saved := _save_scale()
	var gallery := _open(GalleryScene)
	var slider: HSlider = _live(gallery, "HSlider")[0]
	var target := 95.0 if not is_equal_approx(Themes.ui_scale, 0.95) else 90.0
	# A shortcut switches screens with the mouse held: no drag_ended.
	slider.drag_started.emit()
	slider.value = target
	gallery.visible = false
	_assert_near(Themes.ui_scale, target / 100.0, "applied when hidden mid-drag")
	gallery.visible = true
	slider.value = 140.0
	_assert_near(Themes.ui_scale, 1.4, "keys apply again afterwards")
	gallery.free()
	_restore_scale(saved)


func test_theme_dropdown_lists_new_theme_when_opened() -> void:
	var path := Themes.USER_DIR.path_join(TEST_THEME + ".sdtheme.json")
	var settings := _open(SettingsScene)
	settings.show_page("appearance")
	var gallery := _open(GalleryScene)
	_write_test_theme(path)
	# "Open themes folder", drop the file in, open the dropdown: the screen stays visible.
	var settings_select: OptionButton = _live(settings._page_holder, "OptionButton")[0]
	settings_select.get_popup().about_to_popup.emit()
	gallery._theme_select.get_popup().about_to_popup.emit()
	assert_true(_has_theme(settings_select), "listed in the open settings dropdown")
	assert_eq(settings_select.get_item_metadata(settings_select.selected), Themes.theme_id, "active theme still selected")
	assert_true(_has_theme(gallery._theme_select), "listed in the open gallery dropdown")
	settings.free()
	gallery.free()
	DirAccess.remove_absolute(path)
	Themes.discover()


func test_removed_active_theme_stays_selected() -> void:
	var saved_theme := Themes.theme_id
	var path := Themes.USER_DIR.path_join(TEST_THEME + ".sdtheme.json")
	_write_test_theme(path)
	Themes.discover()
	Themes.apply(TEST_THEME, false)
	DirAccess.remove_absolute(path)
	var settings := _open(SettingsScene)
	settings.show_page("appearance")
	var gallery := _open(GalleryScene)
	var selects := {"settings": _live(settings._page_holder, "OptionButton")[0], "gallery": gallery._theme_select}
	for where: String in selects:
		var select: OptionButton = selects[where]
		assert_eq(select.get_item_metadata(select.selected), TEST_THEME, where + ": shows the theme in use")
		assert_true(select.is_item_disabled(select.selected), where + ": but it can't be picked again")
	settings.free()
	gallery.free()
	Themes.apply(saved_theme, false)
	Themes.discover()
	assert_true(not Themes.definitions.has(TEST_THEME), "gone once another theme is in use")


# --- Helpers ----------------------------------------------------------------------------

func _open(scene: PackedScene) -> Control:
	var screen: Control = scene.instantiate()
	screen.visible = false
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	screen.visible = true
	return screen


## Descendants of class `type_name`, skipping pages that are queued for deletion (a rebuild
## frees the old page only at the end of the frame).
func _live(parent: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.is_class(type_name):
			result.append(child)
		result.append_array(_live(child, type_name))
	return result


## The per-event dropdowns (the first two are the pack and the output device).
func _sound_choices(screen: Control) -> Array[Node]:
	return _live(screen._page_holder, "OptionButton").slice(2)


## Scales are snapped to 0.05 steps, which isn't exact in floating point.
func _assert_near(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s expected %s, got %s" % [label, expected, actual])


func _write_test_theme(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 1, "name": "Zz Test Theme", "extends": "midnight-dark", "tokens": {}}))
	file.close()


func _has_theme(select: OptionButton) -> bool:
	for i in select.item_count:
		if select.get_item_metadata(i) == TEST_THEME:
			return true
	return false


## [scale, saved setting or null]: a missing setting is removed again afterwards.
func _save_scale() -> Array:
	var has_setting: bool = AppConfig._settings.has_section_key("appearance", "ui_scale")
	return [Themes.ui_scale, AppConfig.get_setting("appearance", "ui_scale") if has_setting else null]


func _restore_scale(saved: Array) -> void:
	Themes.set_ui_scale(saved[0], false)
	if saved[1] != null:
		AppConfig.set_setting("appearance", "ui_scale", saved[1])
	elif AppConfig._settings.has_section_key("appearance", "ui_scale"):
		AppConfig._settings.erase_section_key("appearance", "ui_scale")
		AppConfig._settings.save(AppConfig.SETTINGS_PATH)
