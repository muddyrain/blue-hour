class_name CombatWeaponVisualV1
extends Node2D
## Read-only pose adapter. The authority supplies phase/progress and owns every clock.

var _actor: Node2D
var _mode: String = ""
var _heading: Vector2 = Vector2.RIGHT
var _phase: String = "idle"
var _progress: float = 0.0
var _grip: Vector2 = Vector2.ZERO


func _draw() -> void:
	if not visible or _mode != CombatPatternsV1.AXE_ID:
		return
	var pivot: Vector2 = _grip
	var alpha: float = 0.0
	var start: float = _heading.angle() - deg_to_rad(55.0)
	var finish: float = start
	if _phase == "strike":
		finish = start + deg_to_rad(110.0) * maxf(0.25, _progress)
		alpha = 0.70 * (1.0 - 0.35 * _progress)
	elif _phase in ["recover", "recovery"] and _progress < 0.20:
		finish = start + deg_to_rad(110.0)
		alpha = 0.55 * (1.0 - _progress / 0.20)
	if alpha > 0.0:
		draw_arc(pivot, 34.0, start, finish, 16, Color(0.91, 0.83, 0.58, alpha * 0.25), 8.0, true)
		draw_arc(pivot, 36.0, start, finish, 16, Color(1.0, 0.89, 0.68, alpha), 2.2, true)


func bind_actor_visual(actor: Node2D) -> void:
	_actor = actor


func present(mode: String, heading: Vector2, phase: String, progress: float) -> void:
	_mode = mode
	_heading = heading.normalized() if heading.is_finite() and heading.length_squared() > 0.0 else Vector2.RIGHT
	_phase = phase
	_progress = clampf(progress, 0.0, 1.0) if is_finite(progress) else 0.0
	visible = mode in [CombatPatternsV1.AXE_ID, CombatPatternsV1.SHOTGUN_ID]
	if is_instance_valid(_actor):
		_apply_actor_pose()
	queue_redraw()


func pose() -> Dictionary:
	var angle: float = 0.0
	var twist: float = 0.0
	var recoil: float = 0.0
	var support_fraction: float = 0.32
	if _mode == CombatPatternsV1.AXE_ID:
		var mirror: float = -1.0 if _heading.x < -0.1 else 1.0
		support_fraction = 0.47
		match _phase:
			"windup":
				angle = lerpf(-0.20, -1.12, _progress) * mirror
				twist = -0.09 * _progress * mirror
			"strike":
				angle = lerpf(-1.12, 0.96, _progress) * mirror
				twist = lerpf(-0.09, 0.10, _progress) * mirror
			"recover", "recovery":
				var settle: float = smoothstep(0.0, 0.45, _progress)
				angle = 0.96 * (1.0 - settle) * mirror
				twist = 0.10 * (1.0 - settle) * mirror
	elif _mode == CombatPatternsV1.SHOTGUN_ID:
		if _phase in ["strike", "fire"]:
			recoil = 3.2 * (1.0 - _progress)
			angle = -0.065 * (1.0 - _progress) * (-1.0 if _heading.x < -0.1 else 1.0)
		elif _phase in ["reload", "reloading"]:
			# A visible pump/hand movement follows the saved reload fraction, never a new timer.
			angle = 0.20 * sin(_progress * PI)
			support_fraction = 0.32 - 0.12 * sin(_progress * PI * 4.0)
	return {"weapon_angle":angle, "hold_twist":twist, "recoil":recoil, "support_fraction":support_fraction}


func _apply_actor_pose() -> void:
	var weapon: Sprite2D = _actor.get("_weapon") as Sprite2D
	var hold: Node2D = _actor.get("_hold") as Node2D
	var arms: MotionHands = _actor.get("_arms") as MotionHands
	var muzzle: Polygon2D = _actor.get("_muzzle") as Polygon2D
	if weapon == null or hold == null or arms == null:
		return
	var view: WeaponPresentation = _actor.get("weapon_view") as WeaponPresentation
	if view == null or not visible:
		return
	var values: Dictionary = pose()
	weapon.rotation += float(values.weapon_angle)
	weapon.position -= _heading * float(values.recoil)
	hold.rotation += float(values.hold_twist)
	arms.trigger = weapon.position
	arms.support = weapon.transform * ((view.muzzle_pixel - view.grip_pixel) * float(values.support_fraction))
	arms.queue_redraw()
	_grip = hold.transform * weapon.position
	if muzzle != null:
		muzzle.visible = false if _mode == CombatPatternsV1.AXE_ID else muzzle.visible
		muzzle.position = weapon.transform * (view.muzzle_pixel - view.grip_pixel)
		muzzle.rotation = weapon.rotation
