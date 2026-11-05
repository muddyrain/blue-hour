extends SceneTree
## Pure geometry only. A's original-world tests own ammo, XP and persistence evidence.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("COMBAT_PATTERNS_V1_FAIL " + label)


func target(id: int, point: Vector2, alive: bool = true, available: bool = true) -> Dictionary:
	return {"id":id, "foot":point, "alive":alive, "available":available}


func hits(plan: Dictionary, id: int) -> int:
	for row: Dictionary in plan.targets:
		if row.id == id:
			return int(row.hits)
	return 0


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var clear: Array[ShotObstacle] = []
	var none: Array[Dictionary] = []
	var axis: Vector2 = Vector2.RIGHT
	var origin: Vector2 = Vector2.ZERO
	var muzzle: Vector2 = Vector2.UP * AttackRules.HIT_HEIGHT
	expect(CombatPatternsV1.axe_plan(origin, axis, none, clear).is_empty(), "axe without targets")
	var close: Array[Dictionary] = [target(0, Vector2(30, 0))]
	var copy: Array[Dictionary] = close.duplicate(true)
	var axe: Array[Dictionary] = CombatPatternsV1.axe_plan(origin, axis, close, clear)
	expect(axe == [{"id":0, "hits":1}], "axe ID zero legal and hit once")
	expect(close == copy, "axe planner never changes input")
	var edge: Array[Dictionary] = [target(1, Vector2(50, 0)), target(2, Vector2(49.99, 0))]
	expect(CombatPatternsV1.axe_plan(origin, axis, edge, clear) == [{"id":2, "hits":1}], "axe strictly below fifty")
	var cone: Array[Dictionary] = [target(1, Vector2.RIGHT.rotated(deg_to_rad(54.9)) * 30),
		target(2, Vector2.RIGHT.rotated(deg_to_rad(-54.9)) * 30),
		target(3, Vector2.RIGHT.rotated(deg_to_rad(55.1)) * 30),
		target(4, Vector2.RIGHT.rotated(deg_to_rad(-55.1)) * 30), target(5, Vector2(-5, 0))]
	axe = CombatPatternsV1.axe_plan(origin, axis, cone, clear)
	expect(axe.size() == 2 and axe[0].id in [1, 2] and axe[1].id in [1, 2], "axe one hundred ten degree sector")
	var crowded: Array[Dictionary] = [target(8, Vector2(40, 0)), target(6, Vector2(20, 0)),
		target(3, Vector2(30, 0)), target(2, Vector2(20, 0)), target(9, Vector2(10, 0))]
	axe = CombatPatternsV1.axe_plan(origin, axis, crowded, clear)
	expect(axe == [{"id":9, "hits":1}, {"id":2, "hits":1}, {"id":6, "hits":1}], "axe at most three by distance then stable ID")
	var invalid: Array[Dictionary] = [target(1, Vector2(10, 0), false), target(2, Vector2(20, 0), true, false)]
	expect(CombatPatternsV1.axe_plan(origin, axis, invalid, clear).is_empty(), "axe rejects dead and unavailable")
	var wall: Array[ShotObstacle] = [ShotObstacle.new(&"wall", Rect2(20, -40, 3, 80), true)]
	expect(CombatPatternsV1.axe_plan(origin, axis, close, wall).is_empty(), "axe cannot cross solid wall")
	var decor: Array[ShotObstacle] = [ShotObstacle.new(&"paint", Rect2(20, -40, 3, 80), false)]
	expect(CombatPatternsV1.axe_plan(origin, axis, close, decor).size() == 1, "nonblocking decor ignored")
	var distant_wall: Array[ShotObstacle] = [ShotObstacle.new(&"after", Rect2(40, -40, 3, 80), true)]
	expect(CombatPatternsV1.axe_plan(origin, axis, close, distant_wall).size() == 1, "wall behind victim irrelevant")
	var behind: Array[Dictionary] = [target(4, Vector2(-30, 0))]
	expect(CombatPatternsV1.axe_plan(origin, Vector2.LEFT, behind, clear).size() == 1, "locked left heading")
	expect(CombatPatternsV1.axe_plan(origin, axis, behind, clear).is_empty(), "same victim outside locked facing")
	var extended: Array[Dictionary] = [target(4, Vector2(55, 0))]
	expect(CombatPatternsV1.axe_plan(origin, axis, extended, clear).is_empty() and CombatPatternsV1.axe_plan(origin, axis, extended, clear, 57.5).size() == 1, "reach changes distance alone")
	var duplicate: Array[Dictionary] = [target(1, Vector2(10, 0)), target(1, Vector2(20, 0))]
	expect(CombatPatternsV1.axe_plan(origin, axis, duplicate, clear).is_empty(), "duplicate identity fails closed")
	expect(CombatPatternsV1.axe_plan(origin, Vector2.ZERO, close, clear).is_empty(), "zero heading has no implicit attack")
	var shot: Dictionary = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, close, clear)
	expect(shot.rays.size() == 5, "one trigger plans exactly five rays")
	expect(shot.targets == [{"id":0, "hits":5}], "all five nearby pellets aggregate one enemy row")
	expect(hits(shot, 0) * CombatPatternsV1.POLICY.shotgun.damage == 45.0, "five hits yield forty five from nine per pellet")
	expect(close == copy, "shotgun planner never changes input")
	for ray: Dictionary in shot.rays:
		expect(ray.id == 0 and ray.from == muzzle and ray.to.x < 30.0, "each ray terminates on first circle")
	var line: Array[Dictionary] = [target(8, Vector2(90, 0)), target(4, Vector2(30, 0))]
	shot = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, line, clear)
	expect(hits(shot, 4) == 5 and hits(shot, 8) == 0, "pellets do not penetrate nearer enemy")
	var tied: Array[Dictionary] = [target(7, Vector2(30, 0)), target(2, Vector2(30, 0))]
	shot = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, tied, clear)
	expect(hits(shot, 2) == 5 and hits(shot, 7) == 0, "first collision tie chooses stable lower ID")
	var spread: Array[Dictionary] = [target(3, Vector2(110, 24)), target(1, Vector2(110, 0)), target(2, Vector2(110, -24))]
	shot = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, spread, clear)
	expect(hits(shot, 1) == 3 and hits(shot, 2) == 1 and hits(shot, 3) == 1, "five deterministic angles spread across three victims")
	expect(shot.targets.size() == 3, "aggregate has exactly one row per victim")
	var reversed: Array[Dictionary] = spread.duplicate(true)
	reversed.reverse()
	expect(CombatPatternsV1.shotgun_plan(origin, muzzle, axis, reversed, clear) == shot, "target iteration order cannot reroll pellets")
	var shot_wall: Array[ShotObstacle] = [ShotObstacle.new(&"shot_wall", Rect2(10, -40, 3, 80), true)]
	shot = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, close, shot_wall)
	expect(shot.targets.is_empty(), "wall before circle blocks every pellet")
	for ray: Dictionary in shot.rays:
		expect(ray.id == -1 and is_equal_approx(ray.to.x, 10.0), "blocked endpoint uses projected physical wall")
	var wall_tie: Array[ShotObstacle] = [ShotObstacle.new(&"tie", Rect2(18, -40, 2, 80), true)]
	shot = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, close, wall_tie)
	expect(shot.rays[2].id == -1, "wall wins exact circle-entry tie")
	shot = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, none, clear)
	expect(shot.targets.is_empty() and shot.rays.size() == 5, "empty geometry has no fabricated victim")
	for index: int in range(5):
		var direction: Vector2 = axis.rotated(deg_to_rad(float(CombatPatternsV1.POLICY.shotgun.angles_degrees[index])))
		expect(shot.rays[index].id == -1 and shot.rays[index].to == muzzle + direction * 150.0, "fixed angle and unblocked endpoint")
	var shot_edge: Array[Dictionary] = [target(1, Vector2(150, 0)), target(2, Vector2(160, 0))]
	expect(CombatPatternsV1.shotgun_plan(origin, Vector2(40, -28), axis, shot_edge, clear).targets.is_empty(), "muzzle and circle do not extend strict foot range")
	var inside_edge: Array[Dictionary] = [target(1, Vector2(149.99, 0))]
	expect(hits(CombatPatternsV1.shotgun_plan(origin, muzzle, axis, inside_edge, clear), 1) == 1, "central pellet reaches just inside foot limit")
	expect(hits(CombatPatternsV1.shotgun_plan(origin, muzzle, axis, shot_edge, clear, 172.5), 1) >= 1, "reach extends shotgun distance")
	var tangent: Array[Dictionary] = [target(6, Vector2(70, 12))]
	shot = CombatPatternsV1.shotgun_plan(origin, muzzle, axis, tangent, clear)
	expect(shot.rays[2].id == 6, "circle tangent is a collision")
	expect(CombatPatternsV1._circle_entry(Vector2.ZERO, Vector2(100, 0), Vector2(112, 0), 12.0) == 1.0, "circle endpoint collision inclusive like rectangles")
	expect(CombatPatternsV1._circle_entry(Vector2.ZERO, Vector2(100, 0), Vector2.ZERO, 12.0) == 0.0, "ray starting in circle collides immediately")
	expect(CombatPatternsV1.shotgun_plan(origin, muzzle, axis, duplicate, clear).rays.is_empty(), "duplicate identities fail closed before trigger planning")
	expect(CombatPatternsV1.shotgun_plan(origin, muzzle, Vector2.ZERO, close, clear).rays.is_empty(), "no implicit default shotgun heading")
	expect(CombatPatternsV1.shotgun_plan(origin, muzzle, axis, close, clear, NAN).rays.is_empty(), "nonfinite reach fails closed")
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		var directional: Array[Dictionary] = [target(0, direction * 30.0)]
		shot = CombatPatternsV1.shotgun_plan(origin, muzzle, direction, directional, clear)
		expect(hits(shot, 0) == 5, "four principal directions use same pellet geometry")
		var visual: CombatWeaponVisualV1 = CombatWeaponVisualV1.new()
		visual.present(CombatPatternsV1.AXE_ID, direction, "windup", 1.0)
		var windup: Dictionary = visual.pose()
		visual.present(CombatPatternsV1.AXE_ID, direction, "recover", 0.0)
		expect(windup.weapon_angle != visual.pose().weapon_angle, "axe has distinct windup and hit pose in each direction")
		visual.present(CombatPatternsV1.AXE_ID, direction, "recover", 1.0)
		expect(visual.pose().weapon_angle == 0.0 and visual.pose().hold_twist == 0.0, "axe recovery returns neutral without new timer")
		visual.free()
	var axe_definition: WeaponDefinition = preload("res://assets/combat_v1/weapons/fire_axe_v1.tres")
	var shotgun_definition: WeaponDefinition = preload("res://assets/combat_v1/weapons/shotgun_v1.tres")
	expect(axe_definition.damage == CombatPatternsV1.POLICY.axe.damage and axe_definition.interval == CombatPatternsV1.POLICY.axe.interval and axe_definition.shot_range == CombatPatternsV1.POLICY.axe.range, "axe resource matches centralized policy")
	expect(shotgun_definition.damage == CombatPatternsV1.POLICY.shotgun.damage and shotgun_definition.interval == CombatPatternsV1.POLICY.shotgun.interval and shotgun_definition.shot_range == CombatPatternsV1.POLICY.shotgun.range, "shotgun resource matches centralized policy")
	expect(axe_definition.presentation.texture.get_size() == Vector2(160, 96) and shotgun_definition.presentation.texture.get_size() == Vector2(176, 80), "original SVGs imported at declared dimensions")
	var holder: Node2D = Node2D.new()
	holder.position = Vector2(400, 300)
	root.add_child(holder)
	var actor_visual: ActorVisual = ActorVisual.new()
	holder.add_child(actor_visual)
	await process_frame
	actor_visual.set_weapon(shotgun_definition.presentation)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		actor_visual.show_fire(direction)
		var actual_pose: Dictionary = actor_visual.presentation_state()
		var visual_muzzle: Vector2 = holder.position + actor_visual.muzzle_offset(direction)
		var planned_muzzle: Vector2 = holder.position + actor_visual.aimed_shot_offset(direction)
		var logical_origin: Vector2 = CombatEquipment.shot_origin(holder.position)
		expect(actual_pose.grip.distance_to(actual_pose.hand) < 0.0001, "actual four direction grip stays on original author hand")
		expect(visual_muzzle.distance_to(planned_muzzle) < 0.0001, "four direction real and predicted display muzzle agree")
		expect(logical_origin == holder.position + Vector2.UP * AttackRules.HIT_HEIGHT and logical_origin != visual_muzzle, "shotgun uses foot hit plane independent of protruding display barrel")
		var contact_target: Array[Dictionary] = [target(0, holder.position + direction * FieldContacts.APPROACH)]
		shot = CombatPatternsV1.shotgun_plan(holder.position, logical_origin, direction, contact_target, clear)
		expect(hits(shot, 0) == 5, "actual four direction shotgun setup hits contact target at twenty four pixels")
		var wall_center: Vector2 = holder.position + direction * 12.0
		var contact_wall: Array[ShotObstacle] = [ShotObstacle.new(&"contact_wall", Rect2(wall_center - Vector2(4, 4), Vector2(8, 8)), true)]
		shot = CombatPatternsV1.shotgun_plan(holder.position, logical_origin, direction, contact_target, contact_wall)
		expect(shot.targets.is_empty() and shot.rays.size() == 5, "four direction wall before victim blocks despite protruding display barrel")
		for ray: Dictionary in shot.rays:
			expect(ray.id == -1, "contact wall is first collision for every pellet")
	holder.queue_free()
	await process_frame
	print(JSON.stringify({"checks":checks, "failures":failures, "scope":"pure_geometry_and_read_only_pose", "policy":CombatPatternsV1.POLICY}))
	quit(0 if failures == 0 else 1)
