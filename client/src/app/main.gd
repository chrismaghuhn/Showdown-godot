extends Control
## App entry point: a 40px app header with screen tabs and the connection status, the
## reconnect banner and download progress, the screens, and the connection cards on top.
## Switches screens on EventBus.navigation_requested; a started battle opens the battle tab.
## Start screen: --screen=<id> (default dev-console).
## Must stay a Control: Godot only passes the window's theme down through Control/Window
## parents, so screens under a plain Node would fall back to the default theme.

const SCREENS := {
	&"dev-console": preload("res://src/ui/screens/dev_console/dev_console.tscn"),
	&"theme-gallery": preload("res://src/ui/screens/theme_gallery/theme_gallery.tscn"),
	&"battle": preload("res://src/ui/screens/battle/battle_screen.tscn"),
	&"settings": preload("res://src/ui/screens/settings/settings_screen.tscn"),
}
const TAB_TITLES := {&"dev-console": "Console", &"theme-gallery": "Theme gallery", &"battle": "Battle", &"settings": "Settings"}
const DevAutomation := preload("res://src/app/dev_automation.gd")

## Screens are created on first use and kept, so switching back keeps their state.
var _screens := {}
var _content := Control.new()
var _tabs := TabBar.new()
var _tab_ids: Array[StringName] = []
var _syncing_tabs := false
## The battle the battle tab shows (restored battles don't take its place).
var _tab_room := ""
var _tab_battle: BattleState
var connection_overlay := ConnectionOverlay.new()
var connection_banner := ConnectionBanner.new()
var data_panel := DataProgressPanel.new()


func _ready() -> void:
	_build_header()
	EventBus.navigation_requested.connect(show_screen)
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_updated.connect(_on_battle_updated)
	EventBus.plugin_paused.connect(_on_plugin_paused)
	EventBus.room_left.connect(func(room_id: String) -> void:
		if room_id == _tab_room and _tab_battle != null:
			_update_battle_tab(_tab_battle))
	show_screen(StringName(AppConfig.cli("screen", "dev-console")))
	add_child(DevAutomation.new())


func _build_header() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var header := PanelContainer.new()
	header.theme_type_variation = &"AppHeader"
	header.custom_minimum_size.y = 40
	column.add_child(header)
	var row := HBoxContainer.new()
	header.add_child(row)
	var app_name := Label.new()
	app_name.text = "Showdown Desktop"
	app_name.theme_type_variation = &"DockTitleLabel"
	row.add_child(app_name)
	_tabs.clip_tabs = true
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_tab_changed)
	row.add_child(_tabs)
	for id: StringName in [&"dev-console", &"theme-gallery", &"settings"]:
		_add_tab(id, TAB_TITLES[id])
	row.add_child(ConnectionStatus.new())
	# App states (design: "03 · Motion & app states"): reconnect banner and first-launch
	# download progress above the screens, connection cards over everything.
	column.add_child(connection_banner)
	column.add_child(data_panel)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_content)
	add_child(connection_overlay)
	# Toasts float above every screen, bottom-right (design: max 3, newest on top).
	var toasts := ToastStack.new()
	toasts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.offset_right = -16
	toasts.offset_bottom = -16
	add_child(toasts)


func show_screen(screen_id: StringName) -> void:
	if not SCREENS.has(screen_id):
		push_warning("Unknown screen '%s'" % screen_id)
		screen_id = &"dev-console"
	if not _screens.has(screen_id):
		var screen: Control = SCREENS[screen_id].instantiate()
		_screens[screen_id] = screen
		_content.add_child(screen)
	for id: StringName in _screens:
		_screens[id].visible = id == screen_id
	if not screen_id in _tab_ids:
		_add_tab(screen_id, TAB_TITLES.get(screen_id, str(screen_id)))
	_syncing_tabs = true
	_tabs.current_tab = _tab_ids.find(screen_id)
	_syncing_tabs = false
	EventBus.screen_changed.emit(screen_id)


func _on_plugin_paused(plugin_id: String, reason: String) -> void:
	var manifest := Plugins.get_manifest(plugin_id)
	EventBus.toast_requested.emit({
		"event": "plugin_paused", "key": "plugin_paused:" + plugin_id,
		"title": tr("%s paused") % (manifest.name if manifest != null else plugin_id),
		"body": tr("It caused an error: %s. The battle is not affected.") % reason,
		"actions": [[tr("Reload plugin"), func() -> void: Plugins.reload(plugin_id)], [tr("Keep paused"), Callable()]],
	})


func _add_tab(screen_id: StringName, title: String) -> void:
	_tab_ids.append(screen_id)
	_tabs.add_tab(tr(title))


func _on_tab_changed(index: int) -> void:
	if not _syncing_tabs and index >= 0 and index < _tab_ids.size():
		show_screen(_tab_ids[index])


func _on_battle_started(battle: BattleState) -> void:
	# A battle restored after a reconnect stays in the background unless it's the one shown.
	if battle.restored and not _tab_room.is_empty() and battle.room_id != _tab_room:
		return
	_tab_room = battle.room_id
	_tab_battle = battle
	if not battle.restored:
		show_screen(&"battle")
	elif not &"battle" in _tab_ids:
		_add_tab(&"battle", TAB_TITLES[&"battle"])
	_update_battle_tab(battle)


func _on_battle_updated(battle: BattleState, msg: PSMessage) -> void:
	if battle.room_id == _tab_room and msg.type in ["turn", "player", "tier", "win", "tie"]:
		_update_battle_tab(battle)


## "vs Mirebloom · Random Battle · T7"
func _update_battle_tab(battle: BattleState) -> void:
	var index := _tab_ids.find(&"battle")
	if index == -1:
		return
	var opponent_id := "p2" if battle.my_side != "p2" else "p1"
	var opponent := battle.side(opponent_id).player_name
	var format := battle.format.get_slice("] ", 1) if battle.format.contains("] ") else battle.format
	var parts := PackedStringArray()
	if not opponent.is_empty():
		parts.append(tr("vs %s") % opponent)
	if not format.is_empty():
		parts.append(format)
	if battle.turn > 0:
		parts.append("T%d" % battle.turn)
	if battle.ended:
		parts.append(tr("ended"))
	_tabs.set_tab_title(index, " · ".join(parts) if not parts.is_empty() else tr("Battle"))
