class_name StreetLayout
extends Resource
## Authored spatial data. Rewards and battle rules remain with their existing owners.

var world_bounds: Rect2 = Rect2(0,0,1920,1440)
var world_data: Dictionary = {}

@export var id: StringName
@export var display_name: String
var rescue_point: Vector2 = Vector2(1344,1120)
@export var bus_block: Rect2
@export var bus_door: Vector2
@export var cash_block: Rect2
@export var cash_door: Vector2
@export var cash_title: String
@export var food_block: Rect2
@export var food_door: Vector2
@export var food_title: String
@export var residences: Array[Rect2] = []
@export var fences: Array[Rect2] = []
@export var roads: Array[Rect2] = []
@export var yards: Array[Rect2] = []
@export var arrivals: Array[Vector2] = []
@export var enemy_points: Array[Vector2] = []
@export var camera_start: Vector2
@export_multiline var route_hint: String


func blockers() -> Array[Rect2]:
	if not world_data.is_empty():
		var blocks: Array[Rect2] = [bus_block]
		blocks.append_array(residences)
		if (world_data.get("version")==3 or world_data.get("version")==4 or world_data.get("version")==5): blocks.append_array(fences)
		if (world_data.get("version")==4 or world_data.get("version")==5):
			for object: Dictionary in world_data.objects:
				var rect: Array=object.collision
				blocks.append(Rect2(float(rect[0]),float(rect[1]),float(rect[2]),float(rect[3])))
		return blocks
	var values: Array[Rect2] = [bus_block,cash_block,food_block]
	values.append_array(residences)
	values.append_array(fences)
	return values


func buildings() -> Array[Rect2]:
	if not world_data.is_empty(): return residences.duplicate()
	var values: Array[Rect2] = [cash_block,food_block]
	values.append_array(residences)
	return values


func shot_obstacles() -> Array[ShotObstacle]:
	if not world_data.is_empty():
		var walls: Array[ShotObstacle] = []
		for row: Dictionary in world_data.entities: walls.append(ShotObstacle.new(StringName(row.id),Rect2(row.rect[0],row.rect[1],row.rect[2],row.rect[3]),true))
		if (world_data.get("version")==3 or world_data.get("version")==4 or world_data.get("version")==5):
			for i: int in range(fences.size()): walls.append(ShotObstacle.new(StringName("yard_wall_%d"%i),fences[i],true))
		walls.append(ShotObstacle.new(&"bus",bus_block,false))
		return walls
	# TMP-123: only authored building bodies stop ordinary shots; category parity is unknown.
	var values: Array[ShotObstacle] = [
		ShotObstacle.new(&"cash_wall", cash_block, true),
		ShotObstacle.new(&"food_wall", food_block, true),
		ShotObstacle.new(&"bus", bus_block, false),
	]
	for index: int in range(residences.size()):
		values.append(ShotObstacle.new(StringName("residence_%d" % index), residences[index], true))
	for index: int in range(fences.size()):
		values.append(ShotObstacle.new(StringName("fence_%d" % index), fences[index], false))
	return values


func hit_area(kind: StringName) -> Rect2:
	var block: Rect2 = cash_block if kind == &"cash" else food_block
	return Rect2(block.position - Vector2(0,60),block.size + Vector2(0,60))


func bus_foot() -> Vector2:
	return Vector2(bus_block.get_center().x,bus_block.end.y)
