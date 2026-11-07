class_name ToxicCarrierVisualV1
extends RefCounted
## The carrier uses its own art with the ordinary infected's octant convention.

const SHEET: Texture2D = preload("res://assets/infected_v1/toxic/carrier.png")
const SOURCE_COUNT: int = 5
const POSE_COUNT: int = 12
const CELL: Vector2 = Vector2(160, 160)
const ROOT: Vector2 = Vector2(80, 144)
const DISPLAY_SCALE: float = 0.58


static func frame_for(state: StringName, walk_clock: float, attack_clock: float,
		defeat_clock: float, cast_progress: float) -> int:
	match state:
		&"defeated":
			return 10 if defeat_clock < 0.18 else 11
		&"windup":
			return 7 if cast_progress < 0.52 else 8
		&"hit":
			return 9
		&"attack":
			return 5 if attack_clock > 0.14 else 6
		&"move":
			return 1 + int(maxf(walk_clock, 0.0) * 7.0) % 4
	return 0


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName,
		walk_clock: float, attack_clock: float, defeat_clock: float, cast_progress: float) -> void:
	var octant: int = MotionAtlas.octant(direction)
	sprite.texture = SHEET
	sprite.hframes = SOURCE_COUNT
	sprite.vframes = POSE_COUNT
	sprite.flip_h = octant in [3, 4, 5]
	sprite.offset = CELL * 0.5 - ROOT
	var row: int = frame_for(state, walk_clock, attack_clock, defeat_clock, cast_progress)
	sprite.frame = row * SOURCE_COUNT + NormalInfectedV1.SOURCE_FOR_OCTANT[octant]
