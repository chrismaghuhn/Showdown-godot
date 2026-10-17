class_name StageLayout
extends RefCounted
## Battlefield geometry from the design's "Battlefield spec": sprites and platforms live on a
## 640 × 360 stage (units u) that scales with the field; HUD and text never scale with it.
##   u      = min(field.w / 640, field.h / 360)
##   origin = ((field.w − 640u) / 2, field.h − 360u)   (centered, bottom-aligned)
## "front" = the opponent's slots (far), "back" = ours (near). Pure: no nodes.

const STAGE := Vector2(640, 360)

## slot key -> {size, feet, platform}
const SINGLES := {
	"front": {"size": 112.0, "feet": Vector2(496, 136), "platform": Vector2(160, 20)},
	"back": {"size": 132.0, "feet": Vector2(144, 340), "platform": Vector2(192, 24)},
}
const DOUBLES := {
	"front_l": {"size": 96.0, "feet": Vector2(424, 136), "platform": Vector2(140, 18)},
	"front_r": {"size": 96.0, "feet": Vector2(564, 152), "platform": Vector2(140, 18)},
	"back_l": {"size": 112.0, "feet": Vector2(84, 332), "platform": Vector2(160, 22)},
	"back_r": {"size": 112.0, "feet": Vector2(220, 344), "platform": Vector2(160, 22)},
}
## Native size of pixel sprites (Gen 1-5 style).
const PIXEL_SPRITE := 96.0


static func unit(field: Vector2) -> float:
	return minf(field.x / STAGE.x, field.y / STAGE.y)


static func origin(field: Vector2) -> Vector2:
	var u := unit(field)
	return Vector2((field.x - STAGE.x * u) / 2.0, field.y - STAGE.y * u)


## Pixel rects of every slot: {key: {"slot": Rect2, "platform": Rect2, "feet": Vector2}}.
static func compute(field: Vector2, doubles := false) -> Dictionary:
	var u := unit(field)
	var o := origin(field)
	var result := {}
	var spec: Dictionary = DOUBLES if doubles else SINGLES
	for key: String in spec:
		var s: Dictionary = spec[key]
		var feet: Vector2 = o + s["feet"] * u
		var size: float = s["size"] * u
		var platform: Vector2 = s["platform"] * u
		result[key] = {
			"feet": feet,
			"slot": Rect2(feet.x - size / 2.0, feet.y - size, size, size),
			"platform": Rect2(feet - platform / 2.0, platform),
		}
	return result


## Drawn size of a sprite inside a slot: fit keeping aspect, never larger than the slot.
## Pixel sprites snap to a whole multiple of 96 px when that is within 10 % of the slot.
static func sprite_size(slot_size: float, texture_size: Vector2, pixel_art := true) -> Vector2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ZERO
	if pixel_art and is_equal_approx(texture_size.x, PIXEL_SPRITE) and is_equal_approx(texture_size.y, PIXEL_SPRITE):
		var multiple := maxf(roundf(slot_size / PIXEL_SPRITE), 1.0) * PIXEL_SPRITE
		if absf(multiple - slot_size) <= slot_size * 0.1 and multiple <= slot_size * 1.1:
			return Vector2(multiple, multiple)
	var scale := minf(slot_size / texture_size.x, slot_size / texture_size.y)
	return texture_size * scale
