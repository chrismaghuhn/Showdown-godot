class_name StartScreen
extends Control
## Start screen, only at launch (design: "Start screen · only at launch"):
##   left   "Welcome back", the battle in progress with Rejoin (Enter), the menu 1–5
##   right  Quick battle (Ctrl+Enter), recent teams, news
##   footer "Show this screen when the app starts", key hints, version, Quit
## Esc cancels a running search. The app header above it has no tabs (Main's start mode).

const MAX_WIDTH := 1152
const LEFT_WIDTH := 432

## [id, icon, title, description, screen (empty = not available yet)]
const MENU := [
	["play", "ui-play", "Play", "Find a battle and see your running battles", &"home"],
	["teambuilder", "ui-grid-view", "Teambuilder", "Coming in v0.2 · Random Battles need no team", &"teambuilder"],
	["watch", "ui-watch", "Watch", "Coming in v0.2 · live battles and replays", &"watch"],
	["chat", "ui-chat", "Chat rooms", "Coming in v0.2 · lobby and format rooms", &""],
	["settings", "ui-settings", "Settings", "Theme, notifications, sounds", &"settings"],
]

var _margin := MarginContainer.new()
var _scroll := ScrollContainer.new()
var _page := VBoxContainer.new()
var _welcome := RichButton.label("", &"DisplayLabel")
var _welcome_sub := RichButton.label("", &"SecondaryLabel")
var _running := RunningBattleCard.new()
var _quick := QuickBattleCard.new()
var _news_list := VBoxContainer.new()
var _news := NewsFeed.new()
var _menu_buttons: Array[Button] = []
## Read once at launch, before the app records this session.
var _last_seen := 0


func _ready() -> void:
	_last_seen = int(AppConfig.get_setting("session", "last_seen", 0))
	_build()
	EventBus.battle_started.connect(func(_b: BattleState) -> void: _refresh())
	EventBus.battle_attention_changed.connect(func(_b: BattleState) -> void: _refresh())
	EventBus.battle_ended.connect(func(_b: BattleState, _winner: String) -> void: _refresh())
	EventBus.battle_updated.connect(func(_b: BattleState, msg: PSMessage) -> void:
		if msg.type in ["turn", "player", "switch", "drag", "-damage", "-heal", "inactive"]:
			_refresh())
	EventBus.room_left.connect(func(_room: String) -> void: _refresh())
	EventBus.search_changed.connect(func(_s: PackedStringArray, _g: Dictionary) -> void: _refresh())
	EventBus.logged_in.connect(func(_u: String) -> void: _refresh())
	EventBus.signed_out.connect(_refresh)
	_running.rejoin_requested.connect(_rejoin)
	_news.loaded.connect(_show_news)
	add_child(_news)
	_news.load_news()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_width()


# --- Layout -------------------------------------------------------------------------------

func _build() -> void:
	var background := PanelContainer.new()
	background.theme_type_variation = &"AppBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	background.add_child(column)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.resized.connect(_fit_width)
	column.add_child(_scroll)
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_margin)
	_page.add_theme_constant_override("separation", 0)
	_margin.add_child(_page)
	# Spacers above and below center the content when the window is taller than it.
	_page.add_child(_spacer())
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 32)
	_page.add_child(grid)
	_page.add_child(_spacer())

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.custom_minimum_size.x = LEFT_WIDTH
	grid.add_child(left)
	var hello := VBoxContainer.new()
	hello.add_theme_constant_override("separation", 4)
	_welcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_welcome_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hello.add_child(_welcome)
	hello.add_child(_welcome_sub)
	left.add_child(hello)
	left.add_child(_running)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 4)
	left.add_child(menu)
	for i in MENU.size():
		var item := _menu_item(i)
		_menu_buttons.append(item)
		menu.add_child(item)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(right)
	right.add_child(_quick)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	right.add_child(cards)
	var teams := EmptyState.section(tr("Recent teams"),
		tr("Teams you build or import show up here. The Teambuilder comes in v0.2."))
	teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cards.add_child(teams)
	cards.add_child(_news_card())

	column.add_child(_footer())


func _menu_item(index: int) -> Button:
	var entry: Array = MENU[index]
	var item := RichButton.new(&"StartMenuItem", 12, 16)
	item.custom_minimum_size.y = 64
	item.focus_mode = Control.FOCUS_ALL
	var icon_box := PanelContainer.new()
	icon_box.theme_type_variation = &"StartIconPanel"
	icon_box.custom_minimum_size = Vector2(40, 40)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := IconView.new(entry[1], "color.text.primary")
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.add_child(icon)
	item.add(icon_box)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_child(RichButton.label(tr(entry[2]), &"StartItemTitleLabel"))
	var description := RichButton.label(tr(entry[3]), &"MutedLabel")
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.custom_minimum_size.x = 120
	text.add_child(description)
	item.add(text)
	item.add(RichButton.kbd(str(index + 1)))
	var screen: StringName = entry[4]
	item.disabled = screen == &""
	item.pressed.connect(func() -> void: EventBus.navigation_requested.emit(screen))
	return item


func _news_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"SectionPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var head := HBoxContainer.new()
	var title := RichButton.label(tr("News"), &"CardTitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(StateCard.make_button(tr("All news"), &"SmallGhostButton", func() -> void:
		OS.shell_open(NewsFeed.REPO_URL + "/releases")))
	column.add_child(head)
	_news_list.add_theme_constant_override("separation", 12)
	column.add_child(_news_list)
	_show_news([])
	return card


