class_name WorldgenScale
extends RefCounted
## PROJECT_TEMP world units. Character art, speed and camera magnification are unchanged.
const WIDTH: Dictionary = {"convenience_store":280,"supermarket":480,"eatery":264,"warehouse":512,"garage":264,"detached_home":256,"row_house":304,"small_apartment":320}
const DEPTH: Dictionary = {"convenience_store":80,"supermarket":120,"eatery":88,"warehouse":128,"garage":96,"detached_home":96,"row_house":96,"small_apartment":88}
const DOOR_X: Dictionary = NeighborhoodArt.DOOR_X
# First nontransparent source pixel, measured on the actual 512x640 textures.
# All eight originals and courtyard_home end at the same source foot, y=608.
const VISIBLE_TOP: Dictionary = {"convenience_store":366,"supermarket":426,"eatery":408,"warehouse":425,"garage":364,"detached_home":131,"row_house":340,"small_apartment":199}
const MAIN_WIDTH: int = 176
const STREET_WIDTH: int = 128
const ALLEY_WIDTH: int = 96
const SIDEWALK: int = 36
const DOOR_CLEARANCE: int = 48

static func definition(id: String) -> Dictionary:
	var value: Dictionary = NeighborhoodArt.definition(id)
	value.version = 3
	value.collision_depth = DEPTH[id]
	return value

static func door_x(type: String, variant: int = 0) -> float:
	return 145.0 if type=="detached_home" and variant==3 else float(DOOR_X[type])

static func visible_height(type: String, variant: int = 0) -> float:
	var top: float=197.0 if type=="detached_home" and variant==3 else float(VISIBLE_TOP[type])
	return (608.0-top)*float(WIDTH[type])/448.0

static func visible_rect(entity: Dictionary) -> Rect2:
	var rect: Rect2=Rect2(float(entity.rect[0]),float(entity.rect[1]),float(entity.rect[2]),float(entity.rect[3]))
	var height: float=visible_height(entity.archetype,int(entity.variant))
	return Rect2(rect.position.x,rect.end.y-height,rect.size.x,height)
