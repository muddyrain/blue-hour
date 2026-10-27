extends SceneTree
## Project candidate semantics; no claim of exact V1.7.0F2 geometry or target priority.

var _results: Array[Dictionary] = []
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_pure_boundaries()
	await _muzzle_projection()
	await _actual_combat()
	await _actual_friendly()
	var folder: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			folder = argument.trim_prefix("--bh-progress=").get_base_dir()
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file: FileAccess = FileAccess.open(folder.path_join("combat-los-report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":_results.size(),"failures":_failures,"results":_results},"\t") + "\n")
		file.close()
	print("BH_COMBAT_LOS checks=%d failures=%d" % [_results.size(),_failures])
	quit(0 if _failures == 0 else 1)


func _body(point: Vector2, enemy: bool = false, living: bool = true, active: bool = true) -> AttackRules.Combatant:
	return AttackRules.Combatant.new(point,living,active,enemy)


func _pure_boundaries() -> void:
	var shooter: AttackRules.Combatant = _body(Vector2.ZERO)
	var target: AttackRules.Combatant = _body(Vector2(100,0),true)
	var origin: Vector2 = Vector2(0,-28)
	var empty: Array[ShotObstacle] = []
	var wall: Array[ShotObstacle] = [ShotObstacle.new(&"wall",Rect2(40,-10,20,20),true)]
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,empty).can_fire,"C01 clear target may fire")
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,wall).reason == &"blocked","C02 physical wall blocks ray in the shared hit plane")
	var decision: AttackRules.Decision = AttackRules.evaluate(shooter,target,origin,210,0,wall)
	_expect(decision.blocker_id == &"wall" and decision.blocked_at.is_equal_approx(Vector2(40,-28)),"first wall identity and exact segment intersection are explainable")
	wall[0].blocks_shots = false
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,wall).can_fire,"decorative/non-shot footprint is not silently treated as a wall")
	for distance: float in [209.999,210.0,210.001]:
		target.foot = Vector2(distance,0)
		_expect(AttackRules.evaluate(shooter,target,origin,210,0,empty).can_fire == (distance < 210),"C05 unchanged strict foot-range boundary %.3f" % distance)
	target.foot = Vector2(100,0)
	decision = AttackRules.evaluate(shooter,target,origin,210,0.1,empty)
	_expect(decision.targetable and not decision.can_fire and decision.reason == &"cooldown","cooldown retains eligible aim but prevents committing a second shot")
	target.alive = false
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,empty).reason == &"dead","dead targets are rejected before damage")
	target.alive = true
	target.available = false
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,empty).reason == &"target_unavailable","hidden/searching targets are unavailable")
	target.available = true
	target.is_enemy = false
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,empty).reason == &"friendly","C06 friendly body is never a damage target")
	target.is_enemy = true
	shooter.available = false
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,empty).reason == &"shooter_unavailable","searching/down shooter cannot attack")
	var bounds: Rect2 = Rect2(10,10,10,10)
	for pair: Array in [[Vector2(0,15),Vector2(30,15)], [Vector2(15,0),Vector2(15,30)],
			[Vector2(0,0),Vector2(30,30)], [Vector2(0,10),Vector2(30,10)],
			[Vector2(15,15),Vector2(15,15)], [Vector2(30,15),Vector2(0,15)]]:
		_expect(AttackRules._segment_entry(pair[0],pair[1],bounds) < INF,"closed physical segment handles crossings, tangents, inside/zero and reversed direction")
	_expect(AttackRules._segment_entry(Vector2(0,9),Vector2(30,9),bounds) == INF,"parallel ray just outside a wall stays clear")
	wall = [ShotObstacle.new(&"far",Rect2(70,-10,10,20),true),ShotObstacle.new(&"near",Rect2(30,-10,10,20),true)]
	shooter.available = true
	_expect(AttackRules.evaluate(shooter,target,origin,210,0,wall).blocker_id == &"near","reported blocker is first on ray, not first in array")


func _muzzle_projection() -> void:
	for variant: int in [0,1]:
		var visual: ActorVisual = ActorVisual.new()
		visual.variant = variant
		root.add_child(visual)
		for view: WeaponPresentation in [ActorVisual.CarbineView,ActorVisual.LongRifleView]:
			visual.set_weapon(view)
			for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1).normalized()]:
				visual.advance(0.1,Vector2(90,20),direction)
				visual.show_hit(Vector2.LEFT)
				var before: Dictionary = visual.presentation_state()
				var forecast: Vector2 = visual.aimed_shot_offset(direction)
				_expect(visual.presentation_state() == before,"candidate muzzle query has no visual side effects")
				visual.show_fire(direction)
				_expect(forecast.distance_to(visual.muzzle_offset()) < 0.001,"C08 both characters/guns/directions forecast exact committed muzzle during moving/hit")
		visual.queue_free()
	await process_frame


