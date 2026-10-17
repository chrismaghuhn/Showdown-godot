extends "res://tests/test_case.gd"
## Regression tests for #37: trimming the stack used to loop forever, because closing toasts stay
## children until their exit fade ends. Reaching the assertions means show_toast() returned.


func _max_toasts() -> int:
	return maxi(int(Themes.tokens.num("toast.max")) if Themes.tokens != null else 3, 1)


func _open_titles(stack: ToastStack) -> Array[String]:
	var titles: Array[String] = []
	for child in stack.get_children():
		if not child.get_meta("closing", false):
			titles.append(child.get_meta("title"))
	return titles


func _show(stack: ToastStack, title: String, key := "") -> void:
	stack.show_toast({"title": title, "key": key, "persistent": true})
	stack.get_child(0).set_meta("title", title)


func test_overflow_evicts_oldest_and_returns() -> void:
	var stack := ToastStack.new()
	var count := _max_toasts() + 2
	for i in count:
		_show(stack, "toast %d" % i)
	var expected: Array[String] = []
	for i in range(count - 1, count - 1 - _max_toasts(), -1):
		expected.append("toast %d" % i)
	assert_eq(_open_titles(stack), expected, "newest toast.max stay open, newest first")
	stack.free()


func test_keyed_replacement_with_full_stack_returns() -> void:
	var stack := ToastStack.new()
	_show(stack, "keyed", "your_turn")
	for i in _max_toasts() - 1:
		_show(stack, "toast %d" % i)
	_show(stack, "keyed again", "your_turn")
	var titles := _open_titles(stack)
	assert_eq(titles.size(), _max_toasts(), "stack stays full")
	assert_eq(titles[0], "keyed again", "replacement on top")
	assert_true(not titles.has("keyed"), "old keyed toast closed")
	stack.free()
