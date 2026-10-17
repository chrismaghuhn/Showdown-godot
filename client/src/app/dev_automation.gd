extends Node
## Command-line driven automation for development and headless end-to-end tests.
## Does nothing unless --server is given.
##
##   godot --path client --headless -- --server=local --name=BotA \
##       --search=gen9randombattle --quit-after-battle --timeout=300
##   godot --path client --headless -- --check-data [--data-url=...] [--sprite-url=...]
##   godot --path client -- --screen=theme-gallery --theme=classic-light --screenshot=/tmp/shot.png
##   ... --notify-test   (sends the settings' test notification: toast, sound, desktop)
##   ... --server=local --search=gen9randombattle --screenshot=/tmp/battle.png --screenshot-turn=3
##       (screenshot once the battle reaches that turn, then keep playing)
## Screenshots render the app into an offscreen viewport of exactly --screenshot-size
## (default 1280x800, scaled by --ui-scale), independent of the window manager.
##   ... --app-state=<id> --screenshot=/tmp/state.png   (shows one app state with sample data:
##       connecting, connecting-retry, servers, sign-in, sign-in-password, sign-in-error,
##       reconnecting, reconnect-failed, gave-up, loading)
##   ... --server=local --server-url=ws://127.0.0.1:8001/showdown/websocket   (through a proxy,
##       see tools/net_fault_proxy.py and tools/e2e_reconnect.sh)
##   ... --fault-proxy=8002 --faults=3:cut,8:blackhole [--fault-hold=8]
##       (sends a command to the proxy's control port when the battle reaches that turn; a
##       blackhole is lifted with "normal" after --fault-hold seconds)

const APP_STATES := ["connecting", "connecting-retry", "servers", "sign-in", "sign-in-password",
	"sign-in-error", "reconnecting", "reconnect-failed", "gave-up", "loading"]

var _capture: SubViewport

var _searched := false
## turn -> proxy command (--faults)
var _faults := {}


func _ready() -> void:
	if AppConfig.has_cli("screenshot"):
		_prepare_offscreen.call_deferred()
	if AppConfig.has_cli("check-data"):
		_check_data()
		return
	if AppConfig.has_cli("notify-test"):
		Notifier.send_test.call_deferred()
	if AppConfig.has_cli("app-state"):
		_preview_app_state.call_deferred(AppConfig.cli("app-state"))
	if AppConfig.has_cli("screenshot") and not AppConfig.has_cli("screenshot-turn"):
		_screenshot(AppConfig.cli("screenshot"), true)
		return
	if not AppConfig.has_cli("server"):
		queue_free()
		return
	var username := AppConfig.cli("name", "Dev%d" % randi_range(1000, 9999))
	var timeout := AppConfig.cli("timeout", "0").to_float()
	if timeout > 0:
		get_tree().create_timer(timeout).timeout.connect(_finish.bind(2, "timeout after %ss" % timeout))

	EventBus.connection_error.connect(func(r: String) -> void: _finish(1, "connection error: " + r))
	EventBus.reconnect_scheduled.connect(func(attempt: int, max_attempts: int, delay: float) -> void:
		_log("connection lost (%s), attempt %d of %d in %.1f s" % [Connection.last_error, attempt, max_attempts, delay]))
	EventBus.reconnected.connect(func() -> void: _log("reconnected as " + Connection.username))
	EventBus.battles_restored.connect(func(count: int) -> void: _log("battles restored: %d" % count))
	EventBus.login_failed.connect(func(r: String) -> void: _finish(1, "login failed: " + r))
	EventBus.logged_in.connect(_on_logged_in)
	EventBus.battle_started.connect(func(b: BattleState) -> void: _log("battle started: " + b.room_id))
	EventBus.battle_ended.connect(_on_battle_ended)
	if AppConfig.has_cli("screenshot-turn"):
		EventBus.battle_updated.connect(_on_battle_updated_for_screenshot)
	if AppConfig.has_cli("fault-proxy"):
		for entry in AppConfig.cli("faults").split(",", false):
			_faults[entry.get_slice(":", 0).to_int()] = entry.get_slice(":", 1)
		EventBus.battle_updated.connect(_on_battle_updated_for_faults)

	Connection.connect_to_server(AppConfig.cli("server"))
	Connection.login(username)


