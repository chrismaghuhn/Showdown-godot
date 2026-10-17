extends Node
## Autoload "AppConfig": persistent user settings, known servers and command-line flags.

const SETTINGS_PATH := "user://settings.cfg"

## Known servers. "login" is either "none" (dev server started with --no-security)
## or the base URL of the login server API. "ratings": where the signed-in user's ladder
## ratings come from - "rank" (the /rank command) or a user JSON URL with %s for the user id.
const SERVERS := {
	"local": {
		"name": "Local server (localhost:8000)",
		"url": "ws://localhost:8000/showdown/websocket",
		"login": "none",
		"ratings": "rank",
	},
	"official": {
		"name": "Pokémon Showdown (official)",
		"url": "wss://sim3.psim.us/showdown/websocket",
		"login": "https://play.pokemonshowdown.com/api/",
		# The server's /rank only points to the web client; the user pages have the ratings.
		"ratings": "https://pokemonshowdown.com/users/%s.json",
	},
}

var _settings := ConfigFile.new()
var _cli := {}


## Where settings are read and saved: user://settings.cfg, or --settings-file=<path> (tests
## and e2e runs use a throwaway file so they never change the user's settings).
var settings_path := SETTINGS_PATH


func _init() -> void:
	# Flags after `--` on the command line, e.g. `godot --path client -- --server=local`.
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		_cli[kv[0]] = kv[1] if kv.size() > 1 else "true"
	settings_path = cli("settings-file", SETTINGS_PATH)
	_settings.load(settings_path)


## --server-url=ws://... replaces the websocket URL of every server (e.g. a test proxy).
func get_server(id: String) -> Dictionary:
	var server: Dictionary = SERVERS.get(id, {})
	if server.is_empty() or not has_cli("server-url"):
		return server
	var copy := server.duplicate()
	copy["url"] = cli("server-url")
	return copy


func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	return _settings.get_value(section, key, default)


func set_setting(section: String, key: String, value: Variant) -> void:
	_settings.set_value(section, key, value)
	_settings.save(settings_path)


func cli(key: String, default := "") -> String:
	return str(_cli.get(key, default))


func has_cli(key: String) -> bool:
	return _cli.has(key)
