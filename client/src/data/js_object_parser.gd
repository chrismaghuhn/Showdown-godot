class_name JsObjectParser
extends RefCounted
## Converts the JavaScript object literals Showdown serves for some data files, e.g.
## `exports.BattleItems = {abilityshield:{name:"Ability Shield",num:1881}};`, into JSON.
## Supports bare and numeric keys, double- and single-quoted strings, true/false/null,
## undefined (-> null) and numbers. Not a general JS parser: no functions or comments.


## Parses an `exports.X = {...};` file. Returns null if it cannot be parsed.
static func parse_exports(source: String) -> Variant:
	var start := source.find("{")
	var end := source.rfind("}")
	if start == -1 or end < start:
		return null
	var json := JSON.new()
	if json.parse(to_json(source.substr(start, end - start + 1))) != OK:
		return null
	return json.data


static func to_json(js: String) -> String:
	var out := PackedStringArray()
	var n := js.length()
	var i := 0
	while i < n:
		var c := js[i]
		if c == "\"":
			var j := _string_end(js, i, "\"")
			out.append(js.substr(i, j - i + 1))
			i = j + 1
		elif c == "'":
			var j := _string_end(js, i, "'")
			var inner := js.substr(i + 1, j - i - 1).replace("\\'", "'").replace("\"", "\\\"")
			out.append("\"" + inner + "\"")
			i = j + 1
		elif _is_token_char(c):
			var j := i + 1
			while j < n and _is_token_char(js[j]):
				j += 1
			var token := js.substr(i, j - i)
			var k := j
			while k < n and js[k] == " ":
				k += 1
			if k < n and js[k] == ":":
				out.append("\"" + token + "\"")
			elif token == "undefined":
				out.append("null")
			else:
				out.append(token)
			i = j
		else:
			out.append(c)
			i += 1
	return "".join(out)


static func _string_end(js: String, start: int, quote: String) -> int:
	var j := start + 1
	while j < js.length():
		if js[j] == "\\":
			j += 2
			continue
		if js[j] == quote:
			return j
		j += 1
	return js.length() - 1


## Characters of identifiers and numbers (letters, digits, _ $ . + -).
static func _is_token_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") \
		or c == "_" or c == "$" or c == "." or c == "-" or c == "+"
