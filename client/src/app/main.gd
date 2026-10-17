extends Control
## App shell (design: the header on every board, and "Start screen · only at launch"):
##   header   app mark, tabs (Home, Teambuilder, one per battle, open pages), connection pill,
##            "Search or run a command" (Ctrl+K), notifications, settings, account
##   below    reconnect banner, first-launch download progress, the current tab's screen
##   on top   connection cards, toasts
## At launch the start screen fills the window under a slim header without tabs ("Start").
##
## Screen ids: start, home, teambuilder, watch, settings, battle:<room id>, and with developer
## mode (--dev or Settings › General) dev-console and theme-gallery. --screen=<id> picks the
## first screen (dev automation; "battle" is a battle screen that follows the newest battle).
## Keys: Ctrl+1–9 tab, Ctrl+Tab / Ctrl+Shift+Tab next / previous, Ctrl+W close the tab (a
## running battle asks first), Ctrl+, settings, Ctrl+K command menu.
## Must stay a Control: Godot only passes the window's theme down through Control/Window
## parents, so screens under a plain Node would fall back to the default theme.

const SCENES := {
	&"dev-console": preload("res://src/ui/screens/dev_console/dev_console.tscn"),
	&"theme-gallery": preload("res://src/ui/screens/theme_gallery/theme_gallery.tscn"),
	&"settings": preload("res://src/ui/screens/settings/settings_screen.tscn"),
}
const BattleScreenScene := preload("res://src/ui/screens/battle/battle_screen.tscn")
const DevAutomation := preload("res://src/app/dev_automation.gd")
const FIXED_TABS: Array[StringName] = [&"home", &"teambuilder"]
const DEV_SCREENS: Array[StringName] = [&"dev-console", &"theme-gallery"]
const PAGES: Array[StringName] = [&"start", &"home", &"teambuilder", &"watch", &"settings", &"battle"]
const PAGE_TITLES := {
	&"start": "Start screen", &"home": "Home", &"teambuilder": "Teambuilder", &"watch": "Watch",
	&"settings": "Settings", &"battle": "Battle", &"dev-console": "Console", &"theme-gallery": "Theme gallery",
}
const PAGE_ICONS := {&"watch": "ui-watch", &"settings": "ui-settings", &"battle": "ui-battle",
	&"dev-console": "ui-general", &"theme-gallery": "ui-theme"}
const LAST_SEEN_INTERVAL := 60.0

var connection_overlay := ConnectionOverlay.new()
var connection_banner := ConnectionBanner.new()
var data_panel := DataProgressPanel.new()
var tabs := AppTabs.new()
## The screen on display.
var current: StringName = &""

## Screens are created on first use and kept, so switching back keeps their state.
var _screens := {}
var _content := Control.new()
var _tab_scroll := ScrollContainer.new()
var _start_chip := Label.new()
var _status := ConnectionStatus.new()
var _command := CommandButton.new()
var _bell := NotificationBell.new()
var _account := AccountButton.new()
## A battle to show as soon as its room arrives (rejoining a game after a restart).
var _pending_open := ""
## Battle rooms the user closed; their tab goes when the server confirms (|deinit|). Other
## rooms that go away keep their tab, shown as over.
var _leaving := {}
var _close_dialog := ConfirmationDialog.new()
var _closing_room := ""


func _ready() -> void:
	_build()
	EventBus.navigation_requested.connect(show_screen)
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_updated.connect(func(battle: BattleState, msg: PSMessage) -> void:
		if msg.type in ["turn", "player", "tier", "win", "tie"]:
			_update_battle_tab(battle))
	EventBus.battle_attention_changed.connect(_update_battle_tab)
	EventBus.room_left.connect(_on_room_left)
	EventBus.join_failed.connect(_on_join_failed)
	EventBus.plugin_paused.connect(_on_plugin_paused)
	EventBus.connection_state_changed.connect(func(_s: int) -> void: _refresh_header())
	tabs.tab_selected.connect(show_screen)
	tabs.tab_close_requested.connect(close_tab)
	_command.opening.connect(_fill_command_menu)
	_command.chosen.connect(show_screen)
	_bell.open_screen.connect(show_screen)
	_account.start_screen_requested.connect(show_screen.bind(&"start"))
	for id in FIXED_TABS:
		tabs.add_tab(id, {"title": tr(PAGE_TITLES[id])})
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_refresh_header)
	add_child(timer)
	var last_seen := Timer.new()
	last_seen.wait_time = LAST_SEEN_INTERVAL
	last_seen.autostart = true
	last_seen.timeout.connect(_record_session)
	add_child(last_seen)
	show_screen(first_screen(AppConfig.cli("screen"), bool(AppConfig.get_setting("general", "show_start_screen", true))))
	add_child(DevAutomation.new())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_record_session()


