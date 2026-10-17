extends Node
## Autoload "Notifier": turns battle, chat and challenge events into in-app toasts, sounds,
## desktop notifications and a taskbar flash, following the user's notification settings
## (rules: NotificationEvents). Toasts go out as EventBus.toast_requested; persistent toasts are
## withdrawn with EventBus.toast_dismissed(key) once handled.
##
## Disabled (except toasts) in headless runs and with --no-notifications (tests, e2e bots).
##
## Everything that reached the user (toast or desktop) also goes into `history`, newest first,
## for the bell in the app header; `unread` counts what came in since the bell was last opened.

const SECTION := "notifications"
## A battle that starts this soon after we were searching counts as "battle found".
const SEARCH_GRACE_MS := 15000
const HISTORY_SIZE := 30

## [{event, title, body, time (unix seconds), screen}] newest first.
var history: Array[Dictionary] = []
var unread := 0
## Challenges with a toast up (by user id); the toast goes when the challenge ends.
var _challenge_toasts := {}

var _sound_and_desktop := true
var _current_screen := &""
var _last_searching_ms := -1
var _notified_rqid := {}
var _timer_warned := {}


func _ready() -> void:
	_sound_and_desktop = not AppConfig.has_cli("no-notifications") and DisplayServer.get_name() != "headless"
	EventBus.message_received.connect(_on_message)
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_request.connect(_on_battle_request)
	EventBus.battle_updated.connect(_on_battle_updated)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.private_message.connect(_on_private_message)
	EventBus.chat_message.connect(_on_chat_message)
	EventBus.screen_changed.connect(_on_screen_changed)
	# However a challenge ends (declined or accepted here, in the lobby, or cancelled by them),
	# the server only says so from our side; Rooms knows which ones are still open.
	EventBus.challenges_changed.connect(func() -> void:
		for id: String in _challenge_toasts.keys():
			if not Rooms.challenges.has(id) or not Rooms.challenges[id]["incoming"]:
				_challenge_toasts.erase(id)
				EventBus.toast_dismissed.emit("challenge:" + id))


# --- Settings -------------------------------------------------------------------------------

func get_value(key: String) -> Variant:
	return AppConfig.get_setting(SECTION, key, NotificationEvents.default_value(key))


func set_value(key: String, value: Variant) -> void:
	AppConfig.set_setting(SECTION, key, value)


func settings() -> Dictionary:
	var result := {}
	for event: String in NotificationEvents.EVENTS:
		for channel: String in NotificationEvents.CHANNELS:
			result["%s.%s" % [event, channel]] = get_value("%s.%s" % [event, channel])
	for key: String in NotificationEvents.GENERAL_DEFAULTS:
		result[key] = get_value(key)
	return result


func reset_events() -> void:
	for event: String in NotificationEvents.EVENTS:
		for channel: String in NotificationEvents.CHANNELS:
			set_value("%s.%s" % [event, channel], NotificationEvents.default_value("%s.%s" % [event, channel]))


func volume() -> float:
	return float(get_value("volume"))


# --- Posting --------------------------------------------------------------------------------

## actions: [[label, Callable], ...]; key: lets the notifier withdraw a persistent toast later.
func post(event: String, title: String, body: String, actions: Array = [], key := "", on_screen := false, force := false) -> void:
	var focused := get_window().has_focus() and not force
	var channels := NotificationEvents.channels(event, settings(), focused, on_screen and not force)
	if force:
		channels = {"toast": true, "sound": true, "desktop": true}
	if channels["toast"]:
		EventBus.toast_requested.emit({"event": event, "title": title, "body": body, "actions": actions,
			"key": key, "persistent": event in NotificationEvents.PERSISTENT})
	if (channels["toast"] or channels["desktop"]) and key != "test":
		_remember(event, title, body, _screen_for_key(key))
	if not _sound_and_desktop:
		return
	if channels["sound"]:
		Sounds.play(event, volume())
	if channels["desktop"]:
		NativeNotifier.post(title, body)
	if event == "your_turn" and bool(get_value("flash_taskbar")) and not get_window().has_focus():
		DisplayServer.window_request_attention()


## The bell was opened: everything in the history counts as seen.
func mark_all_read() -> void:
	if unread > 0:
		unread = 0
		EventBus.notifications_changed.emit()


func clear_history() -> void:
	history.clear()
	unread = 0
	EventBus.notifications_changed.emit()


func _remember(event: String, title: String, body: String, screen: String) -> void:
	history.push_front({"event": event, "title": title, "body": body,
		"time": int(Time.get_unix_time_from_system()), "screen": screen})
	if history.size() > HISTORY_SIZE:
		history.resize(HISTORY_SIZE)
	unread = mini(unread + 1, HISTORY_SIZE)
	EventBus.notifications_changed.emit()


## "your_turn:battle-gen9ou-12" -> "battle:battle-gen9ou-12" (where clicking it leads).
static func _screen_for_key(key: String) -> String:
	var room_id := key.get_slice(":", 1) if key.contains(":") else ""
	return "battle:" + room_id if room_id.begins_with("battle-") else ""


## "Send test notification" in the settings: all channels, regardless of focus.
func send_test() -> void:
	post("your_turn", tr("Your turn · Turn 13"), tr("vs sandsea · Random Battle · 2:10 left on your clock"),
		[[tr("Dismiss"), Callable()]], "test", false, true)


# --- Events ---------------------------------------------------------------------------------

