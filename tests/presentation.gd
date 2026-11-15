extends SceneTree
## Real movement/presentation seams, rather than individual animation frame snapshots.

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var navigation: FieldNavigation = FieldNavigation.new()
	navigation.configure(preload("res://src/features/expedition/repair_lane.tres").blockers())
	for start: Vector2 in [Vector2(800, 704), Vector2(1012, 832)]:
		var actor: FieldActor = FieldActor.new()
		actor.is_enemy = true
		actor.speed = 34.0
		actor.aim = Vector2.ZERO
		actor.position = start
		root.add_child(actor)
		var target: Vector2 = start + Vector2(-208, 72)
		actor.command_path(navigation.path_between(actor.position, target))
		actor.advance(0.1)
		_expect(actor.position.y >= start.y and actor.visual.direction_row != 1,
				"southwest pursuit must not first walk north to a snapped grid origin")
		actor.queue_free()
	_check_weapon(ActorVisual.CarbineView)
	_check_weapon(ActorVisual.LongRifleView)
	_check_readouts()
	_check_dusk_tint()
	_check_actor_night_lighting()
	await process_frame
	print("BH_PRESENTATION checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_weapon(view: WeaponPresentation) -> void:
	var actor: FieldActor = FieldActor.new()
	root.add_child(actor)
	actor.visual.set_weapon(view)
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for direction: Vector2 in directions:
		actor.visual.advance(0.25, Vector2.ZERO, direction * 200.0)
		actor.visual.show_fire(direction)
		var state: Dictionary = actor.visual.presentation_state()
		_expect(state["hand"].distance_to(state["grip"]) < 0.001, "weapon texture grip remains at the drawn upper-body hand landmark")
		var flash: Vector2 = actor.visual.position + actor.visual._hold.transform * actor.visual._muzzle.position
		_expect(flash.distance_to(actor.visual.rendered_muzzle_offset()) < 0.001, "flash and combat trace use the rendered muzzle transform")
		var expected_row: int = state["row"]
		actor.visual.advance(0.25, Vector2.ZERO, direction)
		_expect(actor.visual.direction_row == expected_row, "unit aim and distance-scaled aim map to the same facing")
		if direction == Vector2.UP:
			_expect(actor.visual._head.get_index() > actor.visual._weapon.get_index() and actor.visual._weapon.get_index() > actor.visual._upper.get_index() and actor.visual._head.z_index == 0 and actor.visual._weapon.z_index == 0,
					"north weapon is in front of jacket and behind head/hair")
	actor.aim = Vector2.UP * 100.0
	actor.command_path(PackedVector2Array([Vector2(100, 0)]))
	actor.take_damage(4.0)
	actor.advance(0.1)
	actor.visual.show_fire(actor.aim)
	_expect(actor.position.x > 0.0 and actor.health == 196.0, "hit and moving fire never lock movement or repeat damage")
	var state: Dictionary = actor.visual.presentation_state()
	_expect(state["row"] == 1 and state["leg_row"] == 0, "eastward feet and northward aiming coexist")
	_expect(state["hand"].distance_to(state["grip"]) < 0.001, "hit/recoil transform retains hand contact")
	actor.visual.advance(0.4, Vector2.ZERO, Vector2.LEFT)
	_expect(actor.visual.motion_state == &"idle" and actor.visual.direction_row == 0, "hit/fire clear without stale direction or pose")
	actor.queue_free()


func _check_readouts() -> void:
	var members: Array[FieldActor] = []
	for index: int in range(2):
		var actor: FieldActor = FieldActor.new()
		actor.actor_id = index
		actor.position = Vector2(640, 360)
		root.add_child(actor)
		members.append(actor)
	var readouts: SquadReadouts = SquadReadouts.new()
	root.add_child(readouts)
	readouts.update_members(members, Transform2D.IDENTITY, Vector2(1280, 720))
	_expect(not readouts.entries[0]["rect"].intersects(readouts.entries[1]["rect"]), "crossing members retain separate number/health badges")
	_expect(members[0].position == members[1].position, "readout separation never changes gameplay positions")
	for member: FieldActor in members:
		member.position = Vector2(8, 80)
	readouts.update_members(members, Transform2D.IDENTITY, Vector2(1280, 720))
	_expect(not readouts.entries[0]["rect"].intersects(readouts.entries[1]["rect"]), "readouts remain separated after viewport-edge clamping")
	for member: FieldActor in members:
		member.position = Vector2(40, 640)
	var minimap: Rect2 = Rect2(8, 492, 156, 194)
	readouts.update_members(members, Transform2D.IDENTITY, Vector2(1280, 720), [minimap])
	_expect(members[0].position == Vector2(40, 640) and members[1].position == Vector2(40, 640), "HUD avoidance never changes gameplay positions")
	_expect(readouts.entries.all(func(entry: Dictionary) -> bool:
		return float(entry.get("alpha", 1.0)) < 0.05 or not Rect2(entry.rect).intersects(minimap)
	), "badges over the minimap are moved or faded, not left opaque on the panel")
	for member: FieldActor in members:
		member.queue_free()
	readouts.queue_free()


func _check_dusk_tint() -> void:
	var night: Color = Color(0.24, 0.28, 0.48)
	_expect(ExpeditionAtmosphere.tint_for(0.0).is_equal_approx(Color.WHITE), "day tint is white")
	_expect(ExpeditionAtmosphere.tint_for(1.0).is_equal_approx(night), "night tint keeps the deep blue")
	var mid: Color = ExpeditionAtmosphere.tint_for(0.65)
	var linear: Color = Color.WHITE.lerp(night, 0.65)
	_expect(mid.r - mid.b > linear.r - linear.b and mid.r > mid.b * 0.9, "mid-dusk is warmer than a linear grey-blue lerp")


func _check_actor_night_lighting() -> void:
	var enemies: Array[String] = [EnemyRules.NORMAL, EnemyRules.RUSH, EnemyRules.HEAVY,
		ScreamerVisualV1.KIND, CombatEnemyRules.TOXIC, NightHoundV1.KIND]
	for family: int in range(5 + enemies.size()):
		var actor: FieldActor = FieldActor.new()
		actor.is_enemy = family >= 5
		if actor.is_enemy:
			actor.enemy_behavior = EnemyBehavior.new()
			actor.enemy_behavior.kind = enemies[family - 5]
		else:
			actor.definition_id = StringName("crew_%d" % (family + 1))
		root.add_child(actor)
		var visual: ActorVisual = actor.visual
		visual.advance(0.4, Vector2.RIGHT * 34.0, Vector2.RIGHT)
		var pose: Dictionary = visual.presentation_state()
		var palette: Material = visual._body.material
		var previous_gain: float = 1.0
		for amount: float in [0.0, 0.45, 0.65, 0.85, 1.0]:
			visual.set_night_lighting(amount)
			_expect(visual.presentation_state() == pose and visual._body.material == palette,
				"night lighting preserves directions, action clocks, grip and species material")
			if amount <= 0.45:
				_expect(visual.modulate.is_equal_approx(Color.WHITE), "day and warm dusk keep original actor colour")
			else:
				_expect(visual.modulate.r > previous_gain and visual.modulate.r <= 1.5,
					"dusk to deep night gradually lifts all five crew and every species within a bounded gain")
			previous_gain = visual.modulate.r
			if family in range(5, 8):
				var strength: float = float(visual._body.get_instance_shader_parameter("night_readability"))
				_expect(is_zero_approx(strength) if amount <= 0.45 else strength > 0.0 and strength <= 1.0,
					"basic infected palette receives this actor's night strength")
		var night: Color = ExpeditionAtmosphere.tint_for(1.0) * visual.modulate
		_expect(night.b > night.g and night.g > night.r and night.g < 0.5,
			"actor compensation retains a dark blue ambient instead of daylight")
		if family in range(5, 8):
			var day_actor: FieldActor = FieldActor.new()
			day_actor.is_enemy = true
			root.add_child(day_actor)
			day_actor.visual.set_night_lighting(0.0)
			_expect(is_zero_approx(float(day_actor.visual._body.get_instance_shader_parameter("night_readability")))
				and is_equal_approx(float(visual._body.get_instance_shader_parameter("night_readability")), 1.0),
				"shared palette does not leak a night actor's grade into a daylight actor")
			day_actor.queue_free()
		visual.set_night_lighting(0.0)
		_expect(visual.modulate.is_equal_approx(Color.WHITE), "returning to day clears actor compensation")
		actor.queue_free()


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("BH_PRESENTATION " + label)
