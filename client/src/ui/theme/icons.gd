class_name Icons
extends RefCounted
## The design system's icons (client/assets/icons/*.svg, board "04 · Icons"): 16px grid, drawn
## white, tinted by the theme (Button icon colors) or by IconView. Imported at 2x so they stay
## sharp up to 200 % UI scale; always displayed at 16 logical px. icons.json lists each icon's
## label (for tooltips and accessibility) and group. Pair every icon with a text label or tooltip.

const DIR := "res://assets/icons"
const MANIFEST := "res://assets/icons/icons.json"
const SIZE := 16

static var _cache := {}
static var _meta := {}
static var _order := PackedStringArray()


## Texture for an icon name such as "ui-settings" or "weather-rain"; null if it doesn't exist.
static func get_icon(icon_name: String) -> Texture2D:
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := DIR.path_join(icon_name + ".svg")
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if texture == null:
		push_warning("Unknown icon '%s'" % icon_name)
	_cache[icon_name] = texture
	return texture


## Human-readable label from icons.json ("ui-close" -> "Close · KO"); the name if unknown.
static func label(icon_name: String) -> String:
	_load_manifest()
	return str(_meta.get(icon_name, {}).get("label", icon_name))


static func group(icon_name: String) -> String:
	_load_manifest()
	return str(_meta.get(icon_name, {}).get("group", ""))


## All icon names in the design's order (by group); falls back to the files on disk.
static func names() -> PackedStringArray:
	_load_manifest()
	if not _order.is_empty():
		return _order
	var result := PackedStringArray()
	for file in ResourceLoader.list_directory(DIR):
		if file.ends_with(".svg"):
			result.append(file.trim_suffix(".svg"))
	result.sort()
	return result


## Group names in the design's order.
static func groups() -> PackedStringArray:
	var result := PackedStringArray()
	for icon_name in names():
		var g := group(icon_name)
		if not g in result:
			result.append(g)
	return result


static func _load_manifest() -> void:
	if not _meta.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
	if not (data is Dictionary and data.get("icons") is Array):
		return
	for entry: Variant in data["icons"]:
		if entry is Dictionary and entry.has("name"):
			_meta[str(entry["name"])] = entry
			_order.append(str(entry["name"]))
