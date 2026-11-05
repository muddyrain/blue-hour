class_name ActorVisual
extends Node2D
## Movement, aiming and damage remain inputs; this component never changes gameplay state.

const LegsTexture: Texture2D = preload("res://assets/p032/survivor_legs_032.png")
const UpperTexture: Texture2D = preload("res://assets/p032/survivor_upper_032.png")
const FallenTexture: Texture2D = preload("res://assets/p03/survivor_03.png")
const EnemyTexture: Texture2D = preload("res://assets/p03/infected_03.png")
const CarbineView: WeaponPresentation = preload("res://assets/p032/carbine_view.tres")
const LongRifleView: WeaponPresentation = preload("res://assets/p032/long_rifle_view.tres")
const WALK_FRAMES: Array[int] = [1, 2, 3, 2]
const HAND_PIXELS: Array[Vector2] = [Vector2(156, 140), Vector2(181, 110), Vector2(131, 143)]
const BODY_SCALE: float = 0.36
const COLOURS: Array[Color] = [Color("80ddd8"), Color("f2c37f"), Color("e88266")]
const NORMAL_DIRECTION_MARGIN: float = PI / 36.0
const NORMAL_CONTACT_RESPONSE: float = 96.0

var is_enemy: bool = false
var enemy_kind: String = EnemyRules.NORMAL
var enemy_windup: bool = false
var enemy_rushing: bool = false
var variant: int = 0
var motion_state: StringName = &"idle"
var direction_row: int = 0
var weapon_view: WeaponPresentation = CarbineView
var _body: Sprite2D
var _upper: Sprite2D
var _head: Sprite2D
var _hold: Node2D
var _weapon: Sprite2D
var _arms: MotionHands
var _muzzle: Polygon2D
var _clock: float = 0.0
var _walk_clock: float = 0.0
var _hit_clock: float = 0.0
var _fire_clock: float = 0.0
var _attack_clock: float = 0.0
var _defeat_clock: float = 0.0
var _is_defeated: bool = false
var _facing: Vector2 = Vector2.RIGHT
var _movement: Vector2 = Vector2.ZERO
var _aim: Vector2 = Vector2.ZERO
var _hit_direction: Vector2 = Vector2.LEFT
var _attack_direction: Vector2 = Vector2.RIGHT
var _hand_pixels: Array[Vector2] = HAND_PIXELS
var contact_vector: Vector2 = Vector2.INF
# Transient presentation caches; no new snapshot fields or gameplay inputs.
var _walk_rest: float = 0.0
var _contact_display: Vector2 = Vector2.ZERO
var _contact_initialized: bool = false


func _ready() -> void:
	var amber: bool = not is_enemy and variant == 1
	var lin: bool = not is_enemy and variant == 2
	var shen: bool = not is_enemy and variant==3
	var lu: bool = not is_enemy and variant==4
	_hand_pixels = CrewAppearance.POOL_HANDS if shen or lu else CrewAppearance.LIN_HANDS if lin else (CrewAppearance.AMBER_HANDS if amber else HAND_PIXELS)
	_body = _sprite(MotionAtlas.RIGHT[variant], 5, 7)
	if not is_enemy:
		_body.material = MotionAtlas.material(0)
	add_child(_body)
	_hold = Node2D.new()
	add_child(_hold)
	_upper = _sprite(MotionAtlas.RIGHT[variant], 5, 7)
	_upper.material = MotionAtlas.material(1)
	_hold.add_child(_upper)
	_arms = MotionHands.new()
	_arms.variant = variant
	_hold.add_child(_arms)
	_head = _sprite(MotionAtlas.RIGHT[variant], 5, 7)
	_head.material = MotionAtlas.material(2)
	_hold.add_child(_head)
	_weapon = Sprite2D.new()
	_weapon.centered = false
	_hold.add_child(_weapon)
	_muzzle = Polygon2D.new()
	_muzzle.polygon = PackedVector2Array([
		Vector2(-2, -2), Vector2(5, -4), Vector2(9, 0), Vector2(5, 4), Vector2(-2, 2),
	])
	_muzzle.color = Color("fff0b3")
	# Local child order keeps every actor inside the parent Y-sort group.
	_hold.add_child(_muzzle)
	_apply_pose()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, 17.0, Color(0.03, 0.06, 0.08, 0.35))
	draw_set_transform(Vector2.ZERO)
	if not is_enemy and not _is_defeated:
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, COLOURS[variant % COLOURS.size()], 2.0, true)


