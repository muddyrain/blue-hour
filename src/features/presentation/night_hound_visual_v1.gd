class_name NightHoundVisualV1
extends RefCounted
## Original four-legged poses projected from existing actor presentation state.

const ATLAS: Texture2D = preload("res://assets/combat_v1/hound/night_hound_v1.svg")
const DISPLAY_SCALE: float = 0.95
const CELL: Vector2 = Vector2(96.0, 72.0)
const GROUND: Vector2 = Vector2(48.0, 59.0)
const COLUMNS: Array[int] = [0, 1, 2, 1, 0, 3, 4, 3]
const SOURCE_COLUMNS: int = 5
const ROWS: int = 10


static func pose(sprite: Sprite2D, direction: Vector2, state: StringName, walk_clock: float,
		attack_clock: float, defeat_clock: float) -> void:
	var octant: int = MotionAtlas.octant(direction)
	var row: int = 0
	match state:
		&"move", &"rush":
			row = 1 + posmod(int(walk_clock * 8.0), 4)
		&"windup":
			row = 5
		&"attack":
			row = 6 if attack_clock > 0.16 else 0
		&"hit":
			row = 7
		&"defeated":
			row = 8 if defeat_clock < 0.12 else 9
	sprite.texture = ATLAS
	sprite.hframes = SOURCE_COLUMNS
	sprite.vframes = ROWS
	sprite.offset = CELL * 0.5 - GROUND
	sprite.flip_h = octant in [3, 4, 5]
	sprite.frame = row * sprite.hframes + COLUMNS[octant]