func _on_logged_in(username: String) -> void:
	_log("logged in as " + username)
	if AppConfig.has_cli("search") and not _searched:
		_searched = true
		Connection.send("", "/utm null")
		Connection.send("", "/search " + AppConfig.cli("search"))
		_log("searching " + AppConfig.cli("search"))


func _on_battle_updated_for_faults(battle: BattleState, msg: PSMessage) -> void:
	if msg.type != "turn" or not _faults.has(battle.turn):
		return
	var command: String = _faults[battle.turn]
	_faults.erase(battle.turn)
	_proxy_command(command)
	if command == "blackhole":
		get_tree().create_timer(AppConfig.cli("fault-hold", "8").to_float()).timeout.connect(_proxy_command.bind("normal"))


## Sends one command to tools/net_fault_proxy.py's control port.
func _proxy_command(command: String) -> void:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", AppConfig.cli("fault-proxy").to_int()) != OK:
		_log("proxy: could not reach the control port")
		return
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		await get_tree().process_frame
		peer.poll()
	peer.put_data((command + "\n").to_utf8_buffer())
	_log("proxy: " + command)
	await get_tree().create_timer(0.5).timeout
	peer.disconnect_from_host()


## Shows one app state from the design board with sample data, for screenshots.
func _preview_app_state(id: String) -> void:
	if not id in APP_STATES:
		_log("unknown --app-state '%s', known: %s" % [id, ", ".join(APP_STATES)])
		return
	var app: Node = get_parent()
	var overlay: ConnectionOverlay = app.connection_overlay
	var host := "sim3.psim.us"
	var base := {"state": Connection.State.CONNECTED, "attempt": 1, "max_attempts": 5, "retry_in": 0.0,
		"reconnecting": false, "gave_up": false, "signed_in": false, "signing_in": false, "username": "",
		"session_name": "", "server_host": host, "last_error": ""}
	match id:
		"connecting":
			overlay.preview(base.merged({"state": Connection.State.CONNECTING}, true), {})
		"connecting-retry":
			overlay.preview(base.merged({"state": Connection.State.WAITING, "attempt": 2, "retry_in": 4.0}, true), {})
		"servers":
			overlay.preview(base.merged({"state": Connection.State.CONNECTING}, true), {"servers_open": true})
		"sign-in":
			overlay.preview(base, {})
		"sign-in-password", "sign-in-error":
			overlay.preview(base, {}, "ironquill", tr("Wrong password.") if id == "sign-in-error" else "")
			var card := overlay.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is SignInCard)
			if not card.is_empty():
				(card[0] as SignInCard).fill_for_preview("ironquill", "examplepw")
		"reconnecting":
			app.connection_banner.preview(base.merged({"state": Connection.State.WAITING, "attempt": 2,
				"retry_in": 4.0, "reconnecting": true}, true))
			EventBus.toast_requested.emit({"event": "reconnected", "title": tr("Reconnected"),
				"body": ConnectionFlow.restored_text(2), "persistent": true})
		"reconnect-failed":
			app.connection_banner.preview(base.merged({"state": Connection.State.DISCONNECTED, "attempt": 5,
				"reconnecting": true, "gave_up": true}, true))
		"gave-up":
			overlay.preview(base.merged({"state": Connection.State.DISCONNECTED, "attempt": 5, "gave_up": true,
				"last_error": "No answer from sim3.psim.us"}, true), {})
		"loading":
			app.data_panel.preview({"fraction": 0.42, "bytes": 1840000, "files": [
				{"label": "Pokédex", "state": "done"}, {"label": "Moves", "state": "done"},
				{"label": "Items", "state": "loading"}, {"label": "Abilities", "state": "pending"},
				{"label": "Type chart", "state": "pending"}]})
	_log("app state: " + id)


