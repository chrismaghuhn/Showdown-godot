extends "res://tests/test_case.gd"
## Loads every script under res://src so parse/compile errors anywhere fail the test run
## (the runner turns engine errors into failures), and instantiates every screen scene.


func _scripts(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir.path_join(sub)))
	return found


func test_all_scripts_compile() -> void:
	var scripts := _scripts("res://src")
	assert_true(scripts.size() > 30, "found scripts")
	for path in scripts:
		var script: Script = load(path)
		assert_true(script != null and script.can_instantiate(), path)


func test_screens_instantiate() -> void:
	for path in ["res://src/ui/screens/battle/battle_screen.tscn", "res://src/ui/screens/theme_gallery/theme_gallery.tscn",
			"res://src/ui/screens/dev_console/dev_console.tscn"]:
		var scene: PackedScene = load(path)
		assert_true(scene != null and scene.can_instantiate(), path)
