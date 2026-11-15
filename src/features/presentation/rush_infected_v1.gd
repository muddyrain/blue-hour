class_name RushInfectedV1
extends RefCounted
## Lean, forward-pitched six-phase gait; cadence follows accepted movement.

const SHEETS: Array[Texture2D] = [
	preload("res://assets/infected_v1/rush/e.png"),
	preload("res://assets/infected_v1/rush/se.png"),
	preload("res://assets/infected_v1/rush/s.png"),
	preload("res://assets/infected_v1/rush/ne.png"),
	preload("res://assets/infected_v1/rush/n.png"),
]
const ROOTS: Array[Vector2] = [
	Vector2(160, 304), Vector2(160, 304), Vector2(160, 304),
	Vector2(160, 304), Vector2(160, 304),
]
const DISPLAY_SCALE: float = 0.29
const WALK_FPS: float = 8.0


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName,
		walk_clock: float, attack_clock: float, hit_clock: float, defeat_clock: float) -> void:
	var octant: int = MotionAtlas.octant(direction)
	var source: int = InfectedSheetV1.SOURCE_FOR_OCTANT[octant]
	var frame: int = InfectedSheetV1.frame_for(state, walk_clock, attack_clock,
		hit_clock, defeat_clock, WALK_FPS)
	InfectedSheetV1.pose(sprite, SHEETS[source], ROOTS[source], octant, frame)
