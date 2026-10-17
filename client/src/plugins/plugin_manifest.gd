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


## Loads the manifest of every plugin folder in `dirs`, in search order. A later plugin
## with an id that was already found is marked invalid, so the first copy always wins.
static func load_all(dirs: PackedStringArray) -> Array[PluginManifest]:
	var result: Array[PluginManifest] = []
	var first_dir := {}
	for base in dirs:
		for sub in DirAccess.get_directories_at(base):
			var m := load_from_dir(base.path_join(sub))
			if not first_dir.has(m.id):
				first_dir[m.id] = m.dir
			elif m.is_valid():
				m.error = "duplicate id, already provided by %s" % first_dir[m.id]
			result.append(m)
	return result


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
	m.description = str(data.get("description", ""))
	# int(null) or PackedStringArray("ui") would abort this function, so check types first.
	var api_version: Variant = data.get("api_version", 0)
	var entry: Variant = data.get("entry", "main.gd")
	var permissions: Variant = data.get("permissions", [])
	if not (api_version is float or api_version is int):
		m.error = "\"api_version\" must be a number"
		return m
	if not entry is String:
		m.error = "\"entry\" must be a string"
		return m
	if not permissions is Array or (permissions as Array).any(func(p: Variant) -> bool: return not p is String):
		m.error = "\"permissions\" must be a list of strings"
		return m
	m.api_version = int(api_version)
	m.entry = entry
	m.permissions = PackedStringArray(permissions)

	var id_pattern := RegEx.create_from_string("^[a-z0-9][a-z0-9-]*$")
	if id_pattern.search(m.id) == null:
		m.error = "invalid id '%s' (use lowercase letters, digits and dashes)" % m.id
	elif m.id != plugin_dir.get_file():
		m.error = "id '%s' does not match its folder name '%s'" % [m.id, plugin_dir.get_file()]
	elif m.api_version != PluginAPI.VERSION:
		m.error = "needs plugin API v%d, client provides v%d" % [m.api_version, PluginAPI.VERSION]
	elif not is_entry_inside(m.dir, m.entry):
		m.error = "entry '%s' must be a .gd file inside the plugin folder" % m.entry
	elif not FileAccess.file_exists(m.dir.path_join(m.entry)):
		m.error = "entry script '%s' not found" % m.entry
	else:
		for p in m.permissions:
			if not p in KNOWN_PERMISSIONS:
				m.error = "unknown permission '%s'" % p
	return m


## True if `entry` is a relative path to a .gd file that stays inside `plugin_dir`.
static func is_entry_inside(plugin_dir: String, entry: String) -> bool:
	if entry.get_extension() != "gd" or entry.begins_with("/") or entry.contains(":") \
			or entry.contains("\\") or ".." in entry.split("/"):
		return false
	var folder := plugin_dir.simplify_path().trim_suffix("/") + "/"
	return plugin_dir.path_join(entry).simplify_path().begins_with(folder)


func is_valid() -> bool:
	return error.is_empty()
