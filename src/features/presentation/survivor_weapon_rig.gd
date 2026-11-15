class_name SurvivorWeaponRig
extends RefCounted
## Pixel landmarks belong to the existing 256px frames, not the old three-row torso.
## Columns: idle, four steps, attack preparation/contact/recovery. Rows: E..NE.

const HandShader: Shader = preload("res://src/features/presentation/hand_occlusion.gdshader")
const MuzzleGlow: Texture2D = preload("res://assets/combat_v1/weapons/muzzle_glow.tres")
const ANCHORS: Array[Array] = [
	# gu: E, SE, S, SW, W, NW, N, NE.
	[Vector2(147, 146), Vector2(147, 151), Vector2(105, 164), Vector2(146, 148), Vector2(147, 149), Vector2(150, 136), Vector2(188, 139), Vector2(149, 145)],
	[Vector2(123, 155), Vector2(112, 162), Vector2(102, 153), Vector2(118, 157), Vector2(106, 159), Vector2(114, 142), Vector2(176, 142), Vector2(119, 155)],
	[Vector2(113, 155), Vector2(102, 163), Vector2(109, 148), Vector2(115, 156), Vector2(101, 157), Vector2(104, 145), Vector2(171, 139), Vector2(114, 151)],
	[Vector2(99, 144), Vector2(99, 146), Vector2(103, 134), Vector2(101, 150), Vector2(105, 144), Vector2(105, 136), Vector2(70, 145), Vector2(97, 143)],
	[Vector2(98, 143), Vector2(98, 151), Vector2(109, 138), Vector2(101, 150), Vector2(100, 147), Vector2(104, 137), Vector2(82, 137), Vector2(100, 144)],
	[Vector2(86, 149), Vector2(95, 152), Vector2(105, 165), Vector2(98, 150), Vector2(95, 151), Vector2(85, 142), Vector2(64, 132), Vector2(88, 148)],
	[Vector2(166, 148), Vector2(173, 151), Vector2(167, 164), Vector2(166, 149), Vector2(168, 150), Vector2(172, 140), Vector2(192, 129), Vector2(175, 147)],
	[Vector2(165, 147), Vector2(170, 150), Vector2(157, 163), Vector2(168, 148), Vector2(171, 149), Vector2(175, 140), Vector2(190, 132), Vector2(173, 146)],
	# xia: E, SE, S, SW, W, NW, N, NE.
	[Vector2(149, 137), Vector2(141, 144), Vector2(133, 147), Vector2(140, 145), Vector2(142, 143), Vector2(144, 129), Vector2(186, 142), Vector2(151, 136)],
	[Vector2(146, 145), Vector2(138, 152), Vector2(130, 155), Vector2(137, 153), Vector2(139, 151), Vector2(141, 137), Vector2(187, 148), Vector2(148, 144)],
	[Vector2(140, 148), Vector2(132, 155), Vector2(124, 158), Vector2(131, 156), Vector2(133, 154), Vector2(135, 140), Vector2(171, 148), Vector2(138, 147)],
	[Vector2(105, 141), Vector2(113, 148), Vector2(121, 151), Vector2(114, 149), Vector2(112, 147), Vector2(110, 133), Vector2(71, 143), Vector2(103, 140)],
	[Vector2(107, 139), Vector2(115, 146), Vector2(123, 149), Vector2(116, 147), Vector2(114, 145), Vector2(112, 131), Vector2(69, 140), Vector2(105, 138)],
	[Vector2(84, 141), Vector2(99, 148), Vector2(86, 151), Vector2(90, 149), Vector2(93, 147), Vector2(98, 133), Vector2(60, 137), Vector2(89, 140)],
	[Vector2(90, 144), Vector2(90, 151), Vector2(84, 154), Vector2(85, 152), Vector2(93, 150), Vector2(84, 136), Vector2(63, 134), Vector2(91, 143)],
	[Vector2(152, 143), Vector2(152, 150), Vector2(90, 153), Vector2(150, 151), Vector2(145, 149), Vector2(145, 145), Vector2(63, 135), Vector2(151, 142)],
	# lin: E, SE, S, SW, W, NW, N, NE.
	[Vector2(151, 139), Vector2(135, 146), Vector2(145, 139), Vector2(141, 143), Vector2(143, 142), Vector2(146, 131), Vector2(177, 141), Vector2(153, 138)],
	[Vector2(145, 149), Vector2(129, 156), Vector2(139, 149), Vector2(135, 153), Vector2(137, 152), Vector2(140, 141), Vector2(165, 146), Vector2(147, 148)],
	[Vector2(117, 150), Vector2(101, 157), Vector2(111, 150), Vector2(107, 154), Vector2(109, 153), Vector2(112, 142), Vector2(160, 148), Vector2(115, 149)],
	[Vector2(104, 144), Vector2(120, 151), Vector2(110, 144), Vector2(114, 148), Vector2(112, 147), Vector2(109, 136), Vector2(68, 142), Vector2(102, 143)],
	[Vector2(108, 144), Vector2(124, 151), Vector2(114, 144), Vector2(118, 148), Vector2(116, 147), Vector2(113, 136), Vector2(69, 142), Vector2(106, 143)],
	[Vector2(93, 145), Vector2(96, 152), Vector2(95, 145), Vector2(94, 149), Vector2(94, 148), Vector2(86, 137), Vector2(67, 144), Vector2(94, 144)],
	[Vector2(162, 149), Vector2(156, 156), Vector2(159, 149), Vector2(160, 153), Vector2(159, 152), Vector2(164, 141), Vector2(85, 142), Vector2(166, 148)],
	[Vector2(164, 147), Vector2(158, 154), Vector2(164, 147), Vector2(164, 151), Vector2(157, 150), Vector2(153, 139), Vector2(192, 142), Vector2(162, 146)],
	# shen: E, SE, S, SW, W, NW, N, NE.
	[Vector2(168, 146), Vector2(161, 151), Vector2(168, 149), Vector2(171, 151), Vector2(162, 146), Vector2(163, 138), Vector2(193, 139), Vector2(170, 145)],
	[Vector2(162, 147), Vector2(155, 152), Vector2(162, 150), Vector2(165, 152), Vector2(156, 147), Vector2(157, 139), Vector2(181, 144), Vector2(164, 146)],
	[Vector2(136, 150), Vector2(129, 155), Vector2(136, 153), Vector2(139, 155), Vector2(130, 150), Vector2(110, 143), Vector2(172, 143), Vector2(134, 149)],
	[Vector2(92, 148), Vector2(99, 153), Vector2(92, 151), Vector2(89, 153), Vector2(98, 148), Vector2(97, 140), Vector2(65, 147), Vector2(90, 147)],
	[Vector2(89, 145), Vector2(96, 150), Vector2(89, 148), Vector2(86, 150), Vector2(95, 145), Vector2(94, 137), Vector2(63, 143), Vector2(87, 144)],
	[Vector2(76, 147), Vector2(81, 152), Vector2(81, 150), Vector2(78, 152), Vector2(78, 147), Vector2(79, 139), Vector2(58, 143), Vector2(82, 146)],
	[Vector2(78, 146), Vector2(85, 151), Vector2(84, 149), Vector2(84, 151), Vector2(83, 146), Vector2(84, 138), Vector2(61, 142), Vector2(86, 145)],
	[Vector2(173, 146), Vector2(169, 151), Vector2(180, 149), Vector2(174, 151), Vector2(177, 146), Vector2(195, 138), Vector2(209, 142), Vector2(177, 145)],
	# lu: E, SE, S, SW, W, NW, N, NE.
	[Vector2(154, 136), Vector2(157, 148), Vector2(153, 130), Vector2(157, 157), Vector2(153, 139), Vector2(148, 148), Vector2(191, 137), Vector2(154, 146)],
	[Vector2(154, 143), Vector2(151, 156), Vector2(159, 131), Vector2(164, 154), Vector2(153, 141), Vector2(151, 151), Vector2(178, 141), Vector2(154, 150)],
	[Vector2(155, 143), Vector2(165, 153), Vector2(160, 134), Vector2(165, 157), Vector2(155, 141), Vector2(158, 150), Vector2(166, 138), Vector2(154, 148)],
	[Vector2(109, 137), Vector2(102, 147), Vector2(104, 131), Vector2(97, 153), Vector2(104, 135), Vector2(95, 144), Vector2(69, 137), Vector2(104, 142)],
	[Vector2(105, 138), Vector2(103, 150), Vector2(105, 129), Vector2(101, 155), Vector2(101, 139), Vector2(109, 145), Vector2(67, 138), Vector2(109, 145)],
	[Vector2(91, 141), Vector2(98, 146), Vector2(93, 132), Vector2(94, 153), Vector2(89, 138), Vector2(82, 140), Vector2(56, 132), Vector2(87, 146)],
	[Vector2(168, 144), Vector2(172, 147), Vector2(166, 136), Vector2(169, 154), Vector2(164, 141), Vector2(169, 142), Vector2(187, 129), Vector2(164, 145)],
	[Vector2(166, 142), Vector2(171, 146), Vector2(166, 130), Vector2(172, 153), Vector2(169, 138), Vector2(175, 139), Vector2(194, 132), Vector2(169, 145)],
]

