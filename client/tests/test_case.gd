extends RefCounted
## Minimal base for unit tests (no external test framework needed).
## Test files live in tests/unit/test_*.gd, extend this script and define test_* methods.

var failures: Array[String] = []


func assert_eq(actual: Variant, expected: Variant, label := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s expected %s, got %s" % [label, var_to_str(expected), var_to_str(actual)])


func assert_true(condition: bool, label := "") -> void:
	if not condition:
		failures.append("%s expected true" % label)
