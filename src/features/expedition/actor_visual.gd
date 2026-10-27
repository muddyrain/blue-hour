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
const COLOURS: Array[Color] = [Color("80ddd8"), Color("f2c37f")]

var is_enemy: bool = false
var variant: int = 0
var motion_state: StringName = &"idle"
var direction_row: int = 0
var weapon_view: WeaponPresentation = CarbineView
var _body: Sprite2D
var _upper: Sprite2D
var _head: Sprite2D
var _hold: Node2D
var _weapon: Sprite2D
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


func _ready() -> void:
	var amber: bool = not is_enemy and variant == 1
	_hand_pixels = CrewAppearance.AMBER_HANDS if amber else HAND_PIXELS
	var upper_texture: Texture2D = CrewAppearance.AMBER_UPPER if amber else UpperTexture
	_body = _sprite(EnemyTexture if is_enemy else (CrewAppearance.AMBER_LEGS if amber else LegsTexture), 4, 4)
	add_child(_body)
	_hold = Node2D.new()
	add_child(_hold)
	_upper = _sprite(upper_texture, 3, 1)
	_upper.z_index = 1
	_upper.visible = not is_enemy
	_hold.add_child(_upper)
	_head = Sprite2D.new()
	_head.texture = upper_texture
	_head.region_enabled = true
	_head.offset = Vector2(0, -164)
	_head.scale = Vector2.ONE * BODY_SCALE
	_head.z_index = 3
	_hold.add_child(_head)
	_weapon = Sprite2D.new()
	_weapon.centered = false
	_hold.add_child(_weapon)
	_muzzle = Polygon2D.new()
	_muzzle.polygon = PackedVector2Array([
		Vector2(-2, -2), Vector2(5, -4), Vector2(9, 0), Vector2(5, 4), Vector2(-2, 2),
	])
	_muzzle.color = Color("fff0b3")
	_muzzle.z_index = 4
	_hold.add_child(_muzzle)
	_apply_pose()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, 17.0, Color(0.03, 0.06, 0.08, 0.35))
	draw_set_transform(Vector2.ZERO)
	if not is_enemy and not _is_defeated:
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, COLOURS[variant % 2], 2.0, true)


func advance(delta: float, movement: Vector2, aim: Vector2) -> void:
	_clock += delta
	_movement = movement
	_aim = aim
	_walk_clock = _walk_clock + delta if movement.length_squared() > 1.0 else 0.0
	_hit_clock = maxf(0.0, _hit_clock - delta)
	_fire_clock = maxf(0.0, _fire_clock - delta)
	_attack_clock = maxf(0.0, _attack_clock - delta)
	if _is_defeated:
		_defeat_clock += delta
	elif is_enemy and _attack_clock > 0.0:
		_facing = _attack_direction
	elif aim.length_squared() > 0.0001:
		_facing = aim.normalized()
	elif movement.length_squared() > 1.0:
		_facing = movement.normalized()
	_apply_pose()


func show_hit(direction: Vector2 = Vector2.LEFT) -> void:
	_hit_clock = 0.18
	_hit_direction = direction
	_apply_pose()


func show_fire(direction: Vector2 = Vector2.ZERO) -> void:
	if direction != Vector2.ZERO:
		_facing = direction.normalized()
	_fire_clock = 0.12
	_apply_pose()


