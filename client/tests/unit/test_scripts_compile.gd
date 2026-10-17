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


## Every scene under res://src/ui/screens really goes into the tree, so errors in _ready()
## (reported by the runner as engine errors) fail the test.
func test_screens_instantiate() -> void:
	var scenes := _files("res://src/ui/screens", "tscn")
	assert_true(scenes.size() >= 4, "found screens")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for path in scenes:
		var scene: PackedScene = load(path)
		var screen: Node = scene.instantiate() if scene != null else null
		assert_true(screen != null, path)
		if screen == null:
			continue
		root.add_child(screen)
		assert_true(screen.is_node_ready(), path + " ready")
		screen.free()


## The example plugins load from an absolute path at runtime (--plugins-dir), like here.
func test_example_plugins_compile() -> void:
	var plugins_dir := ProjectSettings.globalize_path("res://").path_join("../plugins").simplify_path()
	var dirs := DirAccess.get_directories_at(plugins_dir)
	assert_true(dirs.size() >= 2, "found plugins in " + plugins_dir)
	for sub in dirs:
		var manifest := PluginManifest.load_from_dir(plugins_dir.path_join(sub))
		assert_true(manifest.is_valid(), "%s manifest: %s" % [sub, manifest.error])
		if not manifest.is_valid():
			continue
		var path := manifest.dir.path_join(manifest.entry)
		var script: Script = load(path)
		assert_true(script != null and script.can_instantiate(), path)
		assert_true(_extends_client_plugin(script), path + " extends ClientPlugin")


func _extends_client_plugin(script: Script) -> bool:
	while script != null:
		if script == ClientPlugin:
			return true
		script = script.get_base_script()
	return false
