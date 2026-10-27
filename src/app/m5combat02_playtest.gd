class_name M5Combat02Playtest
extends M5UX01Playtest
## Opt-in, bounded read-only audit around the unchanged production simulation.

const MAX_SAMPLES: int = 24000

var _contact_mode: String = ""
var _current: Expedition
var _pre: Dictionary = {}
var _accepted: Array[int] = []
var _hits: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _lives: Dictionary = {}
var _audit_clock: float = 0.0
var _audit_serial: int = 0
var _sample_truncated: bool = false
var _anomalies: Array[String] = []
var _contact_pauses: Array[Dictionary] = []


func _run() -> void:
	process_physics_priority = 100
	var sampler: BeforeStep = BeforeStep.new()
	sampler.audit = self
	sampler.process_physics_priority = -100
	add_child(sampler)
	app.get_node("World").child_entered_tree.connect(_attach_audit)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m402-mode="):
			_contact_mode = argument.trim_prefix("--m402-mode=")
	if not _contact_mode.begins_with("contact-"):
		await super._run()
		return
	await _run_contact()


func _attach_audit(node: Node) -> void:
	if not node is Expedition:
		return
	_current = node as Expedition
	_audit_serial += 1
	_pre = {}
	_current.combat_feedback.connect(_audit_feedback)


func before_step(delta: float) -> void:
	_accepted.clear()
	if not is_instance_valid(_current):
		return
	var health: Array[float] = []
	var enemies: Dictionary = {}
	for actor: FieldActor in _current.survivors:
		health.append(actor.health)
	for enemy: FieldActor in _current.enemies:
		enemies[enemy.actor_id] = {"cooldown":enemy.cooldown,"point":enemy.position,"health":enemy.health}
	_pre = {"delta":delta,"elapsed":_current.elapsed,"health":health,"enemies":enemies,"damage":[0.0,0.0]}


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(_current) or _pre.is_empty():
		return
	var sortie: Expedition = _current
	for actor: FieldActor in sortie.survivors:
		var lost: float = float(_pre.health[actor.actor_id])-actor.health
		if not is_equal_approx(lost,float(_pre.damage[actor.actor_id])):
			_anomaly("health loss differs from actual hit events")
		if sortie.phase != Expedition.Phase.FINISHED:
			var label: Label = sortie._hud.view._members[actor.actor_id].health as Label
			if label.text != "生命 %d / %d" % [ceili(actor.health),ceili(actor.max_health)]:
				_anomaly("native HUD differs from actual health")
	_audit_clock += delta
	var sample_now: bool = _audit_clock >= 0.2
	if sample_now:
		_audit_clock = 0.0
	for enemy: FieldActor in sortie.enemies:
		if enemy.activity == FieldActor.Activity.DOWN:
			continue
		var target: FieldActor = sortie._nearest_target(enemy,sortie.survivors,INF)
		var distance: float = enemy.position.distance_to(target.position) if target != null else -1.0
		var row: Dictionary = _life(enemy)
		row["last_elapsed"] = sortie.elapsed
		row["last_point"] = enemy.position
		row["last_health"] = enemy.health
		if distance >= 0.0:
			row.min_distance = minf(float(row.min_distance),distance)
		if not sortie.is_paused and sortie.phase != Expedition.Phase.FINISHED:
			row.path_world_units += enemy.position.distance_to(_pre.enemies.get(enemy.actor_id,{}).get("point",enemy.position))
			if distance >= 0.0 and distance < 28.0:
				row.contact_seconds += delta
				if enemy.cooldown <= 0.0 and enemy.actor_id not in _accepted:
					_anomaly("eligible live enemy ended a production step with no attack and zero cooldown")
		if row.initial_path.is_empty() and enemy.path.size() > 1:
			row.initial_path = enemy.path.duplicate()
		if sample_now and _samples.size() < MAX_SAMPLES:
			var reason: String = "no_eligible_target" if target == null else ("out_of_range" if distance >= 28.0 else "cooldown")
			if enemy.actor_id in _accepted:
				reason = "accepted_actual_hit"
			if sortie.is_paused:
				reason = "paused"
			elif sortie.phase == Expedition.Phase.FINISHED:
				reason = "finished"
			_samples.append({"sortie":_audit_serial,"sim_elapsed":sortie.elapsed,"enemy_id":enemy.actor_id,
				"target_member_id":target.actor_id+1 if target != null else -1,"enemy_foot":enemy.position,
				"target_foot":target.position if target != null else Vector2.ZERO,"distance":distance,"cooldown":enemy.cooldown,
				"reason":reason,"paused":sortie.is_paused,"phase":sortie.phase,"stage":sortie.threat.stage,
				"path_points":enemy.path.size(),"path_index":enemy._path_index,
				"path_end":enemy.path[-1] if not enemy.path.is_empty() else enemy.position,
				"foot_clear":sortie.navigation.is_clear(enemy.position),"search_member_id":sortie.search_actor.actor_id+1 if sortie.search_actor != null else -1})
		elif sample_now:
			_sample_truncated = true


