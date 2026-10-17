extends "res://tests/test_case.gd"
## Plugin manifests (plugin.json) and discovery, on fixture plugins under user://.

const ROOT := "user://test-plugin-manifest"


## Writes ROOT/<base>/<folder>/ with a plugin.json (a Dictionary is merged into a valid
## manifest, a String is written as is) and the given script files. Returns the folder.
func _plugin(base: String, folder: String, data: Variant, files := PackedStringArray(["main.gd"])) -> String:
	var dir := ROOT.path_join(base).path_join(folder)
	DirAccess.make_dir_recursive_absolute(dir)
	var manifest := {"id": folder, "name": folder, "version": "1.0.0", "api_version": PluginAPI.VERSION,
		"entry": "main.gd", "permissions": ["ui"]}
	if data is Dictionary:
		manifest.merge(data, true)
	_write(dir.path_join("plugin.json"), data if data is String else JSON.stringify(manifest))
	for file in files:
		DirAccess.make_dir_recursive_absolute(dir.path_join(file).get_base_dir())
		_write(dir.path_join(file), "extends ClientPlugin\n")
	return dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _is_invalid(m: PluginManifest) -> bool:
	return m != null and not m.is_valid()


func test_wrong_json_types_are_invalid() -> void:
	_remove(ROOT)
	var cases := {
		"api-null": {"api_version": null},
		"api-text": {"api_version": "1"},
		"perm-text": {"permissions": "ui"},
		"perm-number": {"permissions": [1]},
		"entry-null": {"entry": null},
		"entry-number": {"entry": 5},
	}
	for folder: String in cases:
		var m := PluginManifest.load_from_dir(_plugin("types", folder, cases[folder]))
		assert_true(_is_invalid(m), folder)
	_remove(ROOT)


func test_discovery_continues_past_bad_manifest() -> void:
	_remove(ROOT)
	_plugin("discover", "a-bad", {"api_version": null})
	_plugin("discover", "b-good", {})
	_plugin("discover", "c-bad", {"permissions": "ui"})
	_plugin("discover", "d-good", {})
	var found := PluginManifest.load_all(PackedStringArray([ROOT.path_join("discover")]))
	_remove(ROOT)
	var valid := PackedStringArray()
	var invalid := PackedStringArray()
	for m in found:
		if m != null:
			(valid if m.is_valid() else invalid).append(m.id)
	assert_eq(valid, PackedStringArray(["b-good", "d-good"]), "plugins after a bad one are found")
	assert_eq(invalid, PackedStringArray(["a-bad", "c-bad"]), "bad plugins are listed as invalid")


func test_entry_must_stay_in_plugin_folder() -> void:
	_remove(ROOT)
	_plugin("entry", "other", {})
	var other_main := ProjectSettings.globalize_path(ROOT.path_join("entry/other/main.gd"))
	var bad_entries := ["../other/main.gd", "lib/../../other/main.gd", other_main, "user://test-plugin-manifest/entry/other/main.gd",
		"main.txt", "main", ""]
	for i in bad_entries.size():
		var m := PluginManifest.load_from_dir(_plugin("entry", "bad-%d" % i, {"entry": bad_entries[i]},
			PackedStringArray(["main.gd", "main.txt", "main"])))
		assert_true(_is_invalid(m) and m.error.contains("entry"), "rejects '%s'" % bad_entries[i])
	var nested := PluginManifest.load_from_dir(_plugin("entry", "nested", {"entry": "lib/main.gd"}, PackedStringArray(["lib/main.gd"])))
	assert_true(nested.is_valid(), "entry in a subfolder: " + nested.error)
	_remove(ROOT)


func test_duplicate_ids_are_flagged() -> void:
	_remove(ROOT)
	_plugin("installed", "battle-x", {})
	_plugin("dev", "battle-x", {})
	_plugin("dev", "battle-y", {})
	var found := PluginManifest.load_all(PackedStringArray([ROOT.path_join("installed"), ROOT.path_join("dev")]))
	_remove(ROOT)
	assert_eq(found.size(), 3, "all listed")
	assert_true(found[0].is_valid(), "first copy loads")
	assert_true(_is_invalid(found[1]) and found[1].error.contains("duplicate"), "second copy flagged")
	assert_true(found[2].is_valid(), "other plugins unaffected")


func test_id_must_match_folder_name() -> void:
	_remove(ROOT)
	var m := PluginManifest.load_from_dir(_plugin("folders", "battle-x", {"id": "battle-y"}))
	_remove(ROOT)
	assert_true(_is_invalid(m) and m.error.contains("folder"), "id differs from its folder")
	var examples := ProjectSettings.globalize_path("res://").path_join("../plugins").simplify_path()
	var found := PluginManifest.load_all(PackedStringArray([examples]))
	assert_true(found.size() >= 2, "example plugins found")
	for example in found:
		assert_true(example.is_valid(), "%s: %s" % [example.id, example.error])