func advance(delta: float, movement: Vector2, aim: Vector2) -> void:
	_clock += delta
	_movement = movement
	_aim = aim
	# Contact steering can slow an enemy: gait follows accepted displacement.
	var stride: float = movement.length()/34.0 if is_enemy else 1.0
	if movement.length_squared() > 1.0:
		_walk_clock += delta * stride
		_walk_rest = 0.0
	elif _normal_enemy():
		_walk_rest += delta
		if _walk_rest >= 1.0 / 9.0:
			_walk_clock = 0.0
	else:
		_walk_clock = 0.0
	_hit_clock = maxf(0.0, _hit_clock - delta)
	_fire_clock = maxf(0.0, _fire_clock - delta)
	_attack_clock = maxf(0.0, _attack_clock - delta)
	if _is_defeated:
		_defeat_clock += delta
	elif is_enemy and _attack_clock > 0.0:
		_facing = _attack_direction
	elif aim.length_squared() > 0.0001:
		_face(aim)
	elif movement.length_squared() > 1.0:
		_face(movement)
	if _normal_enemy() and not _is_defeated and (contact_vector.is_finite() or _contact_initialized):
		var desired: Vector2 = _contact_target_offset()
		_contact_display = _contact_display.move_toward(desired, NORMAL_CONTACT_RESPONSE * delta) if _contact_initialized else desired
		_contact_initialized = true
	_apply_pose()


func _normal_enemy() -> bool:
	return is_enemy and enemy_kind == EnemyRules.NORMAL


func _face(direction: Vector2) -> void:
	if not _normal_enemy():
		_facing = direction.normalized()
		return
	var angle: float = MotionAtlas.octant(_facing) * PI / 4.0
	if absf(angle_difference(angle, direction.angle())) > PI / 8.0 + NORMAL_DIRECTION_MARGIN:
		angle = MotionAtlas.octant(direction) * PI / 4.0
	_facing = Vector2.RIGHT.rotated(angle)


func show_hit(direction: Vector2 = Vector2.LEFT) -> void:
	if _is_defeated:
		return
	_hit_clock = 0.18
	_hit_direction = direction
	_apply_pose()


func show_fire(direction: Vector2 = Vector2.ZERO) -> void:
	if _is_defeated:
		return
	if direction != Vector2.ZERO:
		_facing = direction.normalized()
	_fire_clock = 0.12
	_apply_pose()


func show_attack(direction: Vector2) -> void:
	if _is_defeated:
		return
	_attack_direction = direction.normalized()
	_facing = _attack_direction
	_attack_clock = 0.30
	_apply_pose()


func show_defeat() -> void:
	_is_defeated = true
	_defeat_clock = 0.0
	_apply_pose()


func set_weapon(view: WeaponPresentation) -> void:
	weapon_view = view
	if _body != null:
		_apply_pose()


func muzzle_offset(_direction: Vector2 = Vector2.ZERO) -> Vector2:
	return position + _hold.transform * (_weapon.transform * (weapon_view.muzzle_pixel - weapon_view.grip_pixel))


func aimed_shot_offset(direction: Vector2) -> Vector2:
	# Query the pose that show_fire will commit, without posing blocked candidates or firing.
	var facing: Vector2 = direction.normalized() if direction != Vector2.ZERO else _facing
	var row: int = _row(facing)
	var hand: Vector2 = _hand_pixels[row] - Vector2(128, 224)
	var size: Vector2 = weapon_view.direction_scales[row] * weapon_view.display_scale
	if row == 0 and facing.x < 0.0:
		hand.x = -hand.x
		size.y *= -1.0
	var hold_position: Vector2 = _body.position - facing * 1.5
	hold_position.y += sin(_walk_clock * 18.0) * 0.5 if _movement.length_squared() > 1.0 else sin(_clock * 2.0) * 0.2
	var hold: Transform2D = Transform2D(_hit_direction.x * (_hit_clock / 0.18) * 0.07, hold_position)
	var weapon: Transform2D = Transform2D(facing.angle(), size, 0.0, hand * BODY_SCALE)
	return position + hold * (weapon * (weapon_view.muzzle_pixel - weapon_view.grip_pixel))


