class_name HomeScreen
extends Control
## Home tab: the lobby (design: "Lobby / Home").
##   main   Find a battle (format picker, team, Battle! / Searching… + Cancel, challenge a
##          user, challenges you sent), your battles, incoming challenges
##   aside  your account and ladder ratings; chat rooms come in v0.2
## Keys: Ctrl+Enter battle, Esc cancel the search.

const ASIDE_WIDTH := 340

## Main sets this: room id -> the battle's tab number for Ctrl+N (0 = none).
var tab_number := Callable()

var _format := FormatPicker.new()
var _team := Button.new()
var _battle := RichButton.new(&"PrimaryButton", 16, 8)
var _battle_text := RichButton.label(tr("Battle!"), &"OnAccentLabel")
var _searching := RichButton.new(&"SearchingButton", 12, 12)
var _search_time := RichButton.label("", &"MonoLabel")
var _cancel := Button.new()
var _sent := VBoxContainer.new()
var _rated := RichButton.label("", &"MutedLabel")
var _battles_count := RichButton.label("", &"TabMetaLabel")
var _battles := GridContainer.new()
var _battles_empty := RichButton.label("", &"MutedLabel")
var _challenges_count := RichButton.label("", &"TabMetaLabel")
var _challenges := VBoxContainer.new()
var _account := VBoxContainer.new()
var _challenge_dialog := ChallengeDialog.new()
var _challenge_button: Button
var _search_started_msec := -1
## The battle cards need a rebuild; done once per frame, and only while Home is visible (a
## replayed battle log is hundreds of messages).
var _battles_dirty := false


func _ready() -> void:
	_build()
	_format.select(str(AppConfig.get_setting("play", "last_format", QuickBattleCard.DEFAULT_FORMAT)))
	_format.format_selected.connect(func(id: String) -> void:
		AppConfig.set_setting("play", "last_format", id)
		var name := FormatList.display_name(Rooms.formats, id)
		if not name.is_empty():
			AppConfig.set_setting("play", "last_format_name", name)
		_refresh_find())
	EventBus.search_changed.connect(func(_s: PackedStringArray, _g: Dictionary) -> void: _refresh_find())
	EventBus.formats_changed.connect(_refresh_find)
	EventBus.ratings_changed.connect(func() -> void:
		_refresh_find()
		_refresh_account())
	EventBus.challenges_changed.connect(func() -> void:
		_refresh_challenges()
		_refresh_sent())
	EventBus.logged_in.connect(func(_u: String) -> void: _refresh_account())
	EventBus.signed_out.connect(_refresh_account)
	EventBus.connection_state_changed.connect(func(_s: int) -> void:
		_refresh_account()
		_refresh_find())
	EventBus.battle_started.connect(func(_b: BattleState) -> void: _queue_battles())
	EventBus.battle_attention_changed.connect(func(_b: BattleState) -> void: _queue_battles())
	EventBus.battle_ended.connect(func(_b: BattleState, _w: String) -> void: _queue_battles())
	EventBus.battle_updated.connect(func(_b: BattleState, msg: PSMessage) -> void:
		if msg.type in ["turn", "player", "switch", "drag", "faint", "-damage", "-heal", "inactive", "teamsize"]:
			_queue_battles())
	EventBus.room_left.connect(func(_room: String) -> void: _queue_battles())
	var ticker := Timer.new()
	ticker.wait_time = 1.0
	ticker.autostart = true
	ticker.timeout.connect(_refresh_find)
	add_child(ticker)
	add_child(_challenge_dialog)
	_refresh_find()
	_refresh_sent()
	_refresh_battles()
	_refresh_challenges()
	_refresh_account()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and is_visible_in_tree() and _battles_dirty:
		_refresh_battles.call_deferred()


# --- Layout -------------------------------------------------------------------------------

