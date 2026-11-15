class_name InfectedSheetV1
extends RefCounted
## Shared registration and event timing for the three basic infected sheets.

const SOURCE_FOR_OCTANT: Array[int] = [0, 1, 2, 1, 0, 3, 4, 3]
const MATERIAL: ShaderMaterial = preload("res://src/features/presentation/infected_palette.tres")
const WALK_COUNT: int = 6


static func frame_for(state: StringName, walk_clock: float, attack_clock: float,
		hit_clock: float, defeat_clock: float, walk_fps: float) -> int:
	match state:
		&"defeated":
			return 12 if defeat_clock < 0.08 else 13 if defeat_clock < 0.18 else 14 if defeat_clock < 0.34 else 15
		&"hit":
			return 10 if hit_clock > 0.09 else 11
		&"attack":
			# Damage has already committed: contact, follow-through, recovery.
			return 7 if attack_clock > 0.22 else 8 if attack_clock > 0.10 else 9
		&"windup":
			return 9
		&"move", &"move_fire", &"rush":
			return 1 + int(maxf(walk_clock, 0.0) * walk_fps) % WALK_COUNT
	return 0


static func pose(sprite: Sprite2D, texture: Texture2D, anchor: Vector2,
		octant: int, frame: int) -> void:
	sprite.texture = texture
	sprite.material = MATERIAL
	sprite.hframes = 4
	sprite.vframes = 4
	sprite.flip_h = octant in [3, 4, 5]
	var cell: Vector2 = texture.get_size() / 4.0
	if sprite.flip_h:
		anchor.x = cell.x - anchor.x
	# One authored root per direction, preserving weight shift and knee lift.
	sprite.offset = cell * 0.5 - anchor
	sprite.frame = frame
