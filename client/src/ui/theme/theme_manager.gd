extends Node
## Autoload "Themes": discovers themes, applies one at runtime and handles UI scaling.
##
## Themes:  res://assets/themes/*.sdtheme.json (built in) and user://themes/*.sdtheme.json
##          (community). Settings: section "appearance", keys "theme" and "ui_scale".
## Command line: --theme=<id> and --ui-scale=<0.75-1.5> override the settings for one run.

const BUILTIN_DIR := "res://assets/themes"
const USER_DIR := "user://themes"
const BASE_THEME := "midnight-dark"
const DEFAULT_THEME := "midnight-dark"
const SCALE_MIN := 0.75
const SCALE_MAX := 1.5
const SCALE_STEP := 0.05

## theme id -> ThemeTokens.parse_definition() result plus "builtin" and "path"
var definitions := {}
var tokens: ThemeTokens
var theme: Theme
var theme_id := ""
var ui_scale := 1.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	discover()
	var wanted := AppConfig.cli("theme", str(AppConfig.get_setting("appearance", "theme", DEFAULT_THEME)))
	if not apply(wanted, false):
		apply(DEFAULT_THEME, false)
	var scale_text := AppConfig.cli("ui-scale", str(AppConfig.get_setting("appearance", "ui_scale", 1.0)))
	set_ui_scale(scale_text.to_float() if scale_text.is_valid_float() else 1.0, false)
	get_tree().root.size_changed.connect(_apply_scale)


func discover() -> void:
	definitions.clear()
	for dir_and_flag: Array in [[BUILTIN_DIR, true], [USER_DIR, false]]:
		var dir: String = dir_and_flag[0]
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".sdtheme.json"):
				continue
			var id := file.trim_suffix(".sdtheme.json")
			if definitions.has(id) and definitions[id]["builtin"]:
				push_warning("Theme '%s' in %s ignored: a built-in theme has that id" % [id, dir])
				continue
			var path := dir.path_join(file)
			var definition := ThemeTokens.parse_definition(id, FileAccess.get_file_as_string(path))
			definition["builtin"] = dir_and_flag[1]
			definition["path"] = path
			if not definition["ok"]:
				push_warning("Theme %s not loadable: %s" % [path, definition["error"]])
			definitions[id] = definition


## [{id, name, author, builtin, error}] sorted: built-in first, then by name.
func available_themes() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: String in definitions:
		var d: Dictionary = definitions[id]
		list.append({"id": id, "name": d.get("name", id), "author": d.get("author", ""),
			"builtin": d["builtin"], "error": d.get("error", "")})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["builtin"] != b["builtin"]:
			return a["builtin"]
		return str(a["name"]) < str(b["name"]))
	return list


## Builds and applies a theme to the whole window. Returns false if it cannot be resolved.
func apply(id: String, save := true) -> bool:
	var resolved := ThemeTokens.resolve(id, definitions, BASE_THEME)
	if resolved == null:
		push_warning("Theme '%s' could not be loaded" % id)
		return false
	for warning in resolved.warnings:
		push_warning("Theme %s: %s" % [id, warning])
	tokens = resolved
	theme = ThemeBuilder.build(tokens)
	theme_id = id
	get_tree().root.theme = theme
	RenderingServer.set_default_clear_color(tokens.color("color.surface.app"))
	if save:
		AppConfig.set_setting("appearance", "theme", id)
	EventBus.theme_changed.emit(id)
	return true


## Scales the whole UI (fonts are re-rendered sharp, layouts get more or less room).
func set_ui_scale(value: float, save := true) -> void:
	ui_scale = clampf(snappedf(value, SCALE_STEP), SCALE_MIN, SCALE_MAX)
	_apply_scale()
	if save:
		AppConfig.set_setting("appearance", "ui_scale", ui_scale)
	EventBus.ui_scale_changed.emit(ui_scale)


func color(key: String) -> Color:
	return tokens.color(key) if tokens != null else Color.MAGENTA


func _apply_scale() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var logical := (Vector2(root.size) / ui_scale).round()
	root.content_scale_size = Vector2i(maxi(int(logical.x), 1), maxi(int(logical.y), 1))
