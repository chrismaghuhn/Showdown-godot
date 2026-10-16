extends Node
## Command-line driven automation for development and headless end-to-end tests.
## Does nothing unless --server is given.
##
##   godot --path client --headless -- --server=local --name=BotA \
##       --search=gen9randombattle --quit-after-battle --timeout=300
##   godot --path client --headless -- --check-data [--data-url=...] [--sprite-url=...]

var _searched := false


func _ready() -> void:
	if AppConfig.has_cli("check-data"):
		_check_data()
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


func _finish(code: int, reason: String) -> void:
	_log(reason)
	get_tree().quit(code)


func _log(text: String) -> void:
	print("[automation] " + text)
