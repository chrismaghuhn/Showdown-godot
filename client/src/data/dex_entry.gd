class_name DexEntry
extends RefCounted
## A simple named dex entry: used for items and abilities.

var id := ""
var name := ""
var num := 0
## The full original entry (e.g. items have "spritenum", "megaStone", "fling").
var raw := {}


static func from_dict(entry_id: String, data: Dictionary) -> DexEntry:
	var e := DexEntry.new()
	e.id = entry_id
	e.name = str(data.get("name", entry_id))
	e.num = int(data.get("num", 0))
	e.raw = data
	return e
