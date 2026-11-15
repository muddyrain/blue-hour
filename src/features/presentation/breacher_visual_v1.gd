class_name BreacherVisualV1
extends RefCounted
## Display identity is separate from the boss's historical heavy behavior/snapshot kind.

const SHEET: Texture2D = preload("res://assets/infected_v1/breacher/actions.png")
const DISPLAY_SCALE: float = 0.48


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName, walk_clock: float,
		attack_clock: float, defeat_clock: float, progress: float) -> void:
	SpecialInfectedSheetV1.pose(sprite, SHEET, direction,
		SpecialInfectedSheetV1.frame_for(state, walk_clock, attack_clock, defeat_clock, progress, 6.0))