func _footer() -> PanelContainer:
	var footer := PanelContainer.new()
	footer.theme_type_variation = &"StartFooter"
	footer.custom_minimum_size.y = 48
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	footer.add_child(row)
	var show_start := CheckBox.new()
	show_start.text = tr("Show this screen when the app starts")
	show_start.button_pressed = bool(AppConfig.get_setting("general", "show_start_screen", true))
	show_start.toggled.connect(func(on: bool) -> void: AppConfig.set_setting("general", "show_start_screen", on))
	row.add_child(show_start)
	var back := HBoxContainer.new()
	back.add_theme_constant_override("separation", 4)
	back.add_child(RichButton.label(tr("Only at launch · back anytime via"), &"MutedLabel"))
	back.add_child(RichButton.kbd("Ctrl+K"))
	back.add_child(RichButton.label(tr("› Start screen"), &"MutedLabel"))
	row.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for hint: Array in [[["1", "5"], tr("menu")], [["Enter"], tr("rejoin")], [["Ctrl+Enter"], tr("battle")]]:
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 4)
		var key_list: Array = hint[0]
		for i in key_list.size():
			if i > 0:
				keys.add_child(RichButton.label("–", &"MutedLabel"))
			keys.add_child(RichButton.kbd(str(key_list[i])))
		keys.add_child(RichButton.label(str(hint[1]), &"MutedLabel"))
		row.add_child(keys)
	row.add_child(RichButton.label(str(ProjectSettings.get_setting("application/config/version", "")), &"MonoSmallLabel"))
	var quit := StateCard.make_button(tr("Quit"), &"SmallGhostButton", func() -> void:
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		get_tree().quit())
	quit.icon = Icons.get_icon("ui-quit")
	quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(quit)
	return footer


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


## Caps the content at MAX_WIDTH and centers it vertically (design: max-width 1152, padding
## 24 / 32).
func _fit_width() -> void:
	var side := maxi(32, int((_scroll.size.x - MAX_WIDTH) / 2.0))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", 24)
	_margin.add_theme_constant_override("margin_bottom", 24)
	_page.custom_minimum_size.y = maxf(_scroll.size.y - 48, 0)


# --- Content ------------------------------------------------------------------------------

func _refresh() -> void:
	var name := Connection.username if Connection.signed_in else str(AppConfig.get_setting("account", "username", ""))
	var running := Rooms.running_battles()
	var unjoined := _unjoined_games()
	var view := welcome(name, _last_seen, int(Time.get_unix_time_from_system()), running.size() + unjoined.size())
	_welcome.text = view["title"]
	_welcome_sub.text = view["sub"]
	if not running.is_empty():
		_running.show_battle(running[0])
		_running.visible = true
	elif not unjoined.is_empty():
		_running.show_game(unjoined[0], str(Rooms.games[unjoined[0]]))
		_running.visible = true
	else:
		_running.visible = false


## {title, sub} for the welcome lines.
static func welcome(name: String, last_seen: int, now: int, running: int) -> Dictionary:
	if name.is_empty() and last_seen <= 0:
		return {"title": _t("Welcome to Showdown Desktop"),
			"sub": _t("Start a Random Battle right away – no team needed.")}
	var parts := PackedStringArray()
	if last_seen > 0:
		parts.append(_t("Last session %s ago") % NotificationBell.time_ago(maxi(now - last_seen, 60)))
	if running == 1:
		parts.append(_t("1 battle still running"))
	elif running > 1:
		parts.append(_t("%d battles still running") % running)
	var title := _t("Welcome back, %s") % name if not name.is_empty() else _t("Welcome back")
	return {"title": title, "sub": " · ".join(parts)}


## Running games the server lists for this user that the client hasn't joined.
func _unjoined_games() -> Array[String]:
	var result: Array[String] = []
	for room_id: String in Rooms.games:
		if room_id.begins_with("battle-") and Rooms.get_battle(room_id) == null:
			result.append(room_id)
	return result


func _rejoin(room_id: String) -> void:
	if room_id.is_empty():
		return
	EventBus.navigation_requested.emit(StringName("battle:" + room_id))


func _show_news(items: Array[Dictionary]) -> void:
	for child in _news_list.get_children():
		child.queue_free()
	if items.is_empty():
		_news_list.add_child(RichButton.label(tr("No news yet. Client releases show up here."), &"MutedLabel"))
		return
	for i in mini(items.size(), 3):
		var item: Dictionary = items[i]
		var article := VBoxContainer.new()
		article.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		head.add_child(RichButton.label(tr("Client %s") % str(item["tag"]).trim_prefix("v"), &"FormatChip"))
		head.add_child(RichButton.label(NewsFeed.short_date(int(item["date"])), &"MutedLabel"))
		article.add_child(head)
		var link := LinkButton.new()
		link.text = str(item["title"])
		link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		var url := str(item["url"])
		link.pressed.connect(func() -> void: OS.shell_open(url))
		article.add_child(link)
		if not str(item["summary"]).is_empty():
			var summary := RichButton.label(str(item["summary"]), &"MutedLabel")
			summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			article.add_child(summary)
		_news_list.add_child(article)


# --- Keys ---------------------------------------------------------------------------------

## 1–5 menu, Enter rejoin, Ctrl+Enter quick battle, Esc cancel search (design footer).
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var number := key.keycode - KEY_1
	if key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		_quick.battle()
	elif key.ctrl_pressed or key.alt_pressed or key.shift_pressed:
		return
	elif number >= 0 and number < _menu_buttons.size():
		if not _menu_buttons[number].disabled:
			_menu_buttons[number].emit_signal("pressed")
	elif (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and _running.visible:
		_rejoin(_running.room_id)
	elif key.keycode == KEY_ESCAPE and Rooms.is_searching():
		Rooms.cancel_search()
	else:
		return
	get_viewport().set_input_as_handled()


static func _t(text: String) -> String:
	return str(TranslationServer.translate(text))
