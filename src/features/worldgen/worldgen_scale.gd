class_name WorldgenScale
extends RefCounted
## PROJECT_TEMP world units. Character art, speed and camera magnification are unchanged.
const WIDTH: Dictionary = {"convenience_store":280,"supermarket":480,"eatery":264,"warehouse":512,"garage":264,"detached_home":256,"row_house":304,"small_apartment":320}
const DEPTH: Dictionary = {"convenience_store":80,"supermarket":120,"eatery":88,"warehouse":128,"garage":96,"detached_home":96,"row_house":96,"small_apartment":88}
const DOOR_X: Dictionary = NeighborhoodArt.DOOR_X
const MAIN_WIDTH: int = 224
const STREET_WIDTH: int = 128
const ALLEY_WIDTH: int = 96
const SIDEWALK: int = 36
const DOOR_CLEARANCE: int = 48

static func definition(id: String) -> Dictionary:
	var value: Dictionary = NeighborhoodArt.definition(id)
	value.version = 3
	value.collision_depth = DEPTH[id]
	return value
