class_name DockPanel
extends PanelContainer
## Panel with a 36px header (icon, title, extras, actions, collapse) and a body.
## Plugin panels show the PLUGIN badge and a source line drawn by the host, so a plugin can't
## hide where its UI comes from (design: Components › Panel).
##
##   var log := DockPanel.new("Battle log", "ui-chat")
##   log.body.add_child(content)

signal collapsed_changed(collapsed: bool)

var body := VBoxContainer.new()
var header_extras := HBoxContainer.new()
var actions := HBoxContainer.new()
var collapsed := false
var _title := Label.new()
var _collapse := Button.new()
var _expand_flag := Control.SIZE_FILL


func _init(title := "", icon_name := "") -> void:
	theme_type_variation = &"DockPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var header := PanelContainer.new()
	header.theme_type_variation = &"DockHeader"
	column.add_child(header)
	var row := HBoxContainer.new()
	header.add_child(row)
	if not icon_name.is_empty():
		row.add_child(IconView.new(icon_name, "color.text.secondary"))
	_title.text = title
	_title.theme_type_variation = &"DockTitleLabel"
	row.add_child(_title)
	row.add_child(header_extras)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	actions.add_theme_constant_override("separation", 2)
	row.add_child(actions)
	_collapse.theme_type_variation = &"IconButton"
	_collapse.text = "▾"
	_collapse.tooltip_text = tr("Collapse panel")
	_collapse.pressed.connect(func() -> void: set_collapsed(not collapsed))
	row.add_child(_collapse)

	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)


func set_title(title: String) -> void:
	_title.text = title


## Adds an icon-only action button; every icon button carries a tooltip.
func add_action(icon_name: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"IconButton"
	button.icon = Icons.get_icon(icon_name)
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	actions.add_child(button)
	return button


## Marks the panel as provided by a plugin: badge in the header, source line in the body.
func set_plugin_source(source_line: String) -> void:
	var badge := Label.new()
	badge.text = tr("Plugin")
	badge.uppercase = true
	badge.theme_type_variation = &"PluginBadge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_extras.add_child(badge)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	var source := Label.new()
	source.text = source_line
	source.theme_type_variation = &"MutedLabel"
	source.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	margin.add_child(source)
	body.add_child(margin)
	body.move_child(margin, 0)


func set_collapsed(value: bool) -> void:
	collapsed = value
	body.visible = not collapsed
	_collapse.text = "▸" if collapsed else "▾"
	_collapse.tooltip_text = tr("Expand panel") if collapsed else tr("Collapse panel")
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN if collapsed else _expand_flag
	collapsed_changed.emit(collapsed)


## Use instead of size_flags_vertical so collapsing can restore it.
func set_vertical_expand(expand: bool) -> void:
	_expand_flag = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	if not collapsed:
		size_flags_vertical = _expand_flag
