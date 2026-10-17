class_name SessionStore
extends RefCounted
## Keeps login server session cookies across restarts, for "Stay signed in".
##
## One cookie per login server, in user://session.cfg (owner-only permissions where the OS
## has them). Passwords are never stored anywhere.

const PATH := "user://session.cfg"


static func load_cookie(api_base: String, path := PATH) -> String:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return ""
	return str(file.get_value("sessions", _key(api_base), ""))


static func save_cookie(api_base: String, sid: String, path := PATH) -> void:
	var file := ConfigFile.new()
	file.load(path)
	if sid.is_empty():
		if not file.has_section_key("sessions", _key(api_base)):
			return
		file.erase_section_key("sessions", _key(api_base))
	else:
		file.set_value("sessions", _key(api_base), sid)
	if file.save(path) == OK and OS.get_name() in ["Linux", "macOS", "FreeBSD"]:
		FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)


static func clear(api_base: String, path := PATH) -> void:
	save_cookie(api_base, "", path)


## ConfigFile keys can't hold every URL character: "https://play.pokemonshowdown.com/api/" ->
## "play.pokemonshowdown.com/api".
static func _key(api_base: String) -> String:
	var rest := api_base.get_slice("://", 1) if api_base.contains("://") else api_base
	return rest.trim_suffix("/").replace("=", "_").replace("\"", "_")
