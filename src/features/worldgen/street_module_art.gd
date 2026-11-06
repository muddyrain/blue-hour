class_name StreetModuleArt
extends RefCounted
## Measured source pixels, independent of textures and runtime world ownership.
const DEFINITIONS: Dictionary = {
	"street_shop": {
		"native_size": Vector2(1122, 1402), "origin": Vector2(563.5, 1265),
		"reference_width": 1023.0, "visible_top": 363.0, "roof_split": 936,
		"door_anchor": Vector2(560, 1265), "sign_rect": Rect2(290, 688, 510, 72),
		"street_sign": "便利店"
	},
	"street_eatery": {
		"native_size": Vector2(1122, 1402), "origin": Vector2(571.5, 1293),
		"reference_width": 1047.0, "visible_top": 435.0, "roof_split": 958,
		"door_anchor": Vector2(560, 1293), "sign_rect": Rect2(308, 750, 438, 66),
		"street_sign": "晨光小食"
	}
}
const COURTYARD_NATIVE: Vector2 = Vector2(1448, 1086)
const COURTYARD_ANCHOR: Vector2 = Vector2(142, 924)
const COURTYARD_REFERENCE_WIDTH: float = 1165.0
const COURTYARD_FEET: Array[Rect2] = [Rect2(142, 897, 1165, 28), Rect2(175, 360, 100, 537)]
const PAVING_PATCH: float = 256.0

static func definition(art: String) -> Dictionary:
	return DEFINITIONS.get(art, {}).duplicate(true)

static func for_archetype(type: String) -> String:
	return {"convenience_store": "street_shop", "eatery": "street_eatery"}.get(type, "")

static func visible_height(art: String, width: float) -> float:
	var value: Dictionary = DEFINITIONS[art]
	return (value.origin.y - value.visible_top) * width / value.reference_width

static func door_offset(art: String, width: float) -> float:
	var value: Dictionary = DEFINITIONS[art]
	return (value.door_anchor.x - value.origin.x) * width / value.reference_width

static func courtyard_collisions(point: Vector2, width: float) -> Array:
	var ratio: float = width / COURTYARD_REFERENCE_WIDTH
	var result: Array = []
	for foot: Rect2 in COURTYARD_FEET:
		var box: Rect2 = Rect2(point + (foot.position - COURTYARD_ANCHOR) * ratio, foot.size * ratio)
		result.append([box.position.x, box.position.y, box.size.x, box.size.y])
	return result
