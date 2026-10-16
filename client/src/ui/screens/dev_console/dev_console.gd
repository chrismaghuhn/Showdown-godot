extends Control
## Developer console: a deliberately plain screen to exercise the whole stack
## (connect, login, search, battle, plugins). The real UI will live in its own
## screens under src/ui/screens/ and reuse the same events.

const COLOR_SYSTEM := Color(0.6, 0.7, 1.0)
const COLOR_ERROR := Color(1.0, 0.45, 0.45)
const COLOR_CHAT := Color(0.85, 0.85, 0.85)
const COLOR_RAW := Color(0.5, 0.5, 0.5)

var _server_select: OptionButton
var _name_edit: LineEdit
var _pass_edit: LineEdit
var _connect_button: Button
var _status: Label
var _log: RichTextLabel
var _raw_toggle: CheckBox
var _format_edit: LineEdit
var _battle_info: Label
var _actions: VBoxContainer
var _plugin_slot: VBoxContainer
var _command_edit: LineEdit
var _current_battle := ""


func _ready() -> void:
	_build_ui()
	EventBus.connection_state_changed.connect(_on_connection_state_changed)
	EventBus.connection_error.connect(func(r: String) -> void: _print_line(r, COLOR_ERROR))
	EventBus.logged_in.connect(func(u: String) -> void: _print_line(tr("Logged in as %s") % u, COLOR_SYSTEM))
	EventBus.login_failed.connect(func(r: String) -> void: _print_line(tr("Login failed: %s") % r, COLOR_ERROR))
	EventBus.popup.connect(func(t: String) -> void: _print_line(t, COLOR_SYSTEM))
	EventBus.chat_message.connect(_on_chat_message)
	EventBus.message_received.connect(_on_message_received)
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_updated.connect(_on_battle_updated)
	EventBus.battle_request.connect(_on_battle_request)
	EventBus.plugin_panel_added.connect(_on_plugin_panel_added)
	for control in Plugins.get_panels(&"sidebar"):
		_plugin_slot.add_child(control)
	_on_connection_state_changed(Connection.state)


# --- UI construction ------------------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_server_select = OptionButton.new()
	for id: String in AppConfig.SERVERS:
		_server_select.add_item(AppConfig.SERVERS[id]["name"])
		_server_select.set_item_metadata(_server_select.item_count - 1, id)
	top.add_child(_server_select)
	_name_edit = _line_edit(tr("Username"), 180)
	_name_edit.text = str(AppConfig.get_setting("account", "username", ""))
	top.add_child(_name_edit)
	_pass_edit = _line_edit(tr("Password (optional)"), 180)
	_pass_edit.secret = true
	top.add_child(_pass_edit)
	_connect_button = Button.new()
	_connect_button.pressed.connect(_on_connect_pressed)
	top.add_child(_connect_button)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_log)

	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size.x = 340
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_scroll.add_child(sidebar)

	sidebar.add_child(_header(tr("Battle")))
	var search_row := HBoxContainer.new()
	sidebar.add_child(search_row)
	_format_edit = _line_edit("gen9randombattle", 0)
	_format_edit.text = "gen9randombattle"
	_format_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(_format_edit)
	search_row.add_child(_button(tr("Search"), _on_search_pressed))
	search_row.add_child(_button(tr("Cancel"), func() -> void: Connection.send("", "/cancelsearch")))
	_battle_info = Label.new()
	_battle_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_battle_info)
	_actions = VBoxContainer.new()
	sidebar.add_child(_actions)
	sidebar.add_child(_button(tr("Forfeit"), func() -> void:
		if not _current_battle.is_empty():
			Connection.send(_current_battle, "/forfeit")))

	sidebar.add_child(_header(tr("Plugins")))
	for m in Plugins.manifests:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var state := tr("active") if Plugins.is_active(m.id) else (m.error if not m.is_valid() else tr("disabled"))
		label.text = "%s %s - %s" % [m.name, m.version, state]
		sidebar.add_child(label)
	_plugin_slot = VBoxContainer.new()
	sidebar.add_child(_plugin_slot)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_command_edit = _line_edit(tr("Chat or /command (sent to the current battle, or globally)"), 0)
	_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_edit.text_submitted.connect(_on_command_submitted)
	bottom.add_child(_command_edit)
	_raw_toggle = CheckBox.new()
	_raw_toggle.text = tr("Raw protocol")
	bottom.add_child(_raw_toggle)


