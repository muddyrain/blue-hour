class_name SpecialInfectedSheetV1
extends RefCounted
## Registration shared by specials; rules and clocks remain with their existing owners.

const CELL: Vector2 = Vector2(256, 256)
const ROOT: Vector2 = Vector2(128, 240)
const SOURCE_COUNT: int = 5
const POSE_COUNT: int = 12
const NIGHT_DETAIL_LIFT: float = 0.35 # PROJECT_TEMP; multiplied by PR #71's night strength.


static func frame_for(state: StringName, walk_clock: float, attack_clock: float,
		defeat_clock: float, progress: float, walk_fps: float = 8.0) -> int:
	match state:
		&"defeated":
			return 10 if defeat_clock < 0.18 else 11
		&"hit":
			return 9
		&"windup":
			return 5 if progress < 0.52 else 6
		&"release":
			return 7 if progress < 0.55 else 8
		&"attack":
			return 7 if attack_clock > 0.14 else 8
		&"move", &"rush":
			return 1 + int(maxf(walk_clock, 0.0) * walk_fps) % 4
	return 0


static func pose(sprite: Sprite2D, sheet: Texture2D, direction: Vector2, row: int,
		night_lift: float = NIGHT_DETAIL_LIFT, sac_contrast: float = 0.0) -> void:
	var octant: int = MotionAtlas.octant(direction)
	sprite.texture = sheet
	sprite.material = InfectedSheetV1.MATERIAL
	# Species traits belong to the sprite, never to the shared palette resource.
	sprite.set_instance_shader_parameter("special_night_lift", night_lift)
	sprite.set_instance_shader_parameter("burst_sac_contrast", sac_contrast)
	sprite.hframes = SOURCE_COUNT
	sprite.vframes = POSE_COUNT
	sprite.flip_h = octant in [3, 4, 5]
	sprite.offset = CELL * 0.5 - ROOT
	sprite.rotation = 0.0
	sprite.frame = row * SOURCE_COUNT + InfectedSheetV1.SOURCE_FOR_OCTANT[octant]


static func supports(kind: String) -> bool:
	return kind in [ScreamerPolicyV1.KIND, ToxicV1.KIND, BurstRuntimeV1.KIND,
		NightHoundV1.KIND, BossDefinition.KIND]
