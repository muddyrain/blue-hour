class_name NormalInfectedV1
extends RefCounted
## Ordinary infected presentation only. Cached sheets; no gameplay or save inputs.

const SHEETS: Array[Texture2D] = [
	preload("res://assets/infected_v1/normal/e.png"),
	preload("res://assets/infected_v1/normal/se.png"),
	preload("res://assets/infected_v1/normal/s.png"),
	preload("res://assets/infected_v1/normal/ne.png"),
	preload("res://assets/infected_v1/normal/n.png"),
]
const SOURCE_FOR_OCTANT: Array[int] = [0, 1, 2, 1, 0, 3, 4, 3]
# Fixed authored roots per source direction; never fit individual alpha bounds.
const ROOTS: Array[Vector2] = [
	Vector2(160, 304), Vector2(160, 292), Vector2(157, 304),
	Vector2(157, 304), Vector2(157, 302),
]
const DISPLAY_SCALE: float = 0.26
const WALK_FPS: float = 8.0
const WALK_COUNT: int = 6

static var _legacy_preview: bool = "--bh-normal-art-legacy" in OS.get_cmdline_user_args()


static func enabled() -> bool:
	return not _legacy_preview


static func frame_for(state: StringName, walk_clock: float, attack_clock: float,
		hit_clock: float, defeat_clock: float) -> int:
	return InfectedSheetV1.frame_for(state, walk_clock, attack_clock,
		hit_clock, defeat_clock, WALK_FPS)


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName,
		walk_clock: float, attack_clock: float, hit_clock: float, defeat_clock: float) -> void:
	var octant: int = MotionAtlas.octant(direction)
	var source: int = SOURCE_FOR_OCTANT[octant]
	InfectedSheetV1.pose(sprite, SHEETS[source], ROOTS[source], octant,
		frame_for(state, walk_clock, attack_clock, hit_clock, defeat_clock))