var actor: ActorVisual
var phase: String = "idle"
var progress: float = 0.0
var heading: Vector2 = Vector2.RIGHT
var action_pose: Dictionary = {}
var hand_pixel: Vector2 = Vector2.ZERO
var render_octant: int = 0
var _hand: Sprite2D
var _flash: Sprite2D
var _light: PointLight2D


static func anchor(variant: int, octant: int, frame: int) -> Vector2:
	return ANCHORS[variant * 8 + octant][frame]


func _init(owner: ActorVisual) -> void:
	actor = owner


func build() -> void:
	_flash = Sprite2D.new()
	actor.add_child(_flash)
	if actor.is_enemy:
		return
	_hand = Sprite2D.new()
	var hand_material: ShaderMaterial = ShaderMaterial.new()
	hand_material.shader = HandShader
	_hand.material = hand_material
	actor._hold.add_child(_hand)
	_light = PointLight2D.new()
	_light.texture = MuzzleGlow
	_light.color = Color("ffc779")
	_light.energy = 0.42
	_light.shadow_enabled = false
	_light.enabled = false
	actor._hold.add_child(_light)


func apply(tint: Color) -> void:
	var body: Sprite2D = actor._body
	var hold: Node2D = actor._hold
	var weapon: Sprite2D = actor._weapon
	var view: WeaponPresentation = actor.weapon_view
	var facing: Vector2 = actor.screen_direction(actor._facing)
	render_octant = body.frame / 8 if body.texture == SurvivorVisualV1.SHEETS[actor.variant] else MotionAtlas.octant(facing)
	var frame: int = body.frame % 8 if body.texture == SurvivorVisualV1.SHEETS[actor.variant] else 0
	hand_pixel = anchor(actor.variant, render_octant, frame)
	var melee: bool = CombatEquipment.melee(String(view.id))
	var kick: float = actor._fire_clock / 0.12 if not melee else 0.0
	var angle: float = float(action_pose.get("weapon_angle", 0.0))
	var recoil: float = (3.2 if view.id == &"shotgun_v1" else 2.5 if view.id == &"long_rifle" else 1.8) * kick
	# Torso, real fist and gun recoil together. No independent bob detaches the grip.
	body.position -= facing * recoil
	hold.position = body.position
	hold.rotation = 0.0
	weapon.texture = view.texture
	weapon.offset = -view.grip_pixel
	weapon.position = (hand_pixel - Vector2(128, 224)) * ActorVisual.BODY_SCALE
	weapon.rotation = facing.angle() + angle
	# Back-view landmarks sit on the authored outer sleeve, not inside the torso.
	# A small outward cant keeps a north-facing barrel beside the shoulder/hair;
	# the complete body still occludes the stock and the far arm.
	if render_octant == 6:
		weapon.rotation += deg_to_rad(15.0) * signf(hand_pixel.x - 128.0)
	var foreshorten: float = 0.72 if render_octant in [2, 6] else 0.86 if render_octant in [1, 3, 5, 7] else 1.0
	weapon.scale = Vector2(foreshorten, -1.0 if facing.x < -0.1 else 1.0) * ActorVisual.field_scale(view.display_scale)
	weapon.self_modulate = tint
	weapon.z_index = 0
	# Keep the side silhouette visible without painting a gun over the back.
	actor.move_child(hold, 0 if render_octant in [5, 6, 7] else actor.get_child_count() - 1)
	actor._arms.trigger = weapon.position
	actor._arms.support = weapon.transform * ((view.muzzle_pixel - view.grip_pixel) * 0.32)
	actor._hold.move_child(weapon, actor._upper.get_index() + 1)
	_copy_frame(_hand, body)
	_hand.transform = hold.transform.affine_inverse() * body.transform
	_hand.visible = weapon.visible
	_hand.self_modulate = tint
	var material: ShaderMaterial = _hand.material as ShaderMaterial
	material.set_shader_parameter("grid", Vector2(body.hframes, body.vframes))
	material.set_shader_parameter("hand_pixel", hand_pixel)
	actor._hold.move_child(_hand, actor._hold.get_child_count() - 1)
	SurvivorVisualV1.pose_head(actor._head, body, hold)
	actor._hold.move_child(actor._head, actor._hold.get_child_count() - 1)
	actor._muzzle.position = weapon.transform * (view.muzzle_pixel - view.grip_pixel)
	actor._muzzle.rotation = weapon.rotation
	actor._muzzle.scale = Vector2.ONE * (0.55 + kick * 0.35)
	actor._muzzle.visible = weapon.visible and not melee and actor._fire_clock > 0.060
	actor._hold.move_child(actor._muzzle, actor._hold.get_child_count() - 1)
	_light.position = actor._muzzle.position
	_light.enabled = actor._muzzle.visible and actor.night_strength > 0.10
	_light.energy = 0.42 * kick
	update_impact()


func update_impact() -> void:
	_flash.visible = actor._hit_clock > 0.0
	if not _flash.visible:
		return
	_copy_frame(_flash, actor._body)
	_flash.transform = actor._body.transform
	# Reuse the source ink/palette rather than replacing the silhouette with white.
	# Only this overlay fades; the underlying actor stays opaque until corpse fade.
	_flash.material = actor._body.material
	_flash.set_instance_shader_parameter("night_readability", actor.night_strength)
	_flash.self_modulate = Color(1.5, 1.4, 1.2, 0.20 * pow(actor._hit_clock / 0.18, 2.0))
	actor.move_child(_flash, actor.get_child_count() - 1)


func rendered_muzzle() -> Vector2:
	return actor.position + actor._hold.transform * actor._muzzle.position


func light_enabled() -> bool:
	return _light != null and _light.enabled


func _copy_frame(target: Sprite2D, source: Sprite2D) -> void:
	target.texture = source.texture
	target.hframes = source.hframes
	target.vframes = source.vframes
	target.frame = source.frame
	target.offset = source.offset
	target.flip_h = source.flip_h