func presentation_state() -> Dictionary:
	var hand: Vector2 = _hold.transform * _arms.trigger
	var grip: Vector2 = _hold.transform * (_weapon.transform * (weapon_view.grip_pixel + _weapon.offset))
	return {"state": String(motion_state), "frame": _body.frame, "row": direction_row,
		"leg_row": _row(_movement) if _movement.length_squared() > 1.0 else direction_row,
		"body_octant": MotionAtlas.octant(_movement if _movement.length_squared() > 1.0 and not is_enemy else _facing),
		"aim_octant": MotionAtlas.octant(_facing), "facing": _facing, "velocity": _movement, "aim": _aim,
		"muzzle": muzzle_offset(), "grip": grip, "hand": hand, "weapon": String(weapon_view.id),
		"weapon_layer": _weapon.z_index, "display_offset": position, "defeat_clock": _defeat_clock,
		"local_layers": [_upper.get_index(), _arms.get_index(), _weapon.get_index(), _head.get_index()]}


func _sprite(texture: Texture2D, columns: int, rows: int) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = columns
	sprite.vframes = rows
	sprite.offset = Vector2(0, -96)
	sprite.scale = Vector2.ONE * BODY_SCALE
	return sprite


func _row(direction: Vector2) -> int:
	if absf(direction.y) > absf(direction.x) * 0.8:
		return 1 if direction.y < 0.0 else 2
	return 0


func _apply_pose() -> void:
	if _body == null:
		return
	direction_row = _row(_facing)
	var moving: bool = _movement.length_squared() > 1.0 or (_normal_enemy() and _walk_clock > 0.0 and _walk_rest < 1.0 / 9.0)
	var legs: Vector2 = _movement if moving and not is_enemy else _facing
	# Existing clocks remain unchanged because gun bob participates in LOS. The visual
	# cadence scales by real survivor speed; enemy clock already scales by speed/34.
	var gait: float = _walk_clock * 9.0 * (1.0 if is_enemy else _movement.length() / 125.0)
	var action: int = WALK_FRAMES[int(gait) % 4] if moving else 0
	if is_enemy and enemy_kind == EnemyRules.RUSH and moving and not enemy_rushing:
		# Same original speed/state; relaxed passing pose before/after the real sprint.
		action = [1, 0, 3, 0][int(gait) % 4]
	var upper_action: int = action
	motion_state = &"move" if moving else &"idle"
	if is_enemy and enemy_rushing and moving:
		motion_state = &"rush"
	_body.position = Vector2.ZERO
	if _fire_clock > 0.0:
		motion_state = &"move_fire" if moving else &"fire"
		upper_action = 4
	if is_enemy and _attack_clock > 0.0:
		motion_state = &"attack"
		action = 5 if _attack_clock > 0.16 else 4
		_body.position += _facing * (_attack_clock / 0.30) * 3.0
	if _hit_clock > 0.0:
		motion_state = &"hit"
		upper_action = 5
		if is_enemy:
			action = 6
		_body.position += _hit_direction * (_hit_clock / 0.18) * 2.0
	var tint: Color = Color("ffd2b3") if _hit_clock > 0.0 else Color.WHITE
	if is_enemy and enemy_windup and not _is_defeated and _hit_clock <= 0.0:
		motion_state = &"windup"
		action = 4
		_body.position -= _facing * 3.0
	_pose_body(legs, action)
	_body.scale = Vector2.ONE * BODY_SCALE
	if is_enemy:
		_body.scale *= Vector2(1.25, 1.18) if enemy_kind == EnemyRules.HEAVY else Vector2(0.90, 1.03) if enemy_kind == EnemyRules.RUSH else Vector2.ONE
		if _normal_enemy() and NormalInfectedV1.enabled():
			_body.scale = Vector2.ONE * NormalInfectedV1.DISPLAY_SCALE
		# Presentation spacing only. Logical feet, navigation, LOS and melee range stay put.
		_body.position += _contact_offset()
	_body.self_modulate = tint
	if _is_defeated:
		motion_state = &"defeated"
		_pose_body(_facing, 7 if is_enemy else 6)
		_body.material = null
		_body.position = _contact_offset() if is_enemy else Vector2.ZERO
		_body.self_modulate = Color(0.70, 0.77, 0.78, clampf(1.0 - (_defeat_clock - 0.50) / 0.45, 0.0, 1.0))
	_update_hold(tint, moving, upper_action)
	queue_redraw()


