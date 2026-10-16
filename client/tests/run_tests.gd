extends SceneTree
## Headless test runner: godot --headless --path client -s res://tests/run_tests.gd
## (or simply tools/run_tests.sh). Exit code 1 if any test fails.
##
## Any engine or script error while a test runs fails that test (runtime errors in GDScript
## only abort the function, so assertions alone would miss them). Tests start on the first
## frame, after the autoloads are ready; errors during startup are reported as a failure too.

const UNIT_DIR := "res://tests/unit"


class ErrorCollector extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		errors.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var result := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return result


var _collector := ErrorCollector.new()
var _done := false


func _init() -> void:
	OS.add_logger(_collector)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var total := 0
	var failed := 0

	var startup_errors := _collector.take()
	if not startup_errors.is_empty():
		total += 1
		failed += 1
		_report("startup", "autoloads", startup_errors)

	for file in DirAccess.get_files_at(UNIT_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(UNIT_DIR.path_join(file))
		var load_errors := _collector.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			total += 1
			failed += 1
			_report(file, "could not load", load_errors)
			continue
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			total += 1
			var test: Variant = script.new()
			test.call(test_name)
			var problems: Array[String] = []
			problems.append_array(test.failures)
			for e in _collector.take():
				problems.append("engine error: " + e)
			if problems.is_empty():
				print("  ok    %s :: %s" % [file, test_name])
			else:
				failed += 1
				_report(file, test_name, problems)
	print("\n%d tests, %d failed" % [total, failed])
	OS.remove_logger(_collector)
	quit(1 if failed > 0 or total == 0 else 0)
	return false


func _report(file: String, test_name: String, problems: Array[String]) -> void:
	print("  FAIL  %s :: %s" % [file, test_name])
	for p in problems:
		print("        " + p)
