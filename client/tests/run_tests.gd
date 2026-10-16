extends SceneTree
## Headless test runner: godot --headless --path client -s res://tests/run_tests.gd
## (or simply tools/run_tests.sh). Exit code 1 if any test fails.

const UNIT_DIR := "res://tests/unit"


func _init() -> void:
	var total := 0
	var failed := 0
	for file in DirAccess.get_files_at(UNIT_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(UNIT_DIR.path_join(file))
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			print("  FAIL  %s :: could not load (see errors above)" % file)
			continue
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			total += 1
			var test: Variant = script.new()
			test.call(test_name)
			if test.failures.is_empty():
				print("  ok    %s :: %s" % [file, test_name])
			else:
				failed += 1
				print("  FAIL  %s :: %s" % [file, test_name])
				for f: String in test.failures:
					print("        " + f)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