func _pose_body(direction: Vector2, action: int) -> void:
	if _normal_enemy() and NormalInfectedV1.enabled():
		NormalInfectedV1.pose(_body, direction, motion_state, _walk_clock, _attack_clock, _hit_clock, _defeat_clock)
	else:
		MotionAtlas.pose(_body, is_enemy, enemy_kind, variant, direction, action)


func _contact_offset() -> Vector2:
	return _contact_display if _normal_enemy() and _contact_initialized else _contact_target_offset()


func _contact_target_offset() -> Vector2:
	if not contact_vector.is_finite():
		return Vector2.ZERO
	var direction: Vector2 = contact_vector.normalized() if contact_vector.length_squared() > 0.0001 else _facing
	var reach: float = 48.0 if enemy_kind == EnemyRules.HEAVY else 42.0
	return -direction * clampf(reach - contact_vector.length(), 0.0, 18.0)


func _update_hold(tint: Color, moving: bool, action: int) -> void:
	_upper.visible = not is_enemy and not _is_defeated
	_head.visible = _upper.visible
	_arms.visible = _upper.visible
	_weapon.visible = _upper.visible
	_muzzle.visible = _fire_clock > 0.045 and _weapon.visible
	if is_enemy:
		return
	MotionAtlas.pose(_upper, false, enemy_kind, variant, _facing, action)
	MotionAtlas.pose(_head, false, enemy_kind, variant, _facing, action)
	_upper.self_modulate = tint
	_head.self_modulate = tint
	_hold.position = _body.position - _facing * (_fire_clock / 0.12) * 1.5
	_hold.position.y += sin(_walk_clock * 18.0) * 0.5 if moving else sin(_clock * 2.0) * 0.2
	_hold.rotation = _hit_direction.x * (_hit_clock / 0.18) * 0.07
	var hand: Vector2 = _hand_pixels[direction_row] - Vector2(128, 224)
	if direction_row == 0 and _facing.x < 0.0:
		hand.x = -hand.x
	_weapon.texture = weapon_view.texture
	_weapon.offset = -weapon_view.grip_pixel
	_weapon.position = hand * BODY_SCALE
	_weapon.rotation = _facing.angle()
	_weapon.scale = weapon_view.direction_scales[direction_row] * weapon_view.display_scale
	if direction_row == 0 and _facing.x < 0.0:
		_weapon.scale.y *= -1.0
	_weapon.z_index = 0
	# Draw gun above torso and below hair without crossing another actor's Y group.
	_hold.move_child(_weapon, _head.get_index())
	_hold.move_child(_head, _hold.get_child_count() - 1)
	_hold.move_child(_muzzle, _hold.get_child_count() - 1)
	_arms.facing = _facing
	_arms.trigger = _weapon.position
	_arms.support = _weapon.transform * ((weapon_view.muzzle_pixel - weapon_view.grip_pixel) * 0.32)
	_arms.modulate = tint
	_arms.queue_redraw()
	_muzzle.position = _weapon.transform * (weapon_view.muzzle_pixel - weapon_view.grip_pixel)
	_muzzle.rotation = _weapon.rotation
	_muzzle.scale = Vector2.ONE * (0.65 + _fire_clock * 3.0)
