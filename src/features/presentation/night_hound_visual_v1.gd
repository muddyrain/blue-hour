class_name NightHoundVisualV1
extends RefCounted
## Four-legged gait, loaded crouch, airborne contact and landing from existing events.

const ATLAS: Texture2D = preload("res://assets/infected_v1/hound/actions.png")
const DISPLAY_SCALE: float = 0.38
const CELL: Vector2 = SpecialInfectedSheetV1.CELL
const GROUND: Vector2 = SpecialInfectedSheetV1.ROOT
const COLUMNS: Array[int] = [0, 1, 2, 1, 0, 3, 4, 3]
const SOURCE_COLUMNS: int = 5
const ROWS: int = 12
const NIGHT_DETAIL_LIFT: float = 0.45 # PROJECT_TEMP; preserve low-contrast fur/ears in deep blue light.


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName, walk_clock: float,
		attack_clock: float, defeat_clock: float, progress: float = 0.0) -> void:
	SpecialInfectedSheetV1.pose(sprite, ATLAS, direction,
		SpecialInfectedSheetV1.frame_for(state, walk_clock, attack_clock, defeat_clock, progress),
		NIGHT_DETAIL_LIFT)
