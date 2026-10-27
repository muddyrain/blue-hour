class_name ShotObstacle
extends RefCounted
## Explicit physical footprint and shot semantics; never inferred from roof pixels.

var id: StringName
var footprint: Rect2
var blocks_shots: bool


func _init(obstacle_id: StringName, bounds: Rect2, solid: bool) -> void:
	id = obstacle_id
	footprint = bounds
	blocks_shots = solid