func _actual_combat() -> void:
	for supply: MissionSupply in [preload("res://src/features/camp/scavenge.tres"),preload("res://src/features/camp/supermarket.tres")]:
		var sortie: Expedition = Expedition.new()
		sortie.supply = supply
		sortie.is_practice = true
		sortie.los_practice = true
		root.add_child(sortie)
		sortie.set_physics_process(false)
		# Unit fixture controls scheduling only. Default health/damage and real attack code remain.
		sortie._spawn_clock = INF
		sortie._ai_clock = INF
		var events: Array[Dictionary] = []
		sortie.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event))
		var blocked: FieldActor = sortie._make_actor(true,20,sortie.los_setup.blocked_spawn)
		sortie.enemies.append(blocked)
		for actor: FieldActor in sortie.survivors:
			_expect(sortie.navigation.is_clear(actor.position) and sortie.navigation.is_clear(blocked.position),"fixture initializes actual legal map footprints")
			_expect(sortie.evaluate_attack(actor,blocked).reason == &"blocked","C02 both real character muzzle rays clip this authored wall corner")
			sortie.evaluate_attack(actor,blocked)
		sortie.step(0.01)
		_expect(blocked.health == sortie.tuning.enemy_health and events.is_empty(),"C02 blocked actual update does not damage or emit fake shot/hit/defeat")
		_expect(sortie.survivors[0].cooldown == 0 and sortie.survivors[0].visual._fire_clock == 0,"C02 blocked fire consumes no cooldown and causes no flash")
		sortie._shop._roof.modulate.a = 0.4
		_expect(sortie.evaluate_attack(sortie.survivors[0],blocked).reason == &"blocked","roof visual transparency never opens physical wall")
		var visible: FieldActor = sortie._make_actor(true,21,sortie.los_setup.visible_spawn)
		sortie.enemies.append(visible)
		_expect(sortie.survivors[0].position.distance_to(blocked.position) < sortie.survivors[0].position.distance_to(visible.position),"C04 blocked target is deliberately closer")
		sortie.step(0.01)
		_expect(visible.health < sortie.tuning.enemy_health and blocked.health == sortie.tuning.enemy_health,"C04 real shots choose farther legal target rather than nearer blocked target")
		_expect(events.any(func(event: Dictionary) -> bool: return event.kind == "shot" and event.target == 21 and event.applied_damage > 0 and event.predicted_muzzle_error < 0.001),"actual shot event retains damage, target and exact visible tracer source")
		sortie.toggle_pause()
		var elapsed: float = sortie.elapsed
		var cooldown: float = sortie.survivors[0].cooldown
		var health: float = visible.health
		sortie.command_move(sortie.los_setup.clear_goal)
		var point: Vector2 = sortie.survivors[0].position
		sortie.step(3.0)
		_expect(sortie.elapsed == elapsed and sortie.survivors[0].cooldown == cooldown and visible.health == health and sortie.survivors[0].position == point,"C07 pause accepts movement intent but freezes time/cooldown/health/position")
		sortie.toggle_pause()
		for tick: int in range(35):
			sortie.step(0.05)
		_expect(blocked.health < sortie.tuning.enemy_health and events.any(func(event: Dictionary) -> bool: return event.kind == "shot" and event.target == 20 and event.moving),"C03 normal path opens angle and shared actual moving combat resumes")
		var shot_bodies: int = 0
		for obstacle: ShotObstacle in sortie.shot_obstacles:
			shot_bodies += int(obstacle.blocks_shots)
		_expect(shot_bodies == sortie.layout.buildings().size() and sortie.navigation.obstacles == sortie.layout.blockers(),"shot semantics use same authored building bodies without changing navigation/fence/bus data")
		sortie.queue_free()
		await process_frame


func _actual_friendly() -> void:
	var sortie: Expedition = Expedition.new()
	sortie.supply = preload("res://src/features/camp/scavenge.tres")
	sortie.is_practice = true
	sortie.los_practice = true
	root.add_child(sortie)
	sortie.set_physics_process(false)
	sortie._spawn_clock = INF
	sortie._ai_clock = INF
	var enemy: FieldActor = sortie._make_actor(true,30,sortie.survivors[0].position + Vector2.UP * 120)
	sortie.enemies.append(enemy)
	var shots: Array[Dictionary] = []
	sortie.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind == "shot":
			shots.append(event)
	)
	sortie.step(0.01)
	_expect(shots.any(func(event: Dictionary) -> bool: return event.actor == 0) and shots.any(func(event: Dictionary) -> bool: return event.actor == 1),"C06 friend stands between shooter and enemy, both real guns still fire")
	_expect(sortie.crew_snapshot.is_empty() and sortie.survivors[0].health == 200 and sortie.survivors[1].health == 200 and enemy.health == 18,"C06 only hostile loses actual shared damage, neither friend takes friendly fire")
	sortie.queue_free()
	await process_frame


func _expect(value: bool, label: String) -> void:
	_results.append({"passed":value,"label":label})
	if not value:
		_failures += 1
		push_error("BH_COMBAT_LOS " + label)
