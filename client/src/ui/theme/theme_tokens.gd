class_name ThemeTokens
extends RefCounted
## A resolved set of design tokens ("color.surface.panel", "space.md", ...) for one theme.
##
## Themes are `.sdtheme.json` files that contain ONLY token values: no scripts, no layout.
##   {"format": 1, "name": "Sandstorm", "author": "...", "extends": "midnight-dark",
##    "tokens": {"color.surface.app": "#15120E", ...}}
## The base theme defines which keys exist and their types; other themes override a subset.
## Invalid or unknown values are ignored with a warning, so a broken community theme can never
## break the client. Pure: no file access, no autoloads.

const FORMAT := 1
const MAX_FILE_BYTES := 64 * 1024
const MAX_EXTENDS_DEPTH := 8
const MAX_STRING_LENGTH := 64

## [foreground token, background token, minimum contrast]. WCAG: 4.5 for text, 3 for controls.
const CONTRAST_PAIRS := [
	["color.text.primary", "color.surface.app", 4.5],
	["color.text.primary", "color.surface.panel", 4.5],
	["color.text.primary", "color.surface.raised", 4.5],
	["color.text.secondary", "color.surface.panel", 4.5],
	["color.text.muted", "color.surface.panel", 4.5],
	["color.text.on-accent", "color.accent.default", 4.5],
	["color.accent.text", "color.surface.panel", 4.5],
	["color.danger.text", "color.surface.panel", 4.5],
	["color.success.text", "color.surface.panel", 4.5],
	["color.warning.text", "color.surface.panel", 4.5],
	["color.plugin.text", "color.surface.panel", 4.5],
	["color.boost.up.fg", "color.boost.up.bg", 4.5],
	["color.boost.down.fg", "color.boost.down.bg", 4.5],
	["color.border.control", "color.surface.panel", 3.0],
	["color.focus.ring", "color.surface.panel", 3.0],
]

const TYPES := ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
	"flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
const STATUSES := ["brn", "par", "slp", "frz", "psn", "tox"]

var id := ""
var name := ""
var author := ""
## Token key -> Color, float or String.
var values := {}
## Problems found while loading (ignored keys, failed contrast pairs, ...).
var warnings := PackedStringArray()


## Parses the text of one .sdtheme.json file. Returns {"ok": bool, "error": String,
## "name", "author", "extends", "tokens": Dictionary (raw values)}.
static func parse_definition(theme_id: String, text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return {"ok": false, "error": "theme file is larger than %d KB" % (MAX_FILE_BYTES / 1024)}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"ok": false, "error": "not valid JSON"}
	var data: Dictionary = json.data
	var format: Variant = data.get("format", 0)
	if not (format is float or format is int) or format != FORMAT:
		return {"ok": false, "error": "unsupported format (expected %d)" % FORMAT}
	if not data.get("tokens") is Dictionary:
		return {"ok": false, "error": "\"tokens\" must be an object"}
	return {
		"ok": true,
		"error": "",
		"name": str(data.get("name", theme_id)).left(MAX_STRING_LENGTH),
		"author": str(data.get("author", "")).left(MAX_STRING_LENGTH),
		"extends": str(data.get("extends", "")),
		"tokens": data["tokens"],
	}


