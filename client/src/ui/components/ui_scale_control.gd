class_name UiScaleControl
extends HBoxContainer
## UI scale slider with its value ("110 %"), for Settings › Appearance and the theme gallery.
## Keys and clicks apply and save the scale right away, a drag only when it ends (rescaling
## moves the slider under the mouse). The mouse wheel scrolls the page instead of the slider.
## Follows scale changes made elsewhere, since screens stay alive.

var slider := HSlider.new()
var label := Label.new()
var _dragging := false


func _init(width := 200) -> void:
	slider.min_value = Themes.SCALE_MIN * 100
	slider.max_value = Themes.SCALE_MAX * 100
	slider.step = Themes.SCALE_STEP * 100
	slider.scrollable = false
	slider.custom_minimum_size.x = width
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(slider)
	label.theme_type_variation = &"MonoLabel"
	label.custom_minimum_size.x = 52
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(label)
	sync(Themes.ui_scale)
	slider.drag_started.connect(func() -> void: _dragging = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		apply())
	slider.value_changed.connect(func(v: float) -> void:
		label.text = "%d %%" % roundi(v)
		if not _dragging:
			apply())
	EventBus.ui_scale_changed.connect(sync)


## Applies and saves the slider's value if it isn't the current scale already.
func apply() -> void:
	if not is_equal_approx(slider.value / 100.0, Themes.ui_scale):
		Themes.set_ui_scale(slider.value / 100.0)


## Shows `ui_scale` without applying it.
func sync(ui_scale: float) -> void:
	slider.set_value_no_signal(ui_scale * 100.0)
	label.text = "%d %%" % roundi(ui_scale * 100.0)
