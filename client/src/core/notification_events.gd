class_name NotificationEvents
extends RefCounted
## Notification events, their defaults (design: Settings › Notifications) and the rules that
## decide which channels fire. Pure: settings are passed in as a Dictionary.
##
## Channels per event: "toast" (in-app), "sound", "desktop" (OS notification).
## Settings keys (AppConfig section "notifications"):
##   "<event>.<channel>": bool, "only_background": bool, "flash_taskbar": bool,
##   "timer_warning": int seconds (60/30/10), "volume": float 0..1

const EVENTS := ["battle_found", "your_turn", "timer_low", "challenge", "mention", "private_message", "battle_ended"]
const CHANNELS := ["toast", "sound", "desktop"]

const LABELS := {
	"battle_found": ["Battle found", "Matchmaking paired you with an opponent"],
	"your_turn": ["Your turn", "A battle is waiting for your choice"],
	"timer_low": ["Timer running low", "Your clock reaches the warning time"],
	"challenge": ["Challenge received", "Someone challenged you directly"],
	"mention": ["Mentioned in chat", "Your name or a highlight word"],
	"private_message": ["Private message", "A direct message from another user"],
	"battle_ended": ["Battle ended", "Win, loss, tie or forfeit"],
}

## [toast, sound, desktop] defaults from the design.
const DEFAULTS := {
	"battle_found": [true, true, true],
	"your_turn": [true, true, true],
	"timer_low": [true, true, true],
	"challenge": [true, true, false],
	"mention": [true, false, true],
	"private_message": [true, true, true],
	"battle_ended": [true, false, false],
}
const GENERAL_DEFAULTS := {"only_background": true, "flash_taskbar": true, "timer_warning": 30, "volume": 0.7}
const TIMER_OPTIONS := [60, 30, 10]

## Events that stay until handled (design: toast lifetime "stay until handled").
const PERSISTENT := ["your_turn", "challenge", "timer_low"]


static func default_value(key: String) -> Variant:
	if GENERAL_DEFAULTS.has(key):
		return GENERAL_DEFAULTS[key]
	var parts := key.split(".")
	if parts.size() == 2 and DEFAULTS.has(parts[0]) and parts[1] in CHANNELS:
		return DEFAULTS[parts[0]][CHANNELS.find(parts[1])]
	return null


static func get_setting(settings: Dictionary, key: String) -> Variant:
	return settings.get(key, default_value(key))


## Which channels fire for an event.
## focused: the app window has focus; event_on_screen: the event's subject (e.g. that battle) is
## the visible screen. With "only_background", sound and desktop stay quiet while focused;
## toasts are skipped when the subject is already on screen.
static func channels(event: String, settings: Dictionary, focused: bool, event_on_screen := false) -> Dictionary:
	var quiet: bool = focused and bool(get_setting(settings, "only_background"))
	return {
		"toast": bool(get_setting(settings, event + ".toast")) and not (focused and event_on_screen),
		"sound": bool(get_setting(settings, event + ".sound")) and not quiet,
		"desktop": bool(get_setting(settings, event + ".desktop")) and not quiet,
	}


## A |pm| that is an incoming challenge: "/challenge FORMAT|..." sent to us by someone else.
## Returns the format id, or "" if it isn't one (an empty "/challenge" means "cancelled").
static func challenge_format(from: String, to: String, text: String, me: String) -> String:
	if not text.begins_with("/challenge ") or PSParser.to_id(to) != PSParser.to_id(me) \
			or PSParser.to_id(from) == PSParser.to_id(me):
		return ""
	return text.substr(11).get_slice("|", 0).strip_edges()


## A real private message from someone else (not a command like /challenge, /text or /raw).
static func is_private_message(from: String, text: String, me: String) -> bool:
	if PSParser.to_id(from) == PSParser.to_id(me) or text.strip_edges().is_empty():
		return false
	return not text.begins_with("/") or text.begins_with("/me ")


## Our name (or a highlight word) as a whole word in someone else's chat message.
static func is_mention(user: String, text: String, me: String, highlights: PackedStringArray = PackedStringArray()) -> bool:
	if me.is_empty() or PSParser.to_id(user) == PSParser.to_id(me):
		return false
	var words := PackedStringArray([me])
	words.append_array(highlights)
	for word in words:
		if word.strip_edges().is_empty():
			continue
		var pattern := RegEx.create_from_string("(?i)(?<![\\p{L}\\p{N}])" + _escape_regex(word.strip_edges()) + "(?![\\p{L}\\p{N}])")
		if pattern != null and pattern.search(text) != null:
			return true
	return false


static func _escape_regex(text: String) -> String:
	var out := ""
	for c in text:
		out += "\\" + c if "\\^$.|?*+()[]{}".contains(c) else c
	return out