## --screen=<id> wins; otherwise the start screen (if the user keeps it) or Home.
static func first_screen(cli_screen: String, show_start: bool) -> StringName:
	if not cli_screen.is_empty():
		return StringName(cli_screen)
	return &"start" if show_start else &"home"


## Console and theme gallery: --dev, Settings › General › Developer mode, or asked for with
## --screen (dev automation).
static func developer_mode() -> bool:
	return AppConfig.has_cli("dev") or bool(AppConfig.get_setting("general", "developer_mode", false)) \
		or StringName(AppConfig.cli("screen")) in DEV_SCREENS


# --- Layout -------------------------------------------------------------------------------

func _build() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	column.add_child(_build_header())
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
	_close_dialog.title = tr("Forfeit and close?")
	_close_dialog.dialog_text = tr("This battle is still running. Closing it forfeits the battle.")
	_close_dialog.ok_button_text = tr("Forfeit and close")
	_close_dialog.confirmed.connect(func() -> void: _leave_battle(_closing_room, true))
	add_child(_close_dialog)


func _build_header() -> PanelContainer:
	var header := PanelContainer.new()
	header.theme_type_variation = &"AppHeader"
	header.custom_minimum_size.y = 40
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	header.add_child(row)
	var logo := AppLogo.new(20)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(logo)
	var app_name := RichButton.label("Showdown Desktop", &"DockTitleLabel")
	app_name.custom_minimum_size.x = 0
	row.add_child(_spaced(app_name, 8, 12))
	_start_chip.text = tr("Start")
	_start_chip.theme_type_variation = &"FormatChip"
	_start_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_start_chip)
	# Tabs scroll sideways (without a bar) when there are more battles than room.
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_scroll.add_child(tabs)
	row.add_child(_tab_scroll)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_spaced(_status, 0, 8))
	row.add_child(_command)
	row.add_child(_bell)
	var settings := Button.new()
	settings.theme_type_variation = &"IconButton"
	settings.icon = Icons.get_icon("ui-settings")
	settings.tooltip_text = tr("Settings (Ctrl+,)")
	settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings.pressed.connect(show_screen.bind(&"settings"))
	row.add_child(settings)
	row.add_child(_account)
	return header


