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

var _capture: SubViewport

var _searched := false


func _ready() -> void:
	if AppConfig.has_cli("screenshot"):
		_prepare_offscreen.call_deferred()
	if AppConfig.has_cli("check-data"):
		_check_data()
		return
	if AppConfig.has_cli("notify-test"):
		Notifier.send_test.call_deferred()
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
	EventBus.login_failed.connect(func(r: String) -> void: _finish(1, "login failed: " + r))
	EventBus.logged_in.connect(_on_logged_in)
	EventBus.battle_started.connect(func(b: BattleState) -> void: _log("battle started: " + b.room_id))
	EventBus.battle_ended.connect(_on_battle_ended)
	if AppConfig.has_cli("screenshot-turn"):
		EventBus.battle_updated.connect(_on_battle_updated_for_screenshot)

	Connection.connect_to_server(AppConfig.cli("server"))
	Connection.login(username)


func _on_logged_in(username: String) -> void:
	_log("logged in as " + username)
	if AppConfig.has_cli("search") and not _searched:
		_searched = true
		Connection.send("", "/utm null")
		Connection.send("", "/search " + AppConfig.cli("search"))
		_log("searching " + AppConfig.cli("search"))


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