func _on_message(msg: PSMessage) -> void:
	if msg.type == "updatesearch":
		var data: Variant = JSON.parse_string(msg.arg(0))
		if data is Dictionary and not (data.get("searching", []) as Array).is_empty():
			_last_searching_ms = Time.get_ticks_msec()


func _on_screen_changed(screen: StringName) -> void:
	_current_screen = screen
	# Looking at a battle handles its "your turn" toast.
	if str(screen).begins_with("battle:"):
		EventBus.toast_dismissed.emit("your_turn:" + str(screen).trim_prefix("battle:"))


func _on_battle_started(battle: BattleState) -> void:
	if _last_searching_ms < 0 or Time.get_ticks_msec() - _last_searching_ms > SEARCH_GRACE_MS:
		return
	_last_searching_ms = -1
	var format := battle.room_id.get_slice("-", 1)
	post("battle_found", tr("Battle found"), tr("%s · opening the battle") % format,
		[[tr("Open battle"), _go_to_battle.bind(battle.room_id)], [tr("Stay here"), Callable()]],
		"battle_found:" + battle.room_id, _on_battle_screen(battle))


func _on_battle_request(battle: BattleState, request: Dictionary) -> void:
	if request.get("wait", false):
		EventBus.toast_dismissed.emit("your_turn:" + battle.room_id)
		return
	var rqid := int(request.get("rqid", -1))
	if _notified_rqid.get(battle.room_id, -2) == rqid:
		return
	_notified_rqid[battle.room_id] = rqid
	post("your_turn", tr("Your turn · Turn %d") % maxi(battle.turn, 1), _battle_line(battle),
		[[tr("Go to battle"), _go_to_battle.bind(battle.room_id)]], "your_turn:" + battle.room_id, _on_battle_screen(battle))


func _on_battle_updated(battle: BattleState, msg: PSMessage) -> void:
	if msg.type == "turn":
		EventBus.toast_dismissed.emit("timer_low:" + battle.room_id)
	if msg.type != "inactive" or battle.timer_turn_seconds < 0:
		return
	var warning := int(get_value("timer_warning"))
	if battle.timer_turn_seconds > warning or _timer_warned.get(battle.room_id, -1) == battle.turn:
		return
	_timer_warned[battle.room_id] = battle.turn
	post("timer_low", tr("Timer running low · %d:%02d") % [battle.timer_turn_seconds / 60, battle.timer_turn_seconds % 60],
		tr("%s · Turn %d — choose before your clock runs out.") % [_battle_line(battle), battle.turn],
		[[tr("Go to battle"), _go_to_battle.bind(battle.room_id)]], "timer_low:" + battle.room_id, _on_battle_screen(battle))


func _on_battle_ended(battle: BattleState, winner: String) -> void:
	for prefix in ["your_turn:", "timer_low:"]:
		EventBus.toast_dismissed.emit(prefix + battle.room_id)
	var title := tr("The battle ended in a tie")
	if not winner.is_empty():
		title = tr("You won") if PSParser.to_id(winner) == PSParser.to_id(Connection.username) else tr("You lost")
	post("battle_ended", title, _battle_line(battle), [], "battle_ended:" + battle.room_id, _on_battle_screen(battle))


func _on_private_message(from: String, to: String, text: String) -> void:
	var me := Connection.username
	var sender := from.substr(1) if not from.is_empty() and PSParser.to_id(from[0]).is_empty() else from
	# An empty "/challenge" (or one we sent) means a challenge ended: withdraw its toast.
	if text == "/challenge" or (text.begins_with("/challenge ") and NotificationEvents.challenge_format(from, to, text, me).is_empty()):
		EventBus.toast_dismissed.emit("challenge:" + PSParser.to_id(sender))
		return
	var format := NotificationEvents.challenge_format(from, to, text, me)
	if not format.is_empty():
		var format_name := FormatList.display_name(Rooms.formats, PSParser.to_id(format.get_slice("@@@", 0)))
		var body := format_name if not format_name.is_empty() else format
		var actions := [[tr("Decline"), func() -> void: Rooms.reject_challenge(sender)]]
		if Rooms.format_needs_team(Rooms.formats, format):
			body += " · " + tr("needs a team (Teambuilder in v0.2)")
		else:
			actions.push_front([tr("Accept"), func() -> void: Rooms.accept_challenge(sender)])
		_challenge_toasts[PSParser.to_id(sender)] = true
		post("challenge", tr("Challenge from %s") % sender, body, actions, "challenge:" + PSParser.to_id(sender))
	elif NotificationEvents.is_private_message(from, text, me):
		post("private_message", tr("Message from %s") % sender, text.trim_prefix("/me "))


func _on_chat_message(room_id: String, user: String, text: String) -> void:
	var sender := user.substr(1) if not user.is_empty() and PSParser.to_id(user[0]).is_empty() else user
	if NotificationEvents.is_mention(sender, text, Connection.username):
		post("mention", tr("%s mentioned you") % sender, text)


func _battle_line(battle: BattleState) -> String:
	var opponent := battle.opponent_name()
	return tr("vs %s · %s") % [opponent, battle.display_format()] if not opponent.is_empty() else battle.display_format()


func _on_battle_screen(battle: BattleState) -> bool:
	return _current_screen == StringName("battle:" + battle.room_id)


func _go_to_battle(room_id: String) -> void:
	EventBus.navigation_requested.emit(StringName("battle:" + room_id))
	get_window().grab_focus()