func _spaced(control: Control, left: int, right: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_right", right)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(control)
	return margin


func _refresh_header() -> void:
	var start := current == &"start"
	_start_chip.visible = start
	_tab_scroll.visible = not start
	# The pill always shows on the start screen; elsewhere only when something is wrong.
	_status.get_parent().visible = start or _status.needs_attention()


# --- Screens ------------------------------------------------------------------------------

func show_screen(id: StringName) -> void:
	var text := str(id)
	if text.begins_with("battle:"):
		var room := text.trim_prefix("battle:")
		if not Rooms.battles.has(room) and not _screens.has(id):
			# A game still running on the server (after a restart): join, open on arrival.
			# Anything else (an old notification about a closed battle) has nothing to open.
			if Rooms.games.has(room):
				_pending_open = room
				Rooms.rejoin(room)
			return
	elif not id in PAGES and not id in DEV_SCREENS:
		push_warning("Unknown screen '%s'" % id)
		id = &"home"
	elif id in DEV_SCREENS and not developer_mode():
		id = &"home"
	var screen := _screen(id)
	for screen_id: StringName in _screens:
		_screens[screen_id].visible = screen_id == id
	current = id
	if id != &"start":
		_ensure_tab(id)
		tabs.select(id)
		_scroll_to_tab(id)
	_refresh_header()
	EventBus.screen_changed.emit(id)


## Closes a tab. A running battle you play in asks first (forfeit); Home and Teambuilder stay.
func close_tab(id: StringName) -> void:
	var text := str(id)
	if id in FIXED_TABS or id == &"start" or not tabs.has_tab(id):
		return
	if text.begins_with("battle:"):
		var room := text.trim_prefix("battle:")
		var battle := Rooms.get_battle(room)
		if battle == null:
			# Gone from the server already: just close the tab.
			_drop_screen(id)
			return
		if not battle.ended and not battle.my_side.is_empty() and Connection.state == Connection.State.CONNECTED:
			_closing_room = room
			_close_dialog.popup_centered()
			return
		_leave_battle(room, false)
		return
	_drop_screen(id)


func _screen(id: StringName) -> Control:
	if _screens.has(id):
		return _screens[id]
	var screen: Control
	var text := str(id)
	if text.begins_with("battle:"):
		var battle_screen: BattleScreen = BattleScreenScene.instantiate()
		battle_screen.bind(text.trim_prefix("battle:"))
		screen = battle_screen
	else:
		match id:
			&"start":
				screen = StartScreen.new()
			&"home":
				screen = HomeScreen.new()
			&"teambuilder":
				screen = ComingSoonScreen.new("ui-grid-view", tr("The Teambuilder is coming"),
					tr("Random Battles bring their own team, so you can play right away. Building, importing and backing up teams comes in v0.2."))
			&"watch":
				screen = ComingSoonScreen.new("ui-watch", tr("Watching is coming"),
					tr("Live battles and your saved replays come in v0.2."))
			&"battle":
				screen = BattleScreenScene.instantiate()
			_:
				screen = SCENES[id].instantiate()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Created hidden, so a background battle doesn't take the plugin panels.
	screen.visible = false
	_content.add_child(screen)
	_screens[id] = screen
	return screen


func _ensure_tab(id: StringName) -> void:
	if tabs.has_tab(id):
		return
	if str(id).begins_with("battle:"):
		var battle := Rooms.get_battle(str(id).trim_prefix("battle:"))
		tabs.add_tab(id, battle_tab_spec(battle) if battle != null else {"title": tr("Battle")}, _first_page_tab())
		return
	tabs.add_tab(id, {"title": tr(PAGE_TITLES.get(id, str(id))), "icon": PAGE_ICONS.get(id, ""), "closable": true})


## Battle tabs go between the fixed tabs and the open pages.
func _first_page_tab() -> StringName:
	for id in tabs.ids():
		if not id in FIXED_TABS and not str(id).begins_with("battle:"):
			return id
	return &""


func _drop_screen(id: StringName) -> void:
	var was_current := current == id
	var before := tabs.ids()
	tabs.remove_tab(id)
	if _screens.has(id):
		_screens[id].queue_free()
		_screens.erase(id)
	if was_current:
		show_screen(next_tab_after_closing(before, id))


## Where to go when the shown tab closes: the next battle for a battle tab (else Home), the
## tab to the left for a page.
static func next_tab_after_closing(ids: Array[StringName], closed: StringName) -> StringName:
	var index := ids.find(closed)
	var rest := ids.filter(func(t: StringName) -> bool: return t != closed)
	if str(closed).begins_with("battle:"):
		var battles := ids.filter(func(t: StringName) -> bool: return str(t).begins_with("battle:"))
		var position := battles.find(closed)
		battles.erase(closed)
		return battles[mini(position, battles.size() - 1)] if not battles.is_empty() else &"home"
	if index > 0 and not rest.is_empty():
		return rest[mini(index - 1, rest.size() - 1)]
	return &"home"


func _scroll_to_tab(id: StringName) -> void:
	# After layout, once the new tab has its size.
	_ensure_tab_visible.call_deferred(id)


func _ensure_tab_visible(id: StringName) -> void:
	var index := tabs.ids().find(id)
	if index >= 0 and index < tabs.get_child_count():
		_tab_scroll.ensure_control_visible(tabs.get_child(index))


func _cycle_tab(step: int) -> void:
	var ids := tabs.ids()
	if ids.is_empty():
		return
	var index := ids.find(current)
	show_screen(ids[posmod(index + step, ids.size())] if index >= 0 else ids[0])


func _fill_command_menu() -> void:
	var entries: Array = []
	for id: StringName in [&"start", &"home", &"teambuilder", &"watch", &"settings"]:
		entries.append([id, tr(PAGE_TITLES[id])])
	var battles := Rooms.running_battles()
	if not battles.is_empty():
		entries.append(["", tr("Battles")])
		for battle in battles:
			var spec := battle_tab_spec(battle)
			entries.append([StringName("battle:" + battle.room_id), "%s · %s" % [spec["title"], spec["meta"]]])
	if developer_mode():
		entries.append(["", tr("Developer")])
		for id in DEV_SCREENS:
			entries.append([id, tr(PAGE_TITLES[id])])
	_command.set_entries(entries)


func _record_session() -> void:
	AppConfig.set_setting("session", "last_seen", int(Time.get_unix_time_from_system()))


# --- Battles ------------------------------------------------------------------------------

func _on_battle_started(battle: BattleState) -> void:
	var id := StringName("battle:" + battle.room_id)
	var opened := battle.room_id == _pending_open
	_screen(id)
	_ensure_tab(id)
	_update_battle_tab(battle)
	if opened:
		_pending_open = ""
	# A battle you just found or asked to open comes to the front; one that came back after a
	# reconnect or restart waits in its tab.
	if opened or not battle.restored:
		show_screen(id)


func _leave_battle(room_id: String, forfeit: bool) -> void:
	_leaving[room_id] = true
	Rooms.leave(room_id, forfeit)


func _on_room_left(room_id: String) -> void:
	var id := StringName("battle:" + room_id)
	if _leaving.erase(room_id):
		_drop_screen(id)
		return
	# The server dropped the room (it expired): keep the tab, shown as over, until closed.
	if _screens.has(id):
		var battle: BattleState = (_screens[id] as BattleScreen).battle
		if battle != null and not battle.ended:
			battle.ended = true
			battle.expired = true
			battle.awaiting_choice = false
			tabs.update_tab(id, battle_tab_spec(battle))


func _on_join_failed(room_id: String, reason: String) -> void:
	if room_id != _pending_open:
		return
	_pending_open = ""
	EventBus.toast_requested.emit({"event": "battle_ended", "title": tr("Couldn’t open the battle"),
		"body": reason if not reason.is_empty() else tr("It has ended or no longer exists.")})


func _update_battle_tab(battle: BattleState) -> void:
	var id := StringName("battle:" + battle.room_id)
	if tabs.has_tab(id):
		tabs.update_tab(id, battle_tab_spec(battle))


## Tab content for a battle (design: "● Mirebloom  OU · T7"): {title, meta, dot, tooltip}.
static func battle_tab_spec(battle: BattleState) -> Dictionary:
	var mine := battle.my_side if not battle.my_side.is_empty() else "p1"
	var opponent := battle.opponent_name()
	var format := short_format(battle.display_format())
	var meta := format
	var dot := ""
	var state := ""
	if battle.ended:
		var me := battle.side(mine).player_name
		if battle.winner.is_empty():
			state = _t("tie") if not battle.my_side.is_empty() and not battle.expired else _t("ended")
		elif battle.my_side.is_empty():
			state = _t("ended")
		else:
			state = _t("won") if PSParser.to_id(battle.winner) == PSParser.to_id(me) else _t("lost")
		meta = "%s · %s" % [format, state]
	else:
		if battle.turn > 0:
			meta = "%s · T%d" % [format, battle.turn]
		dot = "active" if battle.awaiting_choice else "waiting"
		state = _t("your move") if battle.awaiting_choice else _t("waiting")
	var title := opponent if not opponent.is_empty() else _t("Battle")
	return {"title": title, "meta": meta, "dot": dot,
		"tooltip": _t("Battle versus %s, %s") % [title, state] if not opponent.is_empty() else title}


## "[Gen 9] OU" -> "OU", "[Gen 9] Random Battle" / "gen9randombattle" -> "Random".
static func short_format(format: String) -> String:
	var name := format.get_slice("] ", 1) if format.contains("] ") else format
	if name.to_lower().contains("random"):
		return "Random"
	return name


static func _t(text: String) -> String:
	return str(TranslationServer.translate(text))


func _on_plugin_paused(plugin_id: String, reason: String) -> void:
	var manifest := Plugins.get_manifest(plugin_id)
	EventBus.toast_requested.emit({
		"event": "plugin_paused", "key": "plugin_paused:" + plugin_id,
		"title": tr("%s paused") % (manifest.name if manifest != null else plugin_id),
		"body": tr("It caused an error: %s. The battle is not affected.") % reason,
		"actions": [[tr("Reload plugin"), func() -> void: Plugins.reload(plugin_id)], [tr("Keep paused"), Callable()]],
	})


# --- Keys ---------------------------------------------------------------------------------

## App-wide shortcuts, before any focused control sees the keys (Ctrl+Tab would move focus).
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if not key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	# The connection cards are modal: keys there belong to them.
	if connection_overlay.current_card() != &"":
		return
	match key.keycode:
		KEY_K:
			_command.open_menu()
		KEY_COMMA:
			show_screen(&"settings")
		KEY_W:
			close_tab(current)
		KEY_TAB:
			_cycle_tab(-1 if key.shift_pressed else 1)
		_:
			var number := key.keycode - KEY_1
			if key.shift_pressed or number < 0 or number > 8:
				return
			var ids := tabs.ids()
			if number < ids.size():
				show_screen(ids[number])
	get_viewport().set_input_as_handled()
