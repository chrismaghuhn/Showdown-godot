class_name Icons
extends RefCounted
## The design system's icons (client/assets/icons/*.svg): 16px grid, drawn white, tinted by the
## theme (Button icon colors) or by IconView. Imported at 2x so they stay sharp up to 200 % UI
## scale; always displayed at 16 logical px. Pair every icon with a text label or tooltip.

const DIR := "res://assets/icons"
const SIZE := 16

static var _cache := {}


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


## All icon names, sorted.
static func names() -> PackedStringArray:
	var result := PackedStringArray()
	for file in ResourceLoader.list_directory(DIR):
		if file.ends_with(".svg"):
			result.append(file.trim_suffix(".svg"))
	result.sort()
	return result
