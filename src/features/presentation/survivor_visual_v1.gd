class_name SurvivorVisualV1
extends RefCounted
## Full-body, independently drawn eight-direction survivor clips. No gameplay state.

const SHEETS: Array[Texture2D] = [
	preload("res://assets/survivors_v1/gu.png"),
	preload("res://assets/survivors_v1/xia.png"),
	preload("res://assets/survivors_v1/lin.png"),
	preload("res://assets/survivors_v1/shen.png"),
	preload("res://assets/survivors_v1/lu.png"),
	preload("res://assets/survivors_v1/ruan.png"),
	preload("res://assets/survivors_v1/ye.png"),
	preload("res://assets/survivors_v1/he.png"),
]
const WALK_COUNT: int = 4
const WALK_FPS: float = 8.0
const ATTACK_SECONDS: float = 0.24

var _last_fire_clock: float = 0.0
var _attack_started: float = -1.0
var _attack_facing: Vector2 = Vector2.RIGHT


static func variant_for(identity: String) -> int:
	var definition: SurvivorDefinition = SurvivorRoster.definition_by_id(identity)
	if definition == null:
		return 0
	return definition.visual_variant if definition.visual_variant >= 0 else definition.member_id - 1


static func frame_for(state: StringName, walk_phase: float, attack_elapsed: float) -> int:
	if attack_elapsed >= 0.0 and attack_elapsed < ATTACK_SECONDS:
		return 5 if attack_elapsed < 0.055 else 6 if attack_elapsed < 0.14 else 7
	if state in [&"move", &"move_fire"]:
		return 1 + int(maxf(walk_phase, 0.0)) % WALK_COUNT
	return 0


static func pose_head(head: Sprite2D, body: Sprite2D, hold: Node2D) -> void:
	# Repaint only the current frame's hair above the gun. Cancel hold bob/recoil
	# so this occlusion mask coincides exactly with the full-body animation.
	head.texture = body.texture
	head.hframes = body.hframes
	head.vframes = body.vframes
	head.frame = body.frame
	head.flip_h = body.flip_h
	head.offset = body.offset
	head.transform = hold.transform.affine_inverse() * body.transform
	var material: ShaderMaterial = head.material as ShaderMaterial
	material.set_shader_parameter("grid", Vector2(body.hframes, body.vframes))


func pose(sprite: Sprite2D, variant: int, direction: Vector2, facing: Vector2,
		state: StringName, clock: float, gait: float, fire_clock: float,
		attack_clock: float, weapon_phase: String = "", weapon_progress: float = 0.0) -> void:
	# Keep the visual follow-through after the existing muzzle flash expires.
	# The logical shot, weapon grip and LOS prediction retain their original clocks.
	if fire_clock > _last_fire_clock:
		_attack_started = clock
		_attack_facing = facing
	_last_fire_clock = fire_clock
	var elapsed: float = clock - _attack_started if _attack_started >= 0.0 else -1.0
	if attack_clock > 0.0:
		elapsed = 0.30 - attack_clock
		_attack_facing = facing
	# Melee anticipation is supplied by the real windup; contact is the first
	# committed recovery frame, including an empty swing. No second attack timer.
	if weapon_phase == "windup":
		elapsed = 0.01
		_attack_facing = facing
	elif weapon_phase in ["recover", "recovery"] and weapon_progress < 0.45:
		elapsed = 0.08 if weapon_progress < 0.20 else 0.17
		_attack_facing = facing
	# Retain authored hit and fallen artwork; neither uses the old split shader.
	if state in [&"hit", &"defeated"]:
		_attack_started = -1.0
		if variant < MotionAtlas.RIGHT.size():
			MotionAtlas.pose(sprite, false, "", variant, facing, 5 if state == &"hit" else 6)
		else:
			sprite.texture = SHEETS[variant]
			sprite.hframes = 8
			sprite.vframes = 8
			sprite.offset = Vector2(0, -96)
			sprite.flip_h = false
			sprite.frame = MotionAtlas.octant(facing) * 8
		sprite.material = null
		return
	var attacking: bool = elapsed >= 0.0 and elapsed < ATTACK_SECONDS
	var octant: int = MotionAtlas.octant(_attack_facing if attacking else direction)
	sprite.texture = SHEETS[variant]
	sprite.hframes = 8
	sprite.vframes = 8
	sprite.flip_h = false
	sprite.material = null
	sprite.offset = Vector2(0, -96)
	sprite.frame = octant * 8 + frame_for(state, gait * WALK_FPS / 9.0, elapsed)