func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"AppBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	background.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main)
	main.add_child(_find_panel())
	var battles_box := VBoxContainer.new()
	battles_box.add_child(_battles_empty)
	battles_box.add_child(_battles)
	_battles_empty.text = tr("No active battles. Battles you start or join show up here.")
	_battles_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(_section(tr("Your battles"), _battles_count, battles_box))
	_battles.columns = 2
	_battles.add_theme_constant_override("h_separation", 12)
	_battles.add_theme_constant_override("v_separation", 12)
	main.add_child(_section(tr("Incoming challenges"), _challenges_count, _challenges))

	var aside := VBoxContainer.new()
	aside.custom_minimum_size.x = ASIDE_WIDTH
	aside.add_theme_constant_override("separation", 8)
	row.add_child(aside)
	var account := PanelContainer.new()
	account.theme_type_variation = &"SectionPanel"
	_account.add_theme_constant_override("separation", 12)
	account.add_child(_account)
	aside.add_child(account)
	var rooms := EmptyState.section(tr("Chat rooms"), tr("Lobby, format rooms and private chats come in v0.2."))
	aside.add_child(rooms)


func _find_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SectionPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var head := HBoxContainer.new()
	var title := RichButton.label(tr("Find a battle"), &"TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_challenge_button = StateCard.make_button(tr("Challenge a user…"), &"SmallGhostButton", func() -> void:
		_challenge_dialog.open_at(_challenge_button))
	_challenge_button.icon = Icons.get_icon("ui-user-plus")
	head.add_child(_challenge_button)
	column.add_child(head)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	column.add_child(fields)
	_format.min_width = 240
	fields.add_child(_field(tr("Format"), _format))
	_team.disabled = true
	_team.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_team.custom_minimum_size.y = 40
	_team.clip_text = true
	var team_field := _field(tr("Team"), _team)
	team_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(team_field)
	var actions := HBoxContainer.new()
	actions.custom_minimum_size.x = 260
	actions.size_flags_vertical = Control.SIZE_SHRINK_END
	_battle.custom_minimum_size.y = 40
	_battle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle.add(_battle_text)
	_battle.add_spacer()
	_battle.add(RichButton.kbd("Ctrl+Enter", true))
	_battle.pressed.connect(func() -> void: Rooms.search(_format.selected_id))
	actions.add_child(_battle)
	_searching.custom_minimum_size.y = 40
	_searching.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_searching.add(Spinner.new("color.accent.text"))
	_searching.add(RichButton.label(tr("Searching…"), &"AccentLabel"))
	_searching.add_spacer()
	_searching.add(_search_time)
	_searching.focus_mode = Control.FOCUS_NONE
	actions.add_child(_searching)
	_cancel.text = tr("Cancel")
	_cancel.custom_minimum_size.y = 40
	_cancel.tooltip_text = tr("Cancel the search (Esc)")
	_cancel.pressed.connect(Rooms.cancel_search)
	actions.add_child(_cancel)
	fields.add_child(actions)

	_sent.add_theme_constant_override("separation", 4)
	column.add_child(_sent)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	var notify := CheckBox.new()
	notify.text = tr("Sound + desktop notification when a battle is found")
	notify.button_pressed = bool(Notifier.get_value("battle_found.sound")) or bool(Notifier.get_value("battle_found.desktop"))
	notify.toggled.connect(func(on: bool) -> void:
		Notifier.set_value("battle_found.sound", on)
		Notifier.set_value("battle_found.desktop", on))
	foot.add_child(notify)
	_rated.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_rated)
	column.add_child(foot)
	return panel