## Resolves a theme with its `extends` chain. `definitions` maps theme id -> parse_definition()
## result; `base_id` is the theme that defines all keys (and the implicit parent).
## Returns null if the theme or the base cannot be resolved.
static func resolve(theme_id: String, definitions: Dictionary, base_id: String) -> ThemeTokens:
	var base: Dictionary = definitions.get(base_id, {})
	var definition: Dictionary = definitions.get(theme_id, {})
	if not base.get("ok", false) or not definition.get("ok", false):
		return null

	var schema := {}
	var result := ThemeTokens.new()
	for key: String in base["tokens"]:
		var value: Variant = _convert(base["tokens"][key], null)
		if value == null:
			result.warnings.append("base theme: invalid value for %s" % key)
			continue
		schema[key] = typeof(value)
		result.values[key] = value

	# Collect the chain child -> ... -> base, then apply it from the base outwards.
	var chain: Array[String] = []
	var current := theme_id
	while current != base_id:
		if current in chain:
			result.warnings.append("extends cycle at '%s', using '%s'" % [current, base_id])
			break
		if chain.size() >= MAX_EXTENDS_DEPTH:
			result.warnings.append("extends chain too long, using '%s'" % base_id)
			break
		var entry: Dictionary = definitions.get(current, {})
		if not entry.get("ok", false):
			result.warnings.append("theme '%s' not found or invalid, using '%s'" % [current, base_id])
			break
		chain.append(current)
		current = entry["extends"] if not str(entry["extends"]).is_empty() else base_id
	chain.reverse()

	for theme_in_chain in chain:
		var tokens: Dictionary = definitions[theme_in_chain]["tokens"]
		for key: Variant in tokens:
			if not key is String or not schema.has(key):
				result.warnings.append("%s: unknown token '%s' ignored" % [theme_in_chain, key])
				continue
			var value: Variant = _convert(tokens[key], key)
			if value == null or typeof(value) != schema[key]:
				result.warnings.append("%s: invalid value for '%s' ignored" % [theme_in_chain, key])
				continue
			result.values[key] = value

	result.id = theme_id
	result.name = definition["name"]
	result.author = definition["author"]
	result.warnings.append_array(result.check_contrast())
	return result


func color(key: String) -> Color:
	var value: Variant = values.get(key)
	return value if value is Color else Color.MAGENTA


func num(key: String) -> float:
	var value: Variant = values.get(key)
	return value if value is float else 0.0


func px(key: String) -> int:
	return roundi(num(key))


func text(key: String) -> String:
	var value: Variant = values.get(key)
	return value if value is String else ""


## Returns a warning for every token pair below its minimum contrast.
func check_contrast() -> PackedStringArray:
	var pairs: Array = CONTRAST_PAIRS.duplicate()
	for type_id in TYPES:
		pairs.append(["color.type.%s.fg" % type_id, "color.type.%s.bg" % type_id, 4.5])
	for status in STATUSES:
		pairs.append(["color.status.%s.fg" % status, "color.status.%s.bg" % status, 4.5])
	var problems := PackedStringArray()
	for pair: Array in pairs:
		if not (values.has(pair[0]) and values.has(pair[1])):
			continue
		# A translucent foreground is seen blended over its background.
		var ratio := contrast_ratio(color(pair[1]).blend(color(pair[0])), color(pair[1]))
		if ratio < pair[2]:
			problems.append("low contrast %.2f:1 (needs %.1f) for %s on %s" % [ratio, pair[2], pair[0], pair[1]])
	return problems


## WCAG 2 contrast ratio between two opaque colors (1 - 21).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var channels := [c.r, c.g, c.b]
	for i in 3:
		var v: float = channels[i]
		channels[i] = v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


## Converts a raw JSON value into Color, float or String; null if invalid. With a key,
## numbers are range-checked by token family.
static func _convert(raw: Variant, key: Variant) -> Variant:
	if raw is String:
		var s: String = raw
		if s.begins_with("#"):
			var hex := s.substr(1)
			# Not is_valid_hex_number(): that also accepts a leading + or -.
			if (hex.length() == 6 or hex.length() == 8) and Color.html_is_valid(hex):
				return Color.html(s)
			return null
		return s if s.length() <= MAX_STRING_LENGTH else null
	if raw is float or raw is int:
		var n := float(raw)
		if key is String and not _in_range(key, n):
			return null
		return n
	return null


static func _in_range(key: String, n: float) -> bool:
	if key.begins_with("mix."):
		return n >= 0.0 and n <= 1.0
	if key.begins_with("border.width"):
		return n >= 0.0 and n <= 8.0
	if key.begins_with("font.size"):
		return n >= 6.0 and n <= 96.0
	if key.begins_with("motion."):
		return n >= 0.0 and n <= 5.0
	return n >= 0.0 and n <= 1000.0
