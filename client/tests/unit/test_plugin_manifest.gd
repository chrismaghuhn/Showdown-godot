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
		"api-bool": {"api_version": true},
		"api-fraction": {"api_version": PluginAPI.VERSION + 0.5},
		"api-object": {"api_version": {"v": 1}},
		"perm-text": {"permissions": "ui"},
		"perm-null": {"permissions": null},
		"perm-number": {"permissions": [1]},
		"perm-nested": {"permissions": [["ui"]]},
		"perm-object": {"permissions": {"ui": true}},
		"entry-null": {"entry": null},
		"entry-number": {"entry": 5},
	}
	for folder: String in cases:
		var m := PluginManifest.load_from_dir(_plugin("types", folder, cases[folder]))
		var field: String = cases[folder].keys()[0]
		assert_true(_is_invalid(m) and m.error.contains("\"%s\"" % field), "%s: %s" % [folder, m.error if m != null else "null"])
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
		"main.txt", "main", "", "C:/x.gd", "res://x.gd", "lib\\main.gd", "..\\x.gd"]
	for i in bad_entries.size():
		var m := PluginManifest.load_from_dir(_plugin("entry", "bad-%d" % i, {"entry": bad_entries[i]},
			PackedStringArray(["main.gd", "main.txt", "main"])))
		assert_true(_is_invalid(m) and m.error.contains("inside the plugin folder"), "rejects '%s'" % bad_entries[i])
	for entry: String in ["./main.gd", "src/main.gd"]:
		var m := PluginManifest.load_from_dir(_plugin("entry", "good-" + entry.get_base_dir().trim_prefix("."),
			{"entry": entry}, PackedStringArray([entry])))
		assert_true(m.is_valid(), "%s: %s" % [entry, m.error])
	_remove(ROOT)


func test_entry_path_checks() -> void:
	assert_true(PluginManifest.is_entry_inside("C:\\a\\foo", "main.gd"), "Windows folder with backslashes")
	assert_true(PluginManifest.is_entry_inside("C:/a/foo/", "lib/main.gd"), "trailing slash, subfolder")
	assert_true(PluginManifest.is_entry_inside("user://plugins/foo", "./main.gd"), "dot segment")
	assert_true(PluginManifest.is_entry_inside("/home/x/../plugins/foo", "main.gd"), "folder with ..")
	assert_true(not PluginManifest.is_entry_inside("user://plugins/foo", "../foo-extra/main.gd"), "sibling folder")
	assert_true(not PluginManifest.is_entry_inside("C:\\a\\foo", "..\\bar\\main.gd"), "backslash escape")
	assert_true(not PluginManifest.is_entry_inside("user://plugins/foo", "main.gd.txt"), "not a script")


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


func test_broken_copy_does_not_block_a_loadable_duplicate() -> void:
	_remove(ROOT)
	_plugin("installed", "battle-x", {"api_version": PluginAPI.VERSION - 1})
	_plugin("dev", "battle-x", {})
	var found := PluginManifest.load_all(PackedStringArray([ROOT.path_join("installed"), ROOT.path_join("dev")]))
	_remove(ROOT)
	assert_true(_is_invalid(found[0]) and found[0].error.contains("API"), "old copy keeps its own error")
	assert_true(found[1].is_valid(), "loadable copy is not a duplicate: " + found[1].error)
	var saved := Plugins.manifests
	Plugins.manifests = found
	var picked := Plugins.get_manifest("battle-x")
	Plugins.manifests = saved
	assert_true(picked == found[1], "the loadable copy is the one that gets enabled")


func test_id_must_match_folder_name() -> void:
	_remove(ROOT)
	var m := PluginManifest.load_from_dir(_plugin("folders", "battle-x", {"id": "battle-y"}))
	_remove(ROOT)
	assert_true(_is_invalid(m) and m.error.contains("folder name"), "id differs from its folder")
	var examples := ProjectSettings.globalize_path("res://").path_join("../plugins").simplify_path()
	var found := PluginManifest.load_all(PackedStringArray([examples]))
	assert_true(found.size() >= 2, "example plugins found")
	for example in found:
		assert_true(example.is_valid(), "%s: %s" % [example.id, example.error])
