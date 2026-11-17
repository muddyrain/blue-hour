class_name CampPixelArt
extends RefCounted
## Measured alpha bounds from the approved pixel family. No runtime image resampling.

const SHEET: Texture2D = preload("res://assets/camp_pixel/residents.png")
const REGIONS: Array[Rect2] = [
	Rect2(145, 54, 202, 339), Rect2(556, 56, 231, 337),
	Rect2(984, 65, 212, 328), Rect2(1418, 67, 206, 326),
	Rect2(147, 495, 187, 342), Rect2(564, 502, 197, 335),
	Rect2(995, 495, 203, 342), Rect2(1437, 493, 190, 344),
]


static func variant(definition_id: String) -> int:
	var index: int = int(definition_id.trim_prefix("crew_")) - 1
	return 7 if index == 8 else 5 if index == 9 else clampi(index, 0, 7)


static func body(definition_id: String) -> AtlasTexture:
	var texture: AtlasTexture = AtlasTexture.new()
	texture.atlas = SHEET
	texture.region = REGIONS[variant(definition_id)].grow(2)
	texture.filter_clip = true
	return texture
