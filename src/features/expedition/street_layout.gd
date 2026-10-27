class_name StreetLayout
extends Resource
## Authored spatial data. Rewards and battle rules remain with their existing owners.

@export var id: StringName
@export var display_name: String
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
	var values: Array[Rect2] = [bus_block,cash_block,food_block]
	values.append_array(residences)
	values.append_array(fences)
	return values


func buildings() -> Array[Rect2]:
	var values: Array[Rect2] = [cash_block,food_block]
	values.append_array(residences)
	return values


func shot_obstacles() -> Array[ShotObstacle]:
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
