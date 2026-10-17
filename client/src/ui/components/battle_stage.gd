class_name BattleStage
extends Control
## The battlefield stage (design: "Battlefield spec"): platforms and sprites on a 640 × 360
## stage that scales with the field, centered and bottom-aligned. HUD cards are NOT part of
## the stage; they sit on top and never scale with it.

var doubles := false:
	set(value):
		doubles = value
		_relayout()

## slot key -> {"rect": TextureRect, "species": String, "request": int}
var _slots := {}
var _layout := {}
var _request_counter := 0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()
	elif what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


## Shows a Pokémon in a slot ("front"/"back", doubles: "front_l", ...). Loads the sprite async.
func set_slot(key: String, species: String, back: bool, shiny: bool) -> void:
	if not _slots.has(key):
		var rect := TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_slots[key] = {"rect": rect, "species": "", "request": 0}
	var slot: Dictionary = _slots[key]
	if slot["species"] == species + str(back) + str(shiny):
		return
	slot["species"] = species + str(back) + str(shiny)
	slot["name"] = species
	_request_counter += 1
	slot["request"] = _request_counter
	var rect: TextureRect = slot["rect"]
	rect.texture = null
	queue_redraw()
	_load_sprite(key, species, back, shiny, _request_counter)


func clear_slot(key: String) -> void:
	if _slots.has(key):
		(_slots[key]["rect"] as TextureRect).queue_free()
		_slots.erase(key)
		queue_redraw()


func _load_sprite(key: String, species: String, back: bool, shiny: bool, request: int) -> void:
	var texture := await GameData.get_sprite(species, back, shiny)
	if not _slots.has(key) or _slots[key]["request"] != request:
		return  # replaced meanwhile
	var rect: TextureRect = _slots[key]["rect"]
	rect.texture = texture
	# Pixel sprites (96 px) use nearest filtering, larger renders linear.
	var pixel_art := texture != null and texture.get_width() == 96 and texture.get_height() == 96
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_LINEAR
	_relayout()


func _relayout() -> void:
	_layout = StageLayout.compute(size, doubles)
	for key: String in _slots:
		var rect: TextureRect = _slots[key]["rect"]
		if not _layout.has(key):
			rect.visible = false
			continue
		var slot_rect: Rect2 = _layout[key]["slot"]
		var feet: Vector2 = _layout[key]["feet"]
		var drawn := StageLayout.sprite_size(slot_rect.size.x, rect.texture.get_size() if rect.texture != null else Vector2.ZERO)
		rect.visible = rect.texture != null
		rect.position = Vector2(feet.x - drawn.x / 2.0, feet.y - drawn.y).round()
		rect.size = drawn.round()
	queue_redraw()


func _draw() -> void:
	var ground := get_theme_color("ground", "BattleStage")
	for key: String in _layout:
		var platform: Rect2 = _layout[key]["platform"]
		var box := StyleBoxFlat.new()
		box.bg_color = ground
		box.set_corner_radius_all(int(platform.size.y))
		box.anti_aliasing = true
		draw_style_box(box, platform)
	# Placeholder while a sprite loads or when none exists: outline + name.
	var font := get_theme_default_font()
	for key: String in _slots:
		var rect: TextureRect = _slots[key]["rect"]
		if rect.texture != null or not _layout.has(key):
			continue
		var slot_rect: Rect2 = _layout[key]["slot"]
		var outline := StyleBoxFlat.new()
		outline.draw_center = false
		outline.border_color = get_theme_color("placeholder_border", "BattleStage")
		outline.set_border_width_all(1)
		outline.set_corner_radius_all(8)
		draw_style_box(outline, slot_rect)
		var label_text := str(_slots[key].get("name", ""))
		draw_string(font, Vector2(slot_rect.position.x, slot_rect.get_center().y), label_text,
			HORIZONTAL_ALIGNMENT_CENTER, slot_rect.size.x, 12, get_theme_color("placeholder", "BattleStage"))
