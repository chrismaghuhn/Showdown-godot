extends Node
## Command-line driven automation for development and headless end-to-end tests.
## Does nothing unless --server is given.
##
##   godot --path client --headless -- --server=local --name=BotA \
##       --search=gen9randombattle --quit-after-battle --timeout=300

var _searched := false


func _ready() -> void:
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


func _finish(code: int, reason: String) -> void:
	_log(reason)
	get_tree().quit(code)


func _log(text: String) -> void:
	print("[automation] " + text)