func _on_battle_ended(battle: BattleState, winner: String) -> void:
	_log("battle ended after %d turns, winner: %s" % [battle.turn, winner if not winner.is_empty() else "tie"])
	if AppConfig.has_cli("quit-after-battle"):
		_finish(0, "done")


## Loads the game data and a few sprites from the configured source, prints a summary and quits.
func _check_data() -> void:
	get_tree().create_timer(120).timeout.connect(_finish.bind(2, "timeout"))
	EventBus.data_failed.connect(func(r: String) -> void: _finish(1, "data failed: " + r))
	_log("data source: %s, sprites: %s" % [GameData.data_url(), GameData.sprite_url()])
	while GameData.dex == null:
		await EventBus.data_loaded
	var dex := GameData.dex
	_log("dex: %d species, %d moves, %d items, %d abilities, %d types" % [
		dex.species.size(), dex.moves.size(), dex.items.size(), dex.abilities.size(), dex.type_names.size()])
	var chomp := dex.get_species("Garchomp")
	_log("Garchomp %s, Ice deals x%s" % [chomp.types, String.num(dex.effectiveness("Ice", chomp.types))])
	var missing := 0
	for sprite: Array in [["Garchomp", false, false], ["Rotom-Wash", true, false], ["Ogerpon-Wellspring", false, true]]:
		var texture: Texture2D = await GameData.get_sprite(sprite[0], sprite[1], sprite[2])
		if texture == null:
			missing += 1
		_log("sprite %s (back=%s, shiny=%s): %s" % [sprite[0], sprite[1], sprite[2],
			"missing" if texture == null else "%dx%d" % [texture.get_width(), texture.get_height()]])
	_finish(1 if missing > 0 else 0, "data check " + ("failed" if missing > 0 else "ok"))


var _screenshot_taken := false


## Moves the app into a fixed-size SubViewport so screenshots don't depend on the window size.
func _prepare_offscreen() -> void:
	var size_text := AppConfig.cli("screenshot-size", "1280x800")
	var pixels := Vector2i(size_text.get_slice("x", 0).to_int(), size_text.get_slice("x", 1).to_int())
	_capture = SubViewport.new()
	_capture.size = pixels
	_capture.size_2d_override = Vector2i((Vector2(pixels) / Themes.ui_scale).round())
	_capture.size_2d_override_stretch = true
	_capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var app: Control = get_parent()
	# A SubViewport doesn't pass the window theme down, so set it on the app root directly.
	app.theme = Themes.theme
	EventBus.theme_changed.connect(func(_id: String) -> void: app.theme = Themes.theme)
	get_tree().root.add_child(_capture)
	app.reparent(_capture, false)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_battle_updated_for_screenshot(battle: BattleState, _msg: PSMessage) -> void:
	if not _screenshot_taken and battle.turn >= AppConfig.cli("screenshot-turn").to_int():
		_screenshot_taken = true
		_screenshot(AppConfig.cli("screenshot"), AppConfig.has_cli("quit-after-screenshot"))


## Waits until the UI has laid out, rendered and animations settled, then saves the window as
## PNG (and quits if asked).
func _screenshot(path: String, quit_after: bool) -> void:
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var source: Viewport = _capture if _capture != null else get_viewport()
	var image := source.get_texture().get_image()
	var err := image.save_png(path)
	var root := get_tree().root
	var text := "screenshot %s (%dx%d): %s · window %s · content scale size %s · mode %s" % [path, image.get_width(),
		image.get_height(), error_string(err), root.size, root.content_scale_size, root.mode]
	if quit_after:
		_finish(0 if err == OK else 1, text)
	else:
		_log(text)


func _finish(code: int, reason: String) -> void:
	_log(reason)
	get_tree().quit(code)


func _log(text: String) -> void:
	print("[automation] " + text)
