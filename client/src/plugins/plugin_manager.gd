extends Node
## Autoload "Plugins": discovers, enables and disables plugins.
##
## Search paths:
##   user://plugins/<id>/                 installed plugins (enabled via settings)
##   --plugins-dir=<absolute path>        development plugins, e.g. the repo's plugins/ folder
## Enable on the command line with --enable-plugins=id1,id2.

const USER_PLUGIN_DIR := "user://plugins"

var manifests: Array[PluginManifest] = []
## plugin id -> ClientPlugin
var _active := {}
## [{plugin_id, slot, control}] - kept so UI created later can pick up panels.
var _panels: Array[Dictionary] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_PLUGIN_DIR)
	discover()
	for m in manifests:
		if is_enabled_in_settings(m.id):
			enable(m.id)


func search_dirs() -> PackedStringArray:
	var dirs := PackedStringArray([USER_PLUGIN_DIR])
	if AppConfig.has_cli("plugins-dir"):
		dirs.append(AppConfig.cli("plugins-dir"))
	return dirs


func discover() -> void:
	manifests.clear()
	for base in search_dirs():
		for sub in DirAccess.get_directories_at(base):
			var m := PluginManifest.load_from_dir(base.path_join(sub))
			if not m.is_valid():
				push_warning("Plugin '%s' not loadable: %s" % [m.id, m.error])
			manifests.append(m)


func is_enabled_in_settings(id: String) -> bool:
	var enabled: Array = AppConfig.get_setting("plugins", "enabled", [])
	return id in enabled or id in AppConfig.cli("enable-plugins").split(",", false)


func is_active(id: String) -> bool:
	return _active.has(id)


func get_manifest(id: String) -> PluginManifest:
	for m in manifests:
		if m.id == id:
			return m
	return null


func enable(id: String) -> bool:
	if _active.has(id):
		return true
	var m := get_manifest(id)
	if m == null or not m.is_valid():
		return false
	var script: Variant = load(m.dir.path_join(m.entry))
	if not script is GDScript:
		m.error = "entry script failed to load"
		return false
	var instance: Variant = script.new()
	if not instance is ClientPlugin:
		m.error = "entry script must extend ClientPlugin"
		if instance is Node:
			instance.free()
		return false
	var plugin: ClientPlugin = instance
	plugin.name = id
	plugin.api = PluginAPI.new(m)
	add_child(plugin)
	_active[id] = plugin
	plugin._plugin_enable()
	print("Plugin enabled: %s %s" % [m.id, m.version])
	return true


func disable(id: String) -> void:
	var plugin: ClientPlugin = _active.get(id)
	if plugin == null:
		return
	plugin._plugin_disable()
	plugin.api._disconnect_all()
	for p in _panels.filter(func(entry: Dictionary) -> bool: return entry["plugin_id"] == id):
		var control: Control = p["control"]
		if is_instance_valid(control):
			control.queue_free()
		_panels.erase(p)
	_active.erase(id)
	plugin.queue_free()


func register_panel(plugin_id: String, slot: StringName, control: Control) -> void:
	_panels.append({"plugin_id": plugin_id, "slot": slot, "control": control})
	EventBus.plugin_panel_added.emit(plugin_id, slot, control)


func get_panels(slot: StringName) -> Array[Control]:
	var result: Array[Control] = []
	for p in _panels:
		if p["slot"] == slot and is_instance_valid(p["control"]):
			result.append(p["control"])
	return result
