extends "res://tests/test_case.gd"
## Loads every script under res://src so parse/compile errors anywhere fail the test run
## (the runner turns engine errors into failures), instantiates every screen scene and
## compiles the repo's example plugins (plugins/*/, outside the Godot project).


func _files(dir: String, extension: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir.path_join(sub), extension))
	return found


func test_all_scripts_compile() -> void:
	var scripts := _files("res://src", "gd")
	assert_true(scripts.size() > 30, "found scripts")
	for path in scripts:
		var script: Script = load(path)
		assert_true(script != null and script.can_instantiate(), path)


## Every screen under res://src/ui/screens really goes into the tree, so errors in _ready()
## (reported by the runner as engine errors) fail the test: each .tscn, plus each .gd that
## isn't a scene's script but a Node created with .new() (e.g. class_name screens).
## The runner calls every test within one frame, so work that _ready() hands off
## (call_deferred, await, Timer timeouts) never runs here and isn't covered.
func test_screens_instantiate() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var checked := PackedStringArray()
	for path in _files("res://src/ui/screens", "tscn"):
		var scene: PackedScene = load(path)
		assert_true(scene != null and scene.can_instantiate(), path)
		if scene != null and scene.can_instantiate():
			var screen := scene.instantiate()
			var script: Script = screen.get_script()
			if script != null:
				checked.append(script.resource_path)
			_check_screen(root, screen, path)
	var scene_count := checked.size()
	for path in _files("res://src/ui/screens", "gd"):
		if path in checked:
			continue
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate() or _needs_init_args(script) \
				or not ClassDB.is_parent_class(script.get_instance_base_type(), &"Node"):
			continue
		checked.append(path)
		_check_screen(root, script.new(), path)
	assert_true(scene_count >= 4 and checked.size() >= scene_count, "found screens")


func _check_screen(root: Node, screen: Node, path: String) -> void:
	root.add_child(screen)
	assert_true(screen.get_child_count() > 0, path + " has content after _ready()")
	screen.free()


func _needs_init_args(script: GDScript) -> bool:
	for method in script.get_script_method_list():
		if method["name"] == "_init":
			return (method["args"] as Array).size() > (method["default_args"] as Array).size()
	return false


## The example plugins load from an absolute path at runtime (--plugins-dir), like here, and
## are enabled through the PluginManager so _plugin_enable() runs against the real PluginAPI
## (a method PluginAPI doesn't have is only a runtime error). Enabling them here isn't saved
## to the settings, and disabling them leaves nothing behind.
func test_example_plugins_load_and_enable() -> void:
	var plugins_dir := ProjectSettings.globalize_path("res://").path_join("../plugins").simplify_path()
	var dirs := DirAccess.get_directories_at(plugins_dir)
	assert_true(dirs.size() >= 2, "found plugins in " + plugins_dir)
	var enabled_setting: Variant = AppConfig.get_setting("plugins", "enabled", [])
	var connections := _event_bus_connections()
	var plugin_nodes := Plugins.get_child_count()
	var panels := Plugins._panels.size()
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for sub in dirs:
		var manifest := PluginManifest.load_from_dir(plugins_dir.path_join(sub))
		assert_true(manifest.is_valid(), "%s manifest: %s" % [sub, manifest.error])
		if not manifest.is_valid():
			continue
		var path := manifest.dir.path_join(manifest.entry)
		var script: Script = load(path)
		assert_true(script != null and script.can_instantiate(), path)
		if script != null and script.can_instantiate():
			_enable_and_disable(manifest)
	assert_eq(AppConfig.get_setting("plugins", "enabled", []), enabled_setting, "enabled plugins setting")
	assert_eq(_event_bus_connections(), connections, "EventBus connections")
	assert_eq(Plugins.get_child_count(), plugin_nodes, "plugin nodes")
	assert_eq(Plugins._panels.size(), panels, "plugin panels")
	assert_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans, "orphan nodes")


func _enable_and_disable(manifest: PluginManifest) -> void:
	var id := manifest.id
	assert_true(not Plugins.is_active(id), id + " not active before the test")
	if Plugins.is_active(id):
		return
	Plugins.manifests.push_front(manifest)
	var first_panel := Plugins._panels.size()
	assert_true(Plugins.enable(id), "%s enables %s" % [id, manifest.error])
	var leftovers: Array = [Plugins._active.get(id)]
	for p: Dictionary in Plugins._panels.slice(first_panel):
		leftovers.append(p["control"])
	Plugins.disable(id)
	Plugins.manifests.erase(manifest)
	# disable() uses queue_free(), and all tests run within one frame: free them right away.
	for node: Variant in leftovers:
		if is_instance_valid(node):
			(node as Node).free()


func _event_bus_connections() -> int:
	var count := 0
	for s in EventBus.get_signal_list():
		count += EventBus.get_signal_connection_list(s["name"]).size()
	return count
