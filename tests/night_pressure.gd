extends SceneTree
## PROJECT_TEMP engineering checks, not current Deadly Days parity claims.

var _checks: int = 0
var _failures: int = 0
var _results: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var director: ThreatDirector = ThreatDirector.new()
	for sample: Array in [[0.0,0,7.0],[69.99,0,7.0],[70.0,1,5.0],[104.99,1,5.0],[105.0,2,3.5],[140.0,3,2.5],[2000.0,3,2.5]]:
		director.update(sample[0],105.0,7.0)
		_expect(director.stage == sample[1] and is_equal_approx(director.interval,sample[2]), "configured natural stage/interval boundary")
	var changed: int = director.transitions
	director.update(150.0,105.0,7.0)
	_expect(director.transitions == changed and director.stage == ThreatDirector.Stage.DEEP, "repeated state cannot duplicate transition or rewind")
	for supply: MissionSupply in [preload("res://src/features/camp/scavenge.tres"),preload("res://src/features/camp/supermarket.tres")]:
		await _check_sortie(supply)
	await process_frame
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			var folder: String = argument.trim_prefix("--bh-progress=").get_base_dir()
			DirAccess.make_dir_recursive_absolute(folder)
			var file: FileAccess = FileAccess.open(folder.path_join("night-pressure-report.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"results":_results},"\t") + "\n")
			file.close()
	print("BH_NIGHT_PRESSURE checks=%d failures=%d" % [_checks,_failures])
	quit(0 if _failures == 0 else 1)


func _check_sortie(supply: MissionSupply) -> void:
	var sortie: Expedition = Expedition.new()
	sortie.supply = supply
	root.add_child(sortie)
	sortie.set_physics_process(false)
	var spawns: Array[Dictionary] = []
	sortie.spawn_resolved.connect(func(event: Dictionary) -> void: spawns.append(event))
	var warnings: Array[Dictionary] = []
	sortie.threat_changed.connect(func(event: Dictionary) -> void: warnings.append(event))
	_expect(sortie.threat.stage == ThreatDirector.Stage.CALM and sortie._spawn_count == 0, "new sortie starts clean")
	_expect(sortie._night_lighting.amount == 0.0, "calm retains the original ungraded street")
	sortie.step(7.0)
	_expect(spawns.size() == 1 and spawns[0].reason == "spawned" and sortie.enemies.size() == 1, "ordinary generator creates real enemy from first deadline")
	var enemy: FieldActor = sortie.enemies[0]
	var birth: Vector2 = Vector2(spawns[0].point[0],spawns[0].point[1])
	_expect(sortie.navigation.is_clear(birth) and not sortie.visible_world_rect().grow(ThreatRules.SCREEN_MARGIN).has_point(birth), "birth is legal and outside actual camera plus margin")
	_expect(sortie.navigation.path_between(birth,sortie.survivors[0].position).size() > 1, "birth reaches real party around existing geometry")
	_expect(sortie.survivors.all(func(actor: FieldActor) -> bool: return actor.position.distance_to(birth) >= ThreatRules.PARTY_DISTANCE), "birth keeps safe distance from every targetable survivor")
	_expect(enemy.max_health == 54.0 and enemy.speed == 34.0, "pressure never scales existing enemy health or speed")
	sortie.elapsed = 69.9
	sortie._spawn_clock = 0.25
	sortie.toggle_pause()
	var before: Dictionary = sortie.threat_status()
	var foot: Vector2 = enemy.position
	var cooldown: float = enemy.cooldown
	sortie.step(100.0)
	_expect(sortie.threat_status() == before and enemy.position == foot and enemy.cooldown == cooldown and warnings.is_empty(), "paused step crosses neither phase nor spawn nor AI/attack time")
	sortie.toggle_pause()
	sortie.step(0.1)
	_expect(sortie.threat.stage == ThreatDirector.Stage.LATE and warnings.size() == 1 and sortie._spawn_count == 1, "resume advances current simulation only, no frozen-time backlog")
	sortie.step(0.16)
	_expect(sortie._spawn_count == 2 and is_equal_approx(sortie._spawn_clock,5.0), "one due spawn resets exact current stage interval")
	var dusk_grade: float = sortie._night_lighting.amount
	sortie.toggle_pause()
	sortie.step(60.0)
	_expect(dusk_grade > 0.0 and dusk_grade < 1.0 and sortie._night_lighting.amount == dusk_grade,
		"dusk grade derives from simulation time and remains frozen under pause")
	sortie.toggle_pause()
	var second_birth: Vector2 = Vector2(spawns[-1].point[0],spawns[-1].point[1])
	_expect(second_birth.distance_to(sortie.enemies[0].position) >= ThreatRules.ENEMY_SEPARATION, "second birth cannot overlap the earlier enemy")
	sortie.step(500.0)
	_expect(sortie._spawn_count <= 3 and sortie.threat.stage == ThreatDirector.Stage.DEEP and sortie.phase != Expedition.Phase.FINISHED, "large unpaused delta coalesces to one attempt, zero deadline cannot force failure")
	_expect(sortie._night_lighting.amount == 1.0, "deep night reaches the bounded final grade")
	_expect(sortie.survivors.all(func(actor: FieldActor) -> bool: return actor.visual.modulate.r > 1.0)
		and sortie.enemies.all(func(actor: FieldActor) -> bool: return actor.visual.modulate.r > 1.0),
		"the live expedition clock applies night readability to crew and existing enemies")
	var heavy: FieldActor = sortie._make_actor(true, 900, enemy.position + Vector2(80, 0), {}, EnemyRules.HEAVY)
	sortie.enemies.append(heavy)
	heavy.take_damage(heavy.health + 1.0)
	heavy.visual.advance(0.4, Vector2.ZERO, Vector2.ZERO)
	sortie._feedback._refresh_night_lighting()
	_expect(heavy.visual.motion_state == &"defeated" and heavy.visual._body.frame == 15
		and heavy.visual.modulate.is_equal_approx(ActorVisual.NIGHT_GAIN)
		and is_equal_approx(float(heavy.visual._body.get_instance_shader_parameter("night_readability")), 1.0)
		and heavy.visual._body.self_modulate.r >= 0.85 and heavy.visual._body.self_modulate.a == 1.0,
		"real night refresh still compensates a fallen heavy before corpse fade")
	_check_special_night_compensation(sortie)
	for unit: FieldActor in sortie.enemies:
		unit.queue_free()
	sortie.enemies.clear()
	for index: int in range(ThreatRules.ENEMY_CAP):
		sortie.enemies.append(sortie._make_actor(true,100+index,Vector2(1800,1000)))
	sortie._spawn_clock = 0.0
	var count: int = sortie._spawn_count
	sortie.step(0.01)
	_expect(sortie._spawn_count == count and spawns[-1].reason == "capacity" and sortie._spawn_clock > 0.0, "full cap consumes deadline without overflow or queued debt")
	_expect(sortie.enemies.all(func(actor: FieldActor) -> bool: return actor.visual.modulate.r > 1.0),
		"enemies added after nightfall receive the current grade on the next refresh")
	for unit: FieldActor in sortie.enemies:
		unit.queue_free()
	sortie.enemies.clear()
	sortie.step(0.01)
	_expect(sortie._spawn_count == count, "capacity release cannot instantly dump accumulated enemies")
	sortie.camera.zoom = Vector2.ONE * 0.1
	sortie.camera.force_update_scroll()
	await process_frame
	sortie._spawn_clock = 0.0
	sortie.step(0.01)
	_expect(sortie._spawn_count == count and spawns[-1].reason == "no_safe_point", "camera covering all candidates safely skips generation")
	sortie._finish(true)
	before = sortie.threat_status()
	sortie.step(500.0)
	_expect(sortie.threat_status() == before, "finished sortie cannot advance pressure or generate enemies")
	sortie.queue_free()
	await process_frame
	_expect(not is_instance_valid(sortie), "leaving sortie releases director/actors/HUD with scene instead of retaining a global threat pool")


func _check_special_night_compensation(sortie: Expedition) -> void:
	var elapsed: float = sortie.elapsed
	var toxic_before: Dictionary = sortie.combat.toxic.duplicate(true)
	var specials: Array[FieldActor] = []
	for kind: String in [ScreamerPolicyV1.KIND, ToxicV1.KIND, BurstRuntimeV1.KIND,
		NightHoundV1.KIND, BossDefinition.KIND]:
		var rule_kind: String = EnemyRules.HEAVY if kind == BossDefinition.KIND else kind
		var actor: FieldActor = sortie._make_actor(true, 200 + specials.size(), Vector2(1800, 1000), {}, rule_kind)
		actor.visual.enemy_kind = kind
		actor.visual.advance(0.0, Vector2.ZERO, Vector2.RIGHT)
		sortie.enemies.append(actor)
		specials.append(actor)
	for amount: float in [0.85, 1.0, 0.0]:
		sortie.elapsed = sortie.tuning.daylight_seconds * amount
		sortie._feedback._refresh_night_lighting()
		for actor: FieldActor in specials:
			_expect(is_equal_approx(float(actor.visual._body.get_instance_shader_parameter("night_readability")),
				smoothstep(0.45, 1.0, amount))
				and float(actor.visual._body.get_instance_shader_parameter("special_night_lift")) > 0.0,
				"live atmosphere grades each special and boss at 0.85/1.0 and resets by day")
	sortie.elapsed = sortie.tuning.daylight_seconds
	var late_hound: FieldActor = sortie._make_actor(true, 210, Vector2(1800, 1000), {}, NightHoundV1.KIND)
	sortie.enemies.append(late_hound)
	specials.append(late_hound)
	sortie._feedback._refresh_night_lighting()
	_expect(is_equal_approx(float(late_hound.visual._body.get_instance_shader_parameter("night_readability")), 1.0)
		and is_equal_approx(float(late_hound.visual._body.get_instance_shader_parameter("special_night_lift")), NightHoundVisualV1.NIGHT_DETAIL_LIFT),
		"a hound spawned after nightfall receives both grades on the next real refresh")
	for actor: FieldActor in specials:
		sortie.enemies.erase(actor)
		actor.queue_free()
	# _make_actor registers toxic casters in combat missions; leave no fixture state behind.
	sortie.combat.toxic = toxic_before
	sortie.elapsed = elapsed
	sortie._feedback._refresh_night_lighting()


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	_results.append({"label":label,"passed":condition})
	if not condition:
		_failures += 1
		push_error("BH_NIGHT_PRESSURE " + label)
