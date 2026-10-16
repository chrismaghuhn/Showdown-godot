class_name PluginManifest
extends RefCounted
## Parsed and validated `plugin.json`. See docs/plugin-api.md.

const KNOWN_PERMISSIONS := ["ui", "send_commands", "storage"]

var id := ""
var name := ""
var version := ""
var api_version := 0
var entry := "main.gd"
var description := ""
var permissions := PackedStringArray()
## Absolute or user:// path of the plugin folder.
var dir := ""
## Non-empty when the manifest is invalid; such plugins are listed but never loaded.
var error := ""


static func load_from_dir(plugin_dir: String) -> PluginManifest:
	var m := PluginManifest.new()
	m.dir = plugin_dir
	m.id = plugin_dir.get_file()
	var path := plugin_dir.path_join("plugin.json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		m.error = "plugin.json missing or not valid JSON"
		return m

	m.id = str(data.get("id", ""))
	m.name = str(data.get("name", m.id))
	m.version = str(data.get("version", "0.0.0"))
	m.api_version = int(data.get("api_version", 0))
	m.entry = str(data.get("entry", "main.gd"))
	m.description = str(data.get("description", ""))
	m.permissions = PackedStringArray(data.get("permissions", []))

	var id_pattern := RegEx.create_from_string("^[a-z0-9][a-z0-9-]*$")
	if id_pattern.search(m.id) == null:
		m.error = "invalid id '%s' (use lowercase letters, digits and dashes)" % m.id
	elif m.api_version != PluginAPI.VERSION:
		m.error = "needs plugin API v%d, client provides v%d" % [m.api_version, PluginAPI.VERSION]
	elif not FileAccess.file_exists(m.dir.path_join(m.entry)):
		m.error = "entry script '%s' not found" % m.entry
	else:
		for p in m.permissions:
			if not p in KNOWN_PERMISSIONS:
				m.error = "unknown permission '%s'" % p
	return m


func is_valid() -> bool:
	return error.is_empty()