func _section(title: String, count: Label, body: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SectionPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var head := HBoxContainer.new()
	head.add_child(RichButton.label(title, &"CardTitleLabel"))
	head.add_child(count)
	column.add_child(head)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	return panel


func _field(label_text: String, control: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.add_child(RichButton.label(label_text, &"FieldLabel"))
	column.add_child(control)
	return column


# --- Find a battle ----------------------------------------------------------------------------

func _refresh_find() -> void:
	var searching := Rooms.is_searching()
	if searching and _search_started_msec < 0:
		_search_started_msec = Time.get_ticks_msec()
	elif not searching:
		_search_started_msec = -1
	_battle.visible = not searching
	_searching.visible = searching
	_cancel.visible = searching
	if searching:
		var seconds := (Time.get_ticks_msec() - _search_started_msec) / 1000
		_search_time.text = "%d:%02d" % [seconds / 60, seconds % 60]
	var format := _format_info(_format.selected_id)
	var needs_team: bool = not format.is_empty() and not format["preset_team"]
	_team.text = tr("Needs a team · the Teambuilder comes in v0.2") if needs_team else tr("Team from the server · no team needed")
	_battle.disabled = needs_team
	_rated.text = rated_line(_format.selected_id, format, Rooms.ratings)


## Challenges you sent, with "Cancel challenge" (rebuilt only when they change).
func _refresh_sent() -> void:
	_clear(_sent)
	for id: String in Rooms.challenges:
		var challenge: Dictionary = Rooms.challenges[id]
		if challenge["incoming"]:
			continue
		var line := HBoxContainer.new()
		line.add_child(IconView.new("ui-user-plus", "color.text.secondary"))
		line.add_child(RichButton.label(tr("Challenge sent to %s") % challenge["user"], &"DockTitleLabel"))
		line.add_child(RichButton.label(_format_name(str(challenge["format"])), &"FormatChip"))
		var waiting := RichButton.label(tr("waiting for them to accept"), &"MutedLabel")
		waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(waiting)
		var user := str(challenge["user"])
		line.add_child(StateCard.make_button(tr("Cancel challenge"), &"SmallGhostButton", func() -> void:
			Rooms.cancel_challenge(user)))
		_sent.add_child(line)


## "Rated · your ladder rating 1621" / "Rated · no rating in this format yet" / "Unrated".
static func rated_line(format_id: String, format: Dictionary, ratings: Dictionary) -> String:
	var name := str(format.get("name", format_id))
	if name.to_lower().contains("unrated") or (not format.is_empty() and not format["search"]):
		return _t("Unrated")
	if ratings.has(format_id):
		return _t("Rated · your ladder rating %d") % int(ratings[format_id]["elo"])
	return _t("Rated · no rating in this format yet")


func _format_info(format_id: String) -> Dictionary:
	for format in Rooms.formats:
		if format["id"] == format_id:
			return format
	return {}


func _format_name(format_id: String) -> String:
	var name := FormatList.display_name(Rooms.formats, PSParser.to_id(format_id))
	return name if not name.is_empty() else format_id


# --- Your battles -----------------------------------------------------------------------------

func _queue_battles() -> void:
	if _battles_dirty:
		return
	_battles_dirty = true
	if is_visible_in_tree():
		_refresh_battles.call_deferred()


func _refresh_battles() -> void:
	_battles_dirty = false
	_clear(_battles)
	var running := Rooms.running_battles()
	_battles_count.text = str(running.size()) if not running.is_empty() else ""
	_battles_empty.visible = running.is_empty()
	_battles.visible = not running.is_empty()
	for battle in running:
		var number: int = tab_number.call(battle.room_id) if tab_number.is_valid() else 0
		var card := LobbyBattleCard.new(battle, number)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.open_requested.connect(func(room: String) -> void:
			EventBus.navigation_requested.emit(StringName("battle:" + room)))
		_battles.add_child(card)


# --- Incoming challenges ----------------------------------------------------------------------

func _refresh_challenges() -> void:
	_clear(_challenges)
	var incoming: Array[Dictionary] = []
	for id: String in Rooms.challenges:
		if Rooms.challenges[id]["incoming"]:
			incoming.append(Rooms.challenges[id])
	_challenges_count.text = str(incoming.size()) if not incoming.is_empty() else ""
	if incoming.is_empty():
		var empty := RichButton.label(tr("Nobody has challenged you."), &"MutedLabel")
		_challenges.add_child(empty)
		return
	var now := int(Time.get_unix_time_from_system())
	for challenge in incoming:
		_challenges.add_child(_challenge_row(challenge, now))


func _challenge_row(challenge: Dictionary, now: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 56
	var user := str(challenge["user"])
	var avatar := PanelContainer.new()
	avatar.theme_type_variation = &"AvatarPanel"
	avatar.custom_minimum_size = Vector2(28, 28)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var initials := RichButton.label(AccountButton.initials(user), &"AvatarLabel")
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.add_child(initials)
	row.add_child(avatar)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	who.custom_minimum_size.x = 160
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(RichButton.label(user, &"DockTitleLabel"))
	who.add_child(RichButton.label(tr("%s ago") % NotificationBell.time_ago(now - int(challenge["time"])) \
		if now - int(challenge["time"]) >= 60 else tr("just now"), &"MutedLabel"))
	row.add_child(who)
	var chip := RichButton.label(_format_name(str(challenge["format"])), &"FormatChip")
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var needs_team := Rooms.format_needs_team(Rooms.formats, str(challenge["format"]))
	var team := RichButton.label(tr("Needs a team · Teambuilder in v0.2") if needs_team else tr("No team needed"), &"MutedLabel")
	team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(team)
	var accept := StateCard.make_button(tr("Accept"), &"SmallPrimaryButton", func() -> void: Rooms.accept_challenge(user))
	accept.disabled = needs_team
	accept.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(accept)
	var decline := StateCard.make_button(tr("Decline"), &"SmallGhostButton", func() -> void: Rooms.reject_challenge(user))
	decline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(decline)
	return row


# --- Account ----------------------------------------------------------------------------------

func _refresh_account() -> void:
	_clear(_account)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var status := Connection.status()
	var view := AccountButton.describe(status, str(AppConfig.get_setting("account", "username", "")))
	var avatar := PanelContainer.new()
	avatar.theme_type_variation = &"AvatarPanel"
	avatar.custom_minimum_size = Vector2(40, 40)
	var initials := RichButton.label(view["initials"], &"AvatarLabel")
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.add_child(initials)
	head.add_child(avatar)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var online: bool = int(status["state"]) == Connection.State.CONNECTED and status["session_up"]
	var shown_name: String = view["name"] if status["signed_in"] or online or not str(AppConfig.get_setting("account", "username", "")).is_empty() \
		else tr("Not signed in")
	text.add_child(RichButton.label(shown_name, &"CardTitleLabel"))
	var line := HBoxContainer.new()
	line.add_child(StatusDot.new("color.success.text" if online else "color.warning.text", false, 7.0))
	var state_text := tr("Online · signed in") if status["signed_in"] else (tr("Online · guest") if online else tr("Offline"))
	line.add_child(RichButton.label(state_text, &"MutedLabel"))
	text.add_child(line)
	head.add_child(text)
	var action := StateCard.make_button(tr("Log out") if status["signed_in"] else tr("Sign in"), &"SmallGhostButton",
		func() -> void:
			if Connection.signed_in:
				Connection.sign_out()
			else:
				EventBus.sign_in_requested.emit())
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(action)
	_account.add_child(head)
	if not status["signed_in"]:
		return
	var rows := rating_rows(Rooms.ratings, Rooms.formats)
	if rows.is_empty():
		_account.add_child(RichButton.label(tr("No ladder games yet."), &"MutedLabel"))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	for entry: Array in rows:
		var format_label := RichButton.label(entry[0], &"SmallSecondaryLabel")
		format_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(format_label)
		grid.add_child(RichButton.label(str(entry[1]), &"MonoSmallLabel"))
	_account.add_child(grid)


## [[format name, elo], ...], highest first, at most six.
static func rating_rows(ratings: Dictionary, formats: Array[Dictionary]) -> Array:
	var rows: Array = []
	for format_id: String in ratings:
		var name := FormatList.display_name(formats, format_id)
		rows.append([name if not name.is_empty() else format_id, int(ratings[format_id]["elo"])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return rows.slice(0, 6)


## Removes the children right away (queue_free alone would keep them in the layout until the
## end of the frame).
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- Keys -------------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		if Rooms.is_searching():
			return
		if not _battle.disabled:
			Rooms.search(_format.selected_id)
	elif key.keycode == KEY_ESCAPE and not key.ctrl_pressed and Rooms.is_searching():
		Rooms.cancel_search()
	else:
		return
	get_viewport().set_input_as_handled()


static func _t(text: String) -> String:
	return str(TranslationServer.translate(text))
