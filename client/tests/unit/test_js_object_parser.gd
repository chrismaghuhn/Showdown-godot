extends "res://tests/test_case.gd"


func test_bare_keys_nested_values() -> void:
	var data: Variant = JsObjectParser.parse_exports(
		"exports.BattleItems = {abc:{name:\"A\",num:1,flag:true,list:[\"a\",\"b\"]},d2:{x:-1.5,off:false}};")
	assert_true(data is Dictionary, "parsed")
	assert_eq(data["abc"]["name"], "A", "string value")
	assert_eq(data["abc"]["num"], 1.0, "number value")
	assert_eq(data["abc"]["flag"], true, "bool value")
	assert_eq(data["abc"]["list"], ["a", "b"], "array value")
	assert_eq(data["d2"]["x"], -1.5, "negative float")
	assert_eq(data["d2"]["off"], false, "false value")


func test_strings_with_special_characters_are_untouched() -> void:
	var data: Variant = JsObjectParser.parse_exports("{a:\"x: y, {z}\",b:\"say \\\"hi\\\"\"}")
	assert_eq(data["a"], "x: y, {z}", "colon, comma and braces in string")
	assert_eq(data["b"], "say \"hi\"", "escaped quotes")


func test_numeric_keys_single_quotes_and_undefined() -> void:
	var data: Variant = JsObjectParser.parse_exports("{0:'it\\'s',H:\"Hidden\",u:undefined}")
	assert_eq(data["0"], "it's", "numeric key + single quoted string")
	assert_eq(data["H"], "Hidden", "single letter key")
	assert_eq(data["u"], null, "undefined becomes null")


func test_invalid_input_returns_null() -> void:
	assert_eq(JsObjectParser.parse_exports("not an object"), null, "no braces")
	assert_eq(JsObjectParser.parse_exports("{a:}"), null, "broken object")


func test_real_typechart_file() -> void:
	var data: Variant = JsObjectParser.parse_exports(FileAccess.get_file_as_string("res://tests/fixtures/typechart.js"))
	assert_true(data is Dictionary, "parsed")
	assert_true(data.has("dragon") and data.has("fairy"), "has types")
	assert_eq(data["dragon"]["damageTaken"]["Fairy"], 1.0, "dragon weak to fairy")
