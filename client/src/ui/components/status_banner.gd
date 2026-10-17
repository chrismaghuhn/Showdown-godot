class_name StatusBanner
extends PanelContainer
## Full-width strip under the app header (design: ".ms-banner"), e.g. "Connection lost —
## reconnecting in 4 s" with a "Retry now" button. Tone: warning, danger or success.

signal action_pressed

const TONE_ICONS := {"warning": "ui-warning", "danger": "ui-alert", "success": "ui-check-circle"}

var _icon := IconView.new()
var _title := Label.new()
var _sub := Label.new()
var _action := Button.new()


func _init() -> void:
	custom_minimum_size.y = 44
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	_title.theme_type_variation = &"DockTitleLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_title)
	_sub.theme_type_variation = &"SmallSecondaryLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_sub)
	_action.theme_type_variation = &"SmallButton"
	_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action.pressed.connect(func() -> void: action_pressed.emit())
	row.add_child(_action)
	set_content("warning", "", "")


## Updates the text in place (the countdown changes every second); "" hides sub or action.
func set_content(tone: String, title: String, sub: String, action_text := "") -> void:
	theme_type_variation = StringName("Banner_" + tone)
	_icon.icon_name = TONE_ICONS.get(tone, "ui-info")
	_icon.color_token = "color.%s.text" % tone
	_title.text = title
	_sub.text = sub
	_sub.visible = not sub.is_empty()
	_action.text = action_text
	_action.visible = not action_text.is_empty()
