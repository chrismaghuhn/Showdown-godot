extends Node
## Autoload "Plugins": discovers, enables and disables plugins.
##
## Search paths:
##   user://plugins/<id>/                 installed plugins (enabled via settings)
##   --plugins-dir=<absolute path>        development plugins, e.g. the repo's plugins/ folder
## Enable on the command line with --enable-plugins=id1,id2.
##
## An engine or script error raised in a plugin's own scripts pauses that plugin (it is
## switched off and EventBus.plugin_paused fires) until reload() - the battle goes on.

const USER_PLUGIN_DIR := "user://plugins"

var manifests: Array[PluginManifest] = []
## plugin id -> ClientPlugin
var _active := {}
## [{plugin_id, slot, control}] - kept so UI created later can pick up panels.
var _panels: Array[Dictionary] = []
## plugin id -> the error that paused it
var paused := {}
var _watch := PluginErrorWatch.new()


## Sees every engine error (from any thread) and hands the script paths to the manager.
class PluginErrorWatch extends Logger:
	var manager: Object

	func _log_error(_function: String, file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING or manager == null:
			return
		var paths := PackedStringArray([file])
		for backtrace in script_backtraces:
			for i in backtrace.get_frame_count():
				paths.append(backtrace.get_frame_file(i))
		manager.call_deferred("_on_engine_error", paths, rationale if not rationale.is_empty() else code)


func _ready() -> void:
	_watch.manager = self
	OS.add_logger(_watch)
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
	manifests = PluginManifest.load_all(search_dirs())
	for m in manifests:
		if not m.is_valid():
			push_warning("Plugin '%s' not loadable: %s" % [m.id, m.error])


func is_enabled_in_settings(id: String) -> bool:
	var enabled: Array = AppConfig.get_setting("plugins", "enabled", [])
	return id in enabled or id in AppConfig.cli("enable-plugins").split(",", false)


func is_active(id: String) -> bool:
	return _active.has(id)


## The loadable manifest for `id`, else the first one with that id, else null.
func get_manifest(id: String) -> PluginManifest:
	var first: PluginManifest = null
	for m in manifests:
		if m.id == id:
			if m.is_valid():
				return m
			if first == null:
				first = m
	return first


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


func _exit_tree() -> void:
	OS.remove_logger(_watch)
	_watch.manager = null


## Switches a misbehaving plugin off until reload() (design: "Damage Calc paused").
func pause(id: String, reason: String) -> void:
	if not _active.has(id):
		return
	disable(id)
	paused[id] = reason
	print("Plugin paused: %s (%s)" % [id, reason])
	EventBus.plugin_paused.emit(id, reason)


## Turns a paused plugin on again.
func reload(id: String) -> bool:
	paused.erase(id)
	return enable(id)


## Keeps a plugin off, also after restarts.
func set_enabled_in_settings(id: String, enabled: bool) -> void:
	var list: Array = (AppConfig.get_setting("plugins", "enabled", []) as Array).duplicate()
	list.erase(id)
	if enabled:
		list.append(id)
	AppConfig.set_setting("plugins", "enabled", list)
	if not enabled:
		paused.erase(id)


func _on_engine_error(paths: PackedStringArray, reason: String) -> void:
	var id := plugin_for_paths(paths)
	if not id.is_empty():
		pause(id, reason)


## The active plugin whose folder contains one of these script paths, or "".
func plugin_for_paths(paths: PackedStringArray) -> String:
	for id: String in _active.keys():
		var m := get_manifest(id)
		if m == null:
			continue
		for path in paths:
			if is_inside(path, m.dir):
				return id
	return ""


## True if `path` lies inside the folder `dir` (res://, user:// or absolute). The trailing
## slash keeps plugin "foo" from matching "foo-extra".
static func is_inside(path: String, dir: String) -> bool:
	if path.is_empty() or dir.is_empty():
		return false
	if path.begins_with(dir.trim_suffix("/") + "/"):
		return true
	var folder := ProjectSettings.globalize_path(dir).trim_suffix("/") + "/"
	return ProjectSettings.globalize_path(path).begins_with(folder)


func register_panel(plugin_id: String, slot: StringName, control: Control) -> void:
	_panels.append({"plugin_id": plugin_id, "slot": slot, "control": control})
	EventBus.plugin_panel_added.emit(plugin_id, slot, control)


## [{plugin_id, control}] for a slot, in registration order.
func get_panel_entries(slot: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in _panels:
		if p["slot"] == slot and is_instance_valid(p["control"]):
			result.append({"plugin_id": p["plugin_id"], "control": p["control"]})
	return result


func get_panels(slot: StringName) -> Array[Control]:
	var result: Array[Control] = []
	for p in _panels:
		if p["slot"] == slot and is_instance_valid(p["control"]):
			result.append(p["control"])
	return result
