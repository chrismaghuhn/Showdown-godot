class_name DexMove
extends RefCounted
## One move, from Showdown's moves.json.

## Value of `accuracy` for moves that never miss (accuracy: true in the data).
const ALWAYS_HITS := -1

var id := ""
var name := ""
var num := 0
var type := ""
## "Physical", "Special" or "Status"
var category := ""
var base_power := 0
var accuracy := 100
var pp := 0
var priority := 0
var target := ""
var flags := {}
## The full original entry, for fields not mapped above.
var raw := {}


static func from_dict(move_id: String, data: Dictionary) -> DexMove:
	var m := DexMove.new()
	m.id = move_id
	m.name = str(data.get("name", move_id))
	m.num = int(data.get("num", 0))
	m.type = str(data.get("type", ""))
	m.category = str(data.get("category", ""))
	m.base_power = int(data.get("basePower", 0))
	var acc: Variant = data.get("accuracy", 100)
	m.accuracy = ALWAYS_HITS if acc is bool else int(acc)
	m.pp = int(data.get("pp", 0))
	m.priority = int(data.get("priority", 0))
	m.target = str(data.get("target", ""))
	m.flags = data.get("flags", {})
	m.raw = data
	return m