func show_attack(direction: Vector2) -> void:
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
	var hand_pixel: Vector2 = _hand_pixels[direction_row]
	if _upper.flip_h:
		hand_pixel.x = 256.0 - hand_pixel.x
	var hand: Vector2 = _hold.transform * (_upper.transform * (hand_pixel - Vector2(128, 128) + _upper.offset))
	var grip: Vector2 = _hold.transform * (_weapon.transform * (weapon_view.grip_pixel + _weapon.offset))
	return {"state": String(motion_state), "frame": _body.frame, "row": direction_row,
		"leg_row": _body.frame / 4, "facing": _facing, "velocity": _movement, "aim": _aim,
		"muzzle": muzzle_offset(), "grip": grip, "hand": hand, "weapon": String(weapon_view.id),
		"weapon_layer": _weapon.z_index, "display_offset": position, "defeat_clock": _defeat_clock}


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
	var moving: bool = _movement.length_squared() > 1.0
	var leg_row: int = _row(_movement) if moving and not is_enemy else direction_row
	_body.flip_h = _movement.x < 0.0 if moving and not is_enemy else _facing.x < 0.0
	_body.flip_h = _body.flip_h and leg_row == 0
	_body.frame = leg_row * 4 + (WALK_FRAMES[int(_walk_clock * 9.0) % 4] if moving else 0)
	_body.position = Vector2.ZERO
	motion_state = &"move" if moving else &"idle"
	if _fire_clock > 0.0:
		motion_state = &"move_fire" if moving else &"fire"
	if is_enemy and _attack_clock > 0.0:
		motion_state = &"attack"
		if direction_row == 0:
			_body.frame = 13 if _attack_clock > 0.16 else 12
		_body.position += _facing * (_attack_clock / 0.30) * 3.0
	if _hit_clock > 0.0:
		motion_state = &"hit"
		if is_enemy and direction_row == 0:
			_body.frame = 14
		_body.position += _hit_direction * (_hit_clock / 0.18) * 2.0
	var tint: Color = Color("ffd2b3") if _hit_clock > 0.0 else Color.WHITE
	_body.self_modulate = tint
	if _is_defeated:
		motion_state = &"defeated"
		if not is_enemy:
			_body.texture = CrewAppearance.AMBER_FULL if variant == 1 else FallenTexture
		_body.frame = 15 if is_enemy else 12
		_body.position = Vector2.ZERO
		_body.self_modulate = Color(0.70, 0.77, 0.78, clampf(1.0 - (_defeat_clock - 0.50) / 0.45, 0.0, 1.0))
	_update_hold(tint, moving)
	queue_redraw()


func _update_hold(tint: Color, moving: bool) -> void:
	_upper.visible = not is_enemy and not _is_defeated
	_head.visible = _upper.visible
	_weapon.visible = not is_enemy and not _is_defeated
	_muzzle.visible = _fire_clock > 0.045 and _weapon.visible
	if is_enemy:
		return
	_upper.frame = direction_row
	_upper.flip_h = direction_row == 0 and _facing.x < 0.0
	_upper.self_modulate = tint
	_head.region_rect = Rect2(direction_row * 256, 0, 256, 120)
	_head.flip_h = _upper.flip_h
	_head.self_modulate = tint
	_hold.position = _body.position - _facing * (_fire_clock / 0.12) * 1.5
	_hold.position.y += sin(_walk_clock * 18.0) * 0.5 if moving else sin(_clock * 2.0) * 0.2
	_hold.rotation = _hit_direction.x * (_hit_clock / 0.18) * 0.07
	var hand: Vector2 = _hand_pixels[direction_row] - Vector2(128, 224)
	if _upper.flip_h:
		hand.x = -hand.x
	_weapon.texture = weapon_view.texture
	_weapon.offset = -weapon_view.grip_pixel
	_weapon.position = hand * BODY_SCALE
	_weapon.rotation = _facing.angle()
	_weapon.scale = weapon_view.direction_scales[direction_row] * weapon_view.display_scale
	if direction_row == 0 and _facing.x < 0.0:
		_weapon.scale.y *= -1.0
	_weapon.z_index = weapon_view.direction_layers[direction_row]
	_muzzle.position = _weapon.transform * (weapon_view.muzzle_pixel - weapon_view.grip_pixel)
	_muzzle.rotation = _weapon.rotation
	_muzzle.scale = Vector2.ONE * (0.65 + _fire_clock * 3.0)
