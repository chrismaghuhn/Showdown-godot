class_name ComingSoonScreen
extends Control
## A tab whose feature isn't built yet (Teambuilder, Watch in v0.1): an empty state that says
## when it comes and what works already (design: "03 · Motion & app states", frame 06).

var icon := "ui-grid-view"
var title := ""
var text := ""


func _init(icon_name := "ui-grid-view", title_text := "", body_text := "") -> void:
	icon = icon_name
	title = title_text
	text = body_text


func _ready() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"AppBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	background.add_child(center)
	center.add_child(EmptyState.page(icon, title, text, [
		[tr("Play a Random Battle"), func() -> void: EventBus.navigation_requested.emit(&"home")],
	]))
