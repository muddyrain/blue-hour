class_name NeighborhoodArt
extends RefCounted
## V3 physical scale is authored from doors, not a shared image frame.
const WIDTH: Dictionary = {"convenience_store":448,"supermarket":640,"eatery":400,"warehouse":512,"garage":448,"detached_home":336,"row_house":448,"small_apartment":448}
const DEPTH: Dictionary = {"convenience_store":112,"supermarket":160,"eatery":128,"warehouse":128,"garage":144,"detached_home":128,"row_house":128,"small_apartment":112}
const CUT: Dictionary = {"convenience_store":478,"supermarket":510,"eatery":510,"warehouse":518,"garage":487,"detached_home":500,"row_house":500,"small_apartment":514}
const DOOR_X: Dictionary = {"convenience_store":252,"supermarket":256,"eatery":300,"warehouse":256,"garage":252,"detached_home":170,"row_house":256,"small_apartment":256}
static func definition(id: String) -> Dictionary:
	var value: Dictionary = BuildingLibrary.definition(id)
	if id in ["supermarket","row_house"]: value.texture=load("res://assets/world_v2/"+id+".png") as Texture2D
	value.version=2;value.roof_split=CUT[id];value.collision_depth=DEPTH[id];value.door_anchor=Vector2(DOOR_X[id],608)
	return value
