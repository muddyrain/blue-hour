class_name BurstInfectedVisualV1
extends RefCounted
## Intact amber sacs and warning pulses, driven by the authoritative burst phase.

const SHEET: Texture2D = preload("res://assets/infected_v1/burst/actions.png")
const DISPLAY_SCALE: float = 0.36
const SAC_CONTRAST: float = 1.0 # PROJECT_TEMP; only the authored amber sacs match the pigment mask.


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName, walk_clock: float,
		attack_clock: float, defeat_clock: float, progress: float) -> void:
	SpecialInfectedSheetV1.pose(sprite, SHEET, direction,
		SpecialInfectedSheetV1.frame_for(state, walk_clock, attack_clock, defeat_clock, progress),
		SpecialInfectedSheetV1.NIGHT_DETAIL_LIFT, SAC_CONTRAST)


static func flash(progress: float) -> Color:
	var pulse: float = pow(0.5 + 0.5 * sin(clampf(progress, 0.0, 1.0) * TAU * 4.0), 2.0)
	return Color.WHITE.lerp(Color(1.55, 1.30, 0.90), pulse * (0.35 + progress * 0.65))
