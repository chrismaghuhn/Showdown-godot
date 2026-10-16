class_name PSMessage
extends RefCounted
## One parsed line of the Showdown server protocol, e.g. `|move|p1a: Pikachu|Thunderbolt|p2a: Mew`.
##
## Pure data: no dependencies on network, UI or autoloads.

## Room the line belongs to ("" = global / lobby).
var room_id := ""
## Message type without pipes, e.g. "move", "-damage", "c", "challstr". Plain log lines use "text".
var type := ""
## Positional arguments after the type.
var args := PackedStringArray()
## Battle "kwargs" such as `[from] item: Leftovers` -> {"from": "item: Leftovers"}.
var kwargs := {}
## The original line, for debugging and raw logs.
var raw := ""


func arg(index: int, default := "") -> String:
	return args[index] if index < args.size() else default


func _to_string() -> String:
	return "PSMessage(%s, %s, %s)" % [room_id, type, args]