func _line_edit(placeholder: String, min_width: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.x = min_width
	return edit


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label


## Plain text only - server/user text is never parsed as BBCode.
func _print_line(text: String, color := Color.WHITE) -> void:
	_log.push_color(color)
	_log.add_text(text)
	_log.pop()
	_log.newline()


# --- Connection -------------------------------------------------------------------

func _on_connect_pressed() -> void:
	if Connection.state != Connection.State.DISCONNECTED:
		Connection.disconnect_from_server()
		return
	var server_id: String = _server_select.get_item_metadata(_server_select.selected)
	var username := _name_edit.text.strip_edges()
	Connection.connect_to_server(server_id)
	if not username.is_empty():
		AppConfig.set_setting("account", "username", username)
		Connection.login(username, _pass_edit.text)
	_pass_edit.clear()


func _on_connection_state_changed(state: int) -> void:
	match state:
		Connection.State.DISCONNECTED:
			_status.text = tr("Disconnected")
			_connect_button.text = tr("Connect")
		Connection.State.CONNECTING:
			_status.text = tr("Connecting...")
			_connect_button.text = tr("Cancel")
		Connection.State.CONNECTED:
			_status.text = tr("Connected")
			_connect_button.text = tr("Disconnect")


func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	Connection.send(_current_battle, text)
	_command_edit.clear()


func _on_search_pressed() -> void:
	Connection.send("", "/utm null")
	Connection.send("", "/search " + _format_edit.text.strip_edges())
	_print_line(tr("Searching for a %s battle...") % _format_edit.text, COLOR_SYSTEM)


func _on_message_received(msg: PSMessage) -> void:
	if _raw_toggle.button_pressed:
		_print_line(("[%s] " % msg.room_id if not msg.room_id.is_empty() else "") + msg.raw, COLOR_RAW)
	if msg.type == "error" and not Rooms.battles.has(msg.room_id):
		_print_line(msg.arg(0), COLOR_ERROR)


func _on_chat_message(room_id: String, user: String, text: String) -> void:
	if room_id == _current_battle:
		_print_line("%s: %s" % [user, text], COLOR_CHAT)


func _on_plugin_panel_added(_plugin_id: String, slot: StringName, control: Control) -> void:
	if slot == &"sidebar":
		_plugin_slot.add_child(control)


# --- Battle -------------------------------------------------------------------------

func _on_battle_started(battle: BattleState) -> void:
	_current_battle = battle.room_id
	_print_line(tr("Battle started: %s") % battle.room_id, COLOR_SYSTEM)
	_update_battle_info(battle)


func _on_battle_updated(battle: BattleState, msg: PSMessage) -> void:
	if battle.room_id != _current_battle:
		return
	var line := BattleLogFormatter.format(msg, battle)
	if not line.is_empty():
		_print_line(line)
	_update_battle_info(battle)
	if battle.ended:
		_clear_actions()


func _update_battle_info(battle: BattleState) -> void:
	var lines := PackedStringArray([tr("Turn %d  ·  %s") % [battle.turn, battle.format]])
	for side_id: String in battle.sides:
		var side: BattleSide = battle.sides[side_id]
		var mon := side.active_pokemon()
		var mon_text := "-"
		if mon != null:
			mon_text = "%s %d%% %s" % [mon.species, roundi(mon.hp_percent()), mon.status]
			for stat: String in mon.boosts:
				if mon.boosts[stat] != 0:
					mon_text += " %s%+d" % [stat, mon.boosts[stat]]
		lines.append("%s (%s): %s" % [side_id, side.player_name, mon_text])
	if not battle.weather.is_empty():
		lines.append(tr("Weather: %s") % battle.weather)
	_battle_info.text = "\n".join(lines)


func _on_battle_request(battle: BattleState, request: Dictionary) -> void:
	_current_battle = battle.room_id
	_clear_actions()
	var rqid := int(request.get("rqid", -1))
	if request.get("wait", false):
		return
	if request.get("teamPreview", false):
		_add_action(tr("Team preview: default order"), battle.room_id, "default", rqid)
		return

	var active: Array = request.get("active", [])
	var force_switch: Array = request.get("forceSwitch", [])
	var trapped := false
	if not active.is_empty() and force_switch.is_empty():
		var slot: Dictionary = active[0]
		trapped = slot.get("trapped", false) or slot.get("maybeTrapped", false)
		var moves: Array = slot.get("moves", [])
		for i in moves.size():
			var move: Dictionary = moves[i]
			var button := _add_action("%s (%s/%s)" % [move.get("move", "?"), move.get("pp", "?"), move.get("maxpp", "?")],
				battle.room_id, "move %d" % (i + 1), rqid)
			button.disabled = move.get("disabled", false) or int(move.get("pp", 1)) <= 0

	if trapped:
		return
	var team: Array = request.get("side", {}).get("pokemon", [])
	for i in team.size():
		var mon: Dictionary = team[i]
		var condition := str(mon.get("condition", ""))
		if mon.get("active", false) or condition.ends_with(" fnt"):
			continue
		_add_action(tr("Switch to %s (%s)") % [str(mon.get("details", "")).get_slice(",", 0), condition],
			battle.room_id, "switch %d" % (i + 1), rqid)


func _add_action(text: String, room_id: String, choice: String, rqid: int) -> Button:
	var button := _button(text, func() -> void:
		Connection.choose(room_id, choice, rqid)
		_clear_actions())
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_actions.add_child(button)
	return button


func _clear_actions() -> void:
	for child in _actions.get_children():
		child.queue_free()