func _life(enemy: FieldActor) -> Dictionary:
	var key: String = "%d:%d" % [_audit_serial,enemy.actor_id]
	if not _lives.has(key):
		_lives[key] = {"sortie":_audit_serial,"map":String(_current.layout.id),"practice":_current.is_practice,
			"id":enemy.actor_id,"first_elapsed":_current.elapsed,"initial_point":enemy.position,"initial_health":enemy.max_health,
			"min_distance":100000.0,"contact_seconds":0.0,"path_world_units":0.0,"hits":0,"initial_path":PackedVector2Array(),"defeated":false}
	return _lives[key]


func _audit_feedback(event: Dictionary) -> void:
	var sortie: Expedition = _current
	if event.kind == "defeat":
		for enemy: FieldActor in sortie._corpses:
			if enemy.actor_id == int(event.actor):
				var life: Dictionary = _life(enemy)
				var nearest: FieldActor = sortie._nearest_target(enemy,sortie.survivors,INF)
				life.defeated = true
				life["death_elapsed"] = sortie.elapsed
				life["death_point"] = enemy.position
				life["death_distance"] = enemy.position.distance_to(nearest.position) if nearest != null else -1.0
				if nearest != null:
					life.min_distance = minf(float(life.min_distance),float(life.death_distance))
		return
	if event.kind != "hit":
		return
	var target: FieldActor = sortie.survivors[int(event.actor)]
	_pre.damage[target.actor_id] += float(event.applied_damage)
	var candidates: Array[FieldActor] = []
	for enemy: FieldActor in sortie.enemies:
		if enemy.activity == FieldActor.Activity.DOWN or enemy.actor_id in _accepted:
			continue
		var old: Dictionary = _pre.get("enemies",{}).get(enemy.actor_id,{})
		var reset_possible: bool = old.is_empty() or float(old.cooldown) <= float(_pre.delta)+0.00001
		var legal_target: bool = enemy.position.distance_to(target.position) < 28.0 and (target.activity == FieldActor.Activity.DOWN or sortie._nearest_target(enemy,sortie.survivors,28.0) == target)
		if reset_possible and is_equal_approx(enemy.cooldown,sortie.tuning.enemy_interval) and legal_target:
			candidates.append(enemy)
	if candidates.size() != 1:
		_anomaly("actual hit attacker cannot be uniquely identified from the production cooldown transition")
		return
	var attacker: FieldActor = candidates[0]
	_accepted.append(attacker.actor_id)
	var life: Dictionary = _life(attacker)
	life.hits += 1
	life.min_distance = minf(float(life.min_distance),attacker.position.distance_to(target.position))
	var audio: Dictionary = _audio_events.back() if not _audio_events.is_empty() else {}
	_hits.append({"sortie":_audit_serial,"sim_elapsed":sortie.elapsed,"enemy_id":attacker.actor_id,
		"target_member_id":target.actor_id+1,"enemy_foot":attacker.position,"target_foot":target.position,
		"distance":attacker.position.distance_to(target.position),"cooldown_before_step":_pre.enemies.get(attacker.actor_id,{}).get("cooldown",null),
		"spawned_this_step":not _pre.enemies.has(attacker.actor_id),
		"cooldown_after_attack":attacker.cooldown,"health_before":target.health+float(event.applied_damage),
		"health_after":target.health,"applied_damage":event.applied_damage,"target_activity":target.activity,
		"paused":sortie.is_paused,"phase":sortie.phase,"foot_clear":sortie.navigation.is_clear(attacker.position),
		"latest_real_audio_request":audio.duplicate(true),"movie_frame":Engine.get_frames_drawn()})
	if sortie.is_paused or sortie.phase == Expedition.Phase.FINISHED or target.activity == FieldActor.Activity.SEARCHING or float(event.applied_damage) <= 0.0:
		_anomaly("actual hit violates availability/pause/damage contract")


