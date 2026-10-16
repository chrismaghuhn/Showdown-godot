extends Control
## App entry point. Owns the screens and switches between them on
## EventBus.navigation_requested. Start screen: --screen=<id> (default dev-console).
## Must stay a Control: Godot only passes the window's theme down through Control/Window
## parents, so screens under a plain Node would fall back to the default theme.

const SCREENS := {
	&"dev-console": preload("res://src/ui/screens/dev_console/dev_console.tscn"),
	&"theme-gallery": preload("res://src/ui/screens/theme_gallery/theme_gallery.tscn"),
}
const DevAutomation := preload("res://src/app/dev_automation.gd")

## Screens are created on first use and kept, so switching back keeps their state.
var _screens := {}


func _ready() -> void:
	EventBus.navigation_requested.connect(show_screen)
	show_screen(StringName(AppConfig.cli("screen", "dev-console")))
	add_child(DevAutomation.new())


func show_screen(screen_id: StringName) -> void:
	if not SCREENS.has(screen_id):
		push_warning("Unknown screen '%s'" % screen_id)
		screen_id = &"dev-console"
	if not _screens.has(screen_id):
		var screen: Control = SCREENS[screen_id].instantiate()
		_screens[screen_id] = screen
		add_child(screen)
	for id: StringName in _screens:
		_screens[id].visible = id == screen_id
