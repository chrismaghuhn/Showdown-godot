extends Node
## Autoload "AppConfig": persistent user settings, known servers and command-line flags.

const SETTINGS_PATH := "user://settings.cfg"

## Known servers. "login" is either "none" (dev server started with --no-security)
## or the base URL of the login server API.
const SERVERS := {
	"local": {
		"name": "Local server (localhost:8000)",
		"url": "ws://localhost:8000/showdown/websocket",
		"login": "none",
	},
	"official": {
		"name": "Pokémon Showdown (official)",
		"url": "wss://sim3.psim.us/showdown/websocket",
		"login": "https://play.pokemonshowdown.com/api/",
	},
}

var _settings := ConfigFile.new()
var _cli := {}


func _init() -> void:
	_settings.load(SETTINGS_PATH)
	# Flags after `--` on the command line, e.g. `godot --path client -- --server=local`.
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		_cli[kv[0]] = kv[1] if kv.size() > 1 else "true"


func get_server(id: String) -> Dictionary:
	return SERVERS.get(id, {})


func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	return _settings.get_value(section, key, default)


func set_setting(section: String, key: String, value: Variant) -> void:
	_settings.set_value(section, key, value)
	_settings.save(SETTINGS_PATH)


func cli(key: String, default := "") -> String:
	return str(_cli.get(key, default))


func has_cli(key: String) -> bool:
	return _cli.has(key)
