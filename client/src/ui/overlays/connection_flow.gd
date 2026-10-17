class_name ConnectionFlow
extends RefCounted
## Decides which connection UI the app shows for a Connection.status() snapshot (design:
## "03 · Motion & app states", frames 01-03). Free of nodes, so it's unit tested.
##
## A first connection gets the modal card; a connection that drops after it worked gets the
## banner, so battles stay visible while it reconnects.
## ui: {"servers_open": bool, "sign_in_open": bool, "dismissed": bool, "quiet": bool}
## ("quiet": a background connect at launch - only prompts show a card).


## The modal card: &"connecting", &"servers", &"sign_in", &"gave_up" or &"" (none).
static func card_for(status: Dictionary, ui: Dictionary) -> StringName:
	if ui.get("servers_open", false):
		return &"servers"
	var reconnecting: bool = status.get("reconnecting", false)
	var state := int(status.get("state", 0))
	# The socket is open but the server hasn't greeted us (|challstr|) yet: still connecting.
	if state == Connection.State.CONNECTED and not status.get("session_up", true):
		state = Connection.State.CONNECTING
	var quiet: bool = ui.get("quiet", false)
	match state:
		Connection.State.CONNECTING, Connection.State.WAITING:
			return &"" if reconnecting or quiet else &"connecting"
		Connection.State.DISCONNECTED:
			return &"gave_up" if status.get("gave_up", false) and not reconnecting and not quiet else &""
		Connection.State.CONNECTED:
			if reconnecting or status.get("signed_in", false):
				return &""
			if ui.get("sign_in_open", false):
				return &"sign_in"
			if status.get("signing_in", false) or ui.get("dismissed", false) or quiet:
				return &""
			return &"sign_in"
	return &""


## The banner under the app header: {} (hidden) or {tone, title, sub, action}.
static func banner_for(status: Dictionary) -> Dictionary:
	if not status.get("reconnecting", false):
		return {}
	var attempts := _t("Attempt %d of %d.") % [int(status.get("attempt", 1)), int(status.get("max_attempts", 5))]
	var keeps_running := _t("Your battles keep running on the server, and so do their timers.")
	var state := int(status.get("state", 0))
	if state == Connection.State.CONNECTED and not status.get("session_up", true):
		state = Connection.State.CONNECTING
	match state:
		Connection.State.WAITING:
			var seconds := maxi(ceili(float(status.get("retry_in", 0.0))), 1)
			return {"tone": "warning",
				"title": _t("Connection lost — reconnecting in %d s") % seconds,
				"sub": attempts + " " + keeps_running, "action": _t("Retry now")}
		Connection.State.CONNECTING:
			return {"tone": "warning", "title": _t("Connection lost — reconnecting…"),
				"sub": attempts + " " + keeps_running, "action": ""}
		Connection.State.CONNECTED:
			return {"tone": "warning", "title": _t("Connected again — signing in…"),
				"sub": "", "action": ""}
		Connection.State.DISCONNECTED:
			if status.get("gave_up", false):
				return {"tone": "danger", "title": _t("Couldn’t reconnect"),
					"sub": _t("%s didn’t answer after %d attempts.") % [
						status.get("server_host", ""), int(status.get("max_attempts", 5))] + " " + keeps_running,
					"action": _t("Try again")}
	return {}


## The status in the app header: {text, color_token}.
static func status_label(status: Dictionary) -> Dictionary:
	var state := int(status.get("state", 0))
	if status.get("reconnecting", false) or state == Connection.State.DISCONNECTED:
		return {"text": _t("Offline"), "color_token": "color.warning.text"}
	if state != Connection.State.CONNECTED or not status.get("session_up", true):
		return {"text": _t("Connecting…"), "color_token": "color.text.muted"}
	if status.get("signed_in", false):
		return {"text": str(status.get("username", "")), "color_token": "color.success.text"}
	return {"text": _t("Sign in"), "color_token": "color.text.muted"}


## "sim3.psim.us · attempt 1", or "sim3.psim.us · attempt 2 of 5 in 4 s" while waiting.
static func attempt_line(status: Dictionary) -> String:
	var host := str(status.get("server_host", ""))
	var attempt := int(status.get("attempt", 1))
	if int(status.get("state", 0)) == Connection.State.WAITING:
		return _t("%s · attempt %d of %d in %d s") % [host, attempt,
			int(status.get("max_attempts", 5)), maxi(ceili(float(status.get("retry_in", 0.0))), 1)]
	return _t("%s · attempt %d") % [host, attempt]


## "Reconnected" toast text for EventBus.battles_restored.
static func restored_text(count: int) -> String:
	if count <= 0:
		return _t("You’re back online.")
	if count == 1:
		return _t("1 battle restored.")
	return _t("%d battles restored.") % count


static func _t(text: String) -> String:
	return str(TranslationServer.translate(text))
