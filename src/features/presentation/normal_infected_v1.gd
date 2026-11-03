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
	match state:
		&"defeated":
			return 12 if defeat_clock < 0.08 else 13 if defeat_clock < 0.18 else 14 if defeat_clock < 0.34 else 15
		&"hit":
			return 10 if hit_clock > 0.09 else 11
		&"attack":
			# The authoritative hit already happened: contact first, then recovery.
			return 7 if attack_clock > 0.22 else 8 if attack_clock > 0.10 else 9
		&"move", &"move_fire":
			return 1 + int(maxf(walk_clock, 0.0) * WALK_FPS) % WALK_COUNT
	return 0


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName,
		walk_clock: float, attack_clock: float, hit_clock: float, defeat_clock: float) -> void:
	var octant: int = MotionAtlas.octant(direction)
	var source: int = SOURCE_FOR_OCTANT[octant]
	sprite.texture = SHEETS[source]
	sprite.hframes = 4
	sprite.vframes = 4
	sprite.flip_h = octant in [3, 4, 5]
	var cell: Vector2 = sprite.texture.get_size() / 4.0
	var anchor: Vector2 = ROOTS[source]
	if sprite.flip_h:
		anchor.x = cell.x - anchor.x
	sprite.offset = cell * 0.5 - anchor
	sprite.frame = frame_for(state, walk_clock, attack_clock, hit_clock, defeat_clock)