func _anomaly(message: String) -> void:
	if _anomalies.size() < 10:
		_anomalies.append(message)
		_expect(false,message)


func _run_contact() -> void:
	_mode = _contact_mode
	_sequence = _contact_mode
	DirAccess.make_dir_recursive_absolute(output_dir)
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path+".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,"frame":Engine.get_frames_drawn()}))
	await _click_screen(app._home_button.get_global_rect().get_center())
	_before = app.camp_snapshot()
	app.selected_supply = preload("res://src/features/camp/supermarket.tres") if _contact_mode.ends_with("market") else preload("res://src/features/camp/scavenge.tres")
	await _click_control("Interface/Screen/Title/Practice")
	var sortie: Expedition = app.expedition
	await _key(KEY_SPACE)
	_expect(sortie.is_practice and sortie.is_paused,"labelled isolated practice starts paused without campaign writes")
	if _contact_mode.contains("corner"):
		await _key(KEY_SPACE)
		while sortie.enemies.is_empty():
			await _wait(0.05)
		await _corner_case(sortie)
		if not sortie.is_paused:
			await _key(KEY_SPACE)
	elif _contact_mode.contains("search"):
		await _key(KEY_SPACE)
		var site: Expedition.SearchSite = sortie.search_site(&"cash")
		await _frame_at(sortie,site.door)
		await _click_world(sortie,sortie.layout.cash_block.get_center())
		sortie.command_move(site.door+Vector2(112,96))
		await _until_inside(sortie)
		await _key(KEY_SPACE)
		_expect(sortie.search_actor != null and not sortie.search_actor.visible,"original search is actually hidden before guard contact")
	else:
		var initialized: bool = false
		for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			var point: Vector2 = sortie.survivors[0].position+direction*240.0
			if sortie.navigation.is_clear(point) and sortie.navigation._segment_is_clear(point,sortie.survivors[0].position):
				_spawn_at_guard(sortie,direction*240.0,sortie.survivors[0])
				initialized = true
				break
		_expect(initialized,"ranged approach initialization uses a legal clear route on this actual layout")
		await _key(KEY_SPACE)
		await _until_enemies_clear(sortie)
		await _key(KEY_SPACE)
		_expect(sortie.survivors[0].health == 200.0 and sortie.survivors[1].health == 200.0,"a default ranged approach can genuinely end without contact damage")
		await _capture("contact-01-ranged-approach-no-damage")
	var guard: FieldActor = sortie.survivors[0]
	if sortie.search_actor == guard:
		guard = sortie.survivors[1]
	if sortie.is_paused:
		await _key(KEY_SPACE)
	var settling: int = 0
	while guard.activity == FieldActor.Activity.MOVING and settling < 300:
		await _wait(0.02)
		settling += 1
	await _key(KEY_SPACE)
	_expect(sortie.is_paused and guard.activity == FieldActor.Activity.IDLE,"visible guard reaches its ordinary goal before fixed-position contact")
	var directions: Array[Vector2] = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
	var added: int = 0
	for direction: Vector2 in directions:
		if sortie.navigation.is_clear(guard.position+direction*24.0) and added < 2:
			_spawn_at_guard(sortie,direction*24.0,guard)
			added += 1
	_expect(added == 2,"two ordinary enemy initialization feet are legal near the actual visible guard")
	sortie._show_notice("隔离近身接敌布置 · 默认敌人与数值 · 不是普通出生位置")
	sortie.camera.pan_by(guard.position-Vector2(0,64)-sortie.camera.position)
	await _capture("contact-02-before-real-contact")
	var count: int = _hits.size()
	await _key(KEY_SPACE)
	var limit: int = 0
	while _hits.size() < count+2 and limit < 100:
		await _wait(0.02)
		limit += 1
	await _key(KEY_SPACE)
	_expect(_hits.size() >= count+2 and guard.health < 200.0,"actual AI contact produces positive guard damage through original take_damage")
	await _capture("contact-03-real-damage-paused")
	var frozen: Dictionary = _pressure_state(sortie)
	var hit_count: int = _hits.size()
	await _wait(1.5)
	_expect(frozen == _pressure_state(sortie) and _hits.size() == hit_count,"pause longer than melee cooldown freezes health/AI/cooldown/search and attacks")
	_contact_pauses.append({"before":frozen,"after":_pressure_state(sortie),"hits_before":hit_count,"hits_after":_hits.size()})
	await _capture("contact-04-pause-still-frozen")
	await _key(KEY_SPACE)
	await _until_enemies_clear(sortie)
	_expect(_hits.size() > hit_count,"remaining close enemy can perform its next genuine cooldown attack")
	if sortie.search_actor != null:
		_expect(_hits.slice(count).all(func(hit: Dictionary) -> bool: return int(hit.target_member_id) == guard.actor_id+1),"hidden worker is never the target of real guard-contact hits")
	await _capture("contact-05-after-contact")
	var health: Array[float] = [sortie.survivors[0].health,sortie.survivors[1].health]
	sortie.request_extraction()
	await _check_finished(sortie)
	_expect(health == [sortie.survivors[0].health,sortie.survivors[1].health],"finished fixture cannot apply any later damage")
	await _capture("contact-06-result")
	await _click_control("Interface/Screen/Result/Continue")
	_expect(app.camp_snapshot() == _before and _hash(app.run_save.path) == _initial_save_hash,"isolated combat never banks practice wounds or changes v5 campaign")
	await _finish_proof()


