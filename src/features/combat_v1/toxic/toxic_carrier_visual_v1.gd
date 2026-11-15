class_name ToxicCarrierVisualV1
extends RefCounted
## Inflated mist sacs; cast progress is supplied by ToxicV1, never by an animation timer.

const SHEET: Texture2D = preload("res://assets/infected_v1/toxic/actions.png")
const SOURCE_COUNT: int = SpecialInfectedSheetV1.SOURCE_COUNT
const POSE_COUNT: int = SpecialInfectedSheetV1.POSE_COUNT
const CELL: Vector2 = SpecialInfectedSheetV1.CELL
const ROOT: Vector2 = SpecialInfectedSheetV1.ROOT
const DISPLAY_SCALE: float = 0.38


static func frame_for(state: StringName, walk_clock: float, attack_clock: float,
		defeat_clock: float, cast_progress: float) -> int:
	return SpecialInfectedSheetV1.frame_for(state, walk_clock, attack_clock, defeat_clock, cast_progress, 7.0)


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName,
		walk_clock: float, attack_clock: float, defeat_clock: float, cast_progress: float) -> void:
	SpecialInfectedSheetV1.pose(sprite, SHEET, direction,
		frame_for(state, walk_clock, attack_clock, defeat_clock, cast_progress))
