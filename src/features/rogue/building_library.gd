class_name BuildingLibrary
extends RefCounted
## Asset IDs are code-owned, never paths from a save file.
const DOOR_X: Dictionary = {"convenience_store":252,"supermarket":242,"eatery":300,"warehouse":256,"garage":252,"detached_home":170,"row_house":256,"small_apartment":256}
const DEPTH: Dictionary = {"convenience_store":168,"supermarket":112,"eatery":144,"warehouse":144,"garage":128,"detached_home":176,"row_house":144,"small_apartment":192}
const TITLES: Dictionary = {"convenience_store":"街角便利店","supermarket":"青禾超市","eatery":"暖灯食堂","warehouse":"北岸仓库","garage":"旧街修理铺","detached_home":"柳巷独栋","row_house":"河畔联排","small_apartment":"北岸公寓"}
static func definition(id: String) -> Dictionary:
	return {"archetype_id":id,"version":1,"title":TITLES[id],"texture":load("res://assets/world_v1/"+id+".png") as Texture2D,
		"origin":Vector2(256,608),"foot":Vector2(256,608),"door_anchor":Vector2(DOOR_X[id],608),"collision_depth":DEPTH[id],"roof_split":512,"orientation":"south","themes":["commercial","residential","industrial"],"occlusion":"roof_alpha_0.4_on_friend"}
