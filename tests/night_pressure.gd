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
	var second_birth: Vector2 = Vector2(spawns[-1].point[0],spawns[-1].point[1])
	_expect(second_birth.distance_to(sortie.enemies[0].position) >= ThreatRules.ENEMY_SEPARATION, "second birth cannot overlap the earlier enemy")
	sortie.step(500.0)
	_expect(sortie._spawn_count <= 3 and sortie.threat.stage == ThreatDirector.Stage.DEEP and sortie.phase != Expedition.Phase.FINISHED, "large unpaused delta coalesces to one attempt, zero deadline cannot force failure")
	for unit: FieldActor in sortie.enemies:
		unit.queue_free()
	sortie.enemies.clear()
	for index: int in range(ThreatRules.ENEMY_CAP):
		sortie.enemies.append(sortie._make_actor(true,100+index,Vector2(1800,1000)))
	sortie._spawn_clock = 0.0
	var count: int = sortie._spawn_count
	sortie.step(0.01)
	_expect(sortie._spawn_count == count and spawns[-1].reason == "capacity" and sortie._spawn_clock > 0.0, "full cap consumes deadline without overflow or queued debt")
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


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	_results.append({"label":label,"passed":condition})
	if not condition:
		_failures += 1
		push_error("BH_NIGHT_PRESSURE " + label)
