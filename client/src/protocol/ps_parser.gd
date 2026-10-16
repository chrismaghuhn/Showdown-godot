class_name PSParser
extends RefCounted
## Turns raw websocket frames from the Showdown server into PSMessage objects.
##
## Protocol reference: PROTOCOL.md and sim/SIM-PROTOCOL.md in smogon/pokemon-showdown.
## Pure and static: safe to use from tests, tools and plugins.

## Message types whose last argument may itself contain "|" characters.
## Value = number of arguments; everything after the last split stays in the final argument.
const MAX_ARGS := {
	"c": 2,
	"chat": 2,
	"c:": 3,
	"pm": 3,
	"raw": 1,
	"html": 1,
	"uhtml": 2,
	"uhtmlchange": 2,
	"popup": 1,
	"error": 1,
	"bigerror": 1,
	"challstr": 1,
	"request": 1,
	"queryresponse": 2,
	"updatesearch": 1,
	"updatechallenges": 1,
}

## Battle message types that may carry `[key] value` kwargs (besides every "-minor" message).
const KWARG_TYPES := ["move", "switch", "drag", "replace", "detailschange", "cant", "faint"]


## Parses a full websocket frame. A frame may start with `>ROOMID` and contains one message per line.
static func parse_frame(data: String) -> Array[PSMessage]:
	var result: Array[PSMessage] = []
	var lines := data.split("\n")
	var room_id := ""
	var start := 0
	if lines.size() > 0 and lines[0].begins_with(">"):
		room_id = lines[0].substr(1).strip_edges()
		start = 1
	for i in range(start, lines.size()):
		var line := lines[i]
		if line.is_empty():
			continue
		result.append(parse_line(room_id, line))
	return result


static func parse_line(room_id: String, line: String) -> PSMessage:
	var msg := PSMessage.new()
	msg.room_id = room_id
	msg.raw = line

	if not line.begins_with("|"):
		msg.type = "text"
		msg.args = PackedStringArray([line])
		return msg

	var body := line.substr(1)
	var type_end := body.find("|")
	if type_end == -1:
		msg.type = body
		return msg

	msg.type = body.substr(0, type_end)
	var rest := body.substr(type_end + 1)

	# `||text` is a plain log line.
	if msg.type.is_empty():
		msg.type = "text"
		msg.args = PackedStringArray([rest])
		return msg

	var max_args: int = MAX_ARGS.get(msg.type, 0)
	if max_args == 1:
		msg.args = PackedStringArray([rest])
	elif max_args > 1:
		msg.args = rest.split("|", true, max_args - 1)
	else:
		msg.args = rest.split("|", true)

	if msg.type.begins_with("-") or msg.type in KWARG_TYPES:
		_extract_kwargs(msg)
	return msg


static func _extract_kwargs(msg: PSMessage) -> void:
	var positional := PackedStringArray()
	for a in msg.args:
		var close := a.find("]")
		if a.begins_with("[") and close > 1:
			msg.kwargs[a.substr(1, close - 1)] = a.substr(close + 1).strip_edges()
		else:
			positional.append(a)
	msg.args = positional


## Showdown's toID(): lowercase, only a-z and 0-9.
static func to_id(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out