func _spawn_at_guard(sortie: Expedition, offset: Vector2, guard: FieldActor) -> void:
	_expect(sortie.navigation.is_clear(guard.position+offset),"every explicitly initialized enemy begins on legal ground")
	if not sortie.navigation.is_clear(guard.position+offset):
		return
	var vector: Vector2 = guard.position+offset-sortie.survivors[0].position
	sortie.practice_incoming(vector.normalized(),vector.length())


func _until_enemies_clear(sortie: Expedition) -> void:
	var attempts: int = 0
	while not sortie.enemies.is_empty() and attempts < 500:
		await _wait(0.02)
		attempts += 1
	_expect(sortie.enemies.is_empty(),"original weapon/combat chain defeats the initialized ordinary enemies")


func _finish_proof() -> void:
	_expect(_anomalies.is_empty() and not _sample_truncated,"bounded read-only audit found no lost hits, HUD mismatch or eligible missed attacks")
	_write_json("enemy-contact.json",{"mode":_contact_mode,"pid":OS.get_process_id(),"samples":_samples,
		"lives":_lives.values(),"actual_hits":_hits,"pause_observations":_contact_pauses,"anomalies":_anomalies,
		"truncated":_sample_truncated,"scope":"Read-only pre/post production-step sampling. Accepted attacks are existing real hit events, uniquely attributed by the actual cooldown transition. Rejection labels are audit classifications, not a replacement gameplay predicate. Contact-* is explicitly initialized practice, never natural spawns. Default gameplay functions/stats unchanged."})
	await super._finish_proof()


class BeforeStep extends Node:
	var audit: M5Combat02Playtest


	func _physics_process(delta: float) -> void:
		audit.before_step(delta)
