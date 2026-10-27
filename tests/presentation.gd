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
		_expect(flash.distance_to(actor.visual.muzzle_offset()) < 0.001, "flash and combat trace use the rendered muzzle transform")
		var expected_row: int = state["row"]
		actor.visual.advance(0.25, Vector2.ZERO, direction)
		_expect(actor.visual.direction_row == expected_row, "unit aim and distance-scaled aim map to the same facing")
		if direction == Vector2.UP:
			_expect(actor.visual._head.z_index > actor.visual._weapon.z_index and actor.visual._weapon.z_index > actor.visual._upper.z_index,
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
		member.queue_free()
	readouts.queue_free()


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("BH_PRESENTATION " + label)
