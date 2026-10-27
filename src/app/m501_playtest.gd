class_name M501Playtest
extends M403Playtest
## Native wall-corner proof on real map components, separate from normal mission regression.

var _los_mode: String = ""
var _observations: Array[Dictionary] = []
var _shot_error: float = 0.0
var _resume_capture: bool = false
var _range_retreat: bool = false
var _retreat_goal: Vector2


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m402-mode="):
			_los_mode = argument.trim_prefix("--m402-mode=")
	if not _los_mode.begins_with("los-"):
		await super._run()
		return
	_sequence = _los_mode
	_identity_mode = _los_mode
	_mode = _los_mode
	DirAccess.make_dir_recursive_absolute(output_dir)
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path + ".bak")
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,"frame":Engine.get_frames_drawn()}))
	await _capture("m501-001-home")
	await _click_screen(app._home_button.get_global_rect().get_center())
	_before = app.camp_snapshot()
	await _profiles()
	await _key(KEY_ESCAPE)
	await _click_control("Interface/Screen/Title/Practice")
	var practice: Expedition = app.expedition
	_expect(practice.is_practice and practice.los_practice and practice.los_setup != null,"explicit practice uses authored normal-map geometry with initialization-only arrangement")
	for actor: FieldActor in practice.survivors:
		var item: Dictionary = WeaponInventory.for_member(_before, actor.actor_id + 1)
		_expect(actor.weapon_instance_id == item.instance_id and actor.weapon_definition.id == StringName(item.weapon_id),"practice still reads each real saved weapon instance/definition")
	var limit: int = 0
	while practice.enemies.is_empty() and limit < 100:
		await _wait(0.05)
		limit += 1
	_expect(practice.enemies.size() == 1,"one ordinary enemy initialized at explicit fixture spawn")
	if _los_mode == "los-range":
		await _range_case(practice)
	else:
		await _corner_case(practice)
	practice.request_extraction()
	await _capture("m501-practice-result")
	await _check_finished(practice)
	await _click_control("Interface/Screen/Result/Continue")
	_expect(app.camp_snapshot() == _before and _hash(app.run_save.path) == _initial_save_hash,"isolated LOS combat never settles, consumes food or mutates saved campaign")
	await _finish_proof()


func _corner_case(practice: Expedition) -> void:
	# Show that both zero-cooldown guns stay quiet while simulation actually advances.
	var active_clock: float = practice.elapsed
	await _wait(0.6)
	_expect(practice.elapsed > active_clock + 0.5 and _feedback.is_empty(),"C02 live, unpaused wall interval produces no shots despite ready cooldowns")
	await _key(KEY_SPACE)
	var wall_enemy: FieldActor = practice.enemies[0]
	for actor: FieldActor in practice.survivors:
		var decision: AttackRules.Decision = practice.evaluate_attack(actor,wall_enemy)
		_observe(actor,wall_enemy,decision,"wall_before")
		_expect(decision.reason == &"blocked" and decision.blocker_id == &"cash_wall","C02 actual predicted muzzle ray is blocked by real cash building body")
	_expect(_feedback.is_empty() and wall_enemy.health == practice.tuning.enemy_health and _audio_accepted("fire") == 0 and _audio_accepted("hit") == 0,"C02 no fake shots/damage/fire or hit sound while wall blocks")
	await _capture("m501-002-wall-blocks-both")
	await _wait(1.8)
	var first_event: int = _feedback.size()
	if _los_mode.contains("choice"):
		var offset: Vector2 = practice.los_setup.visible_spawn - practice.survivors[0].position
		practice.practice_incoming(offset.normalized(),offset.length())
		var visible: FieldActor = practice.enemies[1]
		for actor: FieldActor in practice.survivors:
			var decision: AttackRules.Decision = practice.evaluate_attack(actor,visible)
			_observe(actor,visible,decision,"visible_alternative")
			_expect(decision.targetable and actor.position.distance_to(wall_enemy.position) < decision.distance,"C04 legal alternative is farther than the blocked target")
		await _capture("m501-003-one-blocked-one-clear")
		await _key(KEY_SPACE)
		await _wait(0.22)
		var shots: Array[Dictionary] = []
		for event: Dictionary in _feedback.slice(first_event):
			if event.kind == "shot":
				shots.append(event)
		_expect(not shots.is_empty() and shots.all(func(event: Dictionary) -> bool: return event.target == visible.actor_id),"C04 initial real volleys choose visible target instead of the closer wall target")
		await _capture("m501-004-visible-target-hit")
		return
	var clock: float = practice.elapsed
	var before: Dictionary = _world_state(practice)
	var cooldowns: Array[float] = [practice.survivors[0].cooldown,practice.survivors[1].cooldown]
	await _click_world(practice,practice.los_setup.clear_goal)
	_expect(practice.survivors[0].activity == FieldActor.Activity.MOVING,"C07 movement command is accepted while paused")
	var paused: Dictionary = _world_state(practice)
	await _wait(1.0)
	_expect(practice.elapsed == clock and _world_state(practice) == paused and practice.survivors[0].cooldown == cooldowns[0] and practice.survivors[1].cooldown == cooldowns[1],"C07 pause freezes time, health, animation and cooldown after accepting order")
	_expect(before.actors[0].position == paused.actors[0].position,"paused order cannot teleport actors")
	await _capture("m501-003-paused-order-around-corner")
	_resume_capture = true
	await _key(KEY_SPACE)
	var attempts: int = 0
	while not _feedback.any(func(event: Dictionary) -> bool: return event.kind == "shot" and event.target == wall_enemy.actor_id) and attempts < 100:
		await _wait(0.05)
		attempts += 1
	_expect(_feedback.any(func(event: Dictionary) -> bool: return event.kind == "shot" and event.target == wall_enemy.actor_id and event.moving and event.applied_damage > 0),"C03 actual path around corner automatically restores moving fire with real damage")
	await _capture("m501-004-corner-open-fire")
	await _wait(1.5)
	for actor: FieldActor in practice.survivors:
		if is_instance_valid(wall_enemy) and wall_enemy.health > 0:
			_observe(actor,wall_enemy,practice.evaluate_attack(actor,wall_enemy),"after_corner")


func _range_case(practice: Expedition) -> void:
	var target: FieldActor = practice.enemies[0]
	await _key(KEY_SPACE)
	for actor: FieldActor in practice.survivors:
		var decision: AttackRules.Decision = practice.evaluate_attack(actor,target)
		_observe(actor,target,decision,"range_outside")
		_expect(decision.reason == &"out_of_range","C05 initial ordinary target is beyond unchanged range")
	await _capture("m501-range-01-outside")
	_retreat_goal = practice.los_setup.starts[0] + Vector2(-80,48)
	_range_retreat = true
	await _click_world(practice,practice.los_setup.clear_goal)
	await _key(KEY_SPACE)
	var attempts: int = 0
	while not _feedback.any(func(event: Dictionary) -> bool: return event.kind == "shot") and attempts < 160:
		await _wait(0.05)
		attempts += 1
	_expect(target.health < target.max_health and target.health > 0,"C05 approach produces actual damage before retreat, no durable-health injection")
	await _wait(1.2)
	var health: float = target.health
	var shot_count: int = _feedback.filter(func(event: Dictionary) -> bool: return event.kind == "shot").size()
	await _capture("m501-range-02-retreated")
	await _wait(0.8)
	_expect(target.health == health and _feedback.filter(func(event: Dictionary) -> bool: return event.kind == "shot").size() == shot_count,"C05 retreat outside range stops further damage through actual cooldown windows")
	await _click_world(practice, target.position + Vector2(0,48))
	attempts = 0
	while target.health == health and attempts < 160:
		await _wait(0.05)
		attempts += 1
	_expect(target.health < health,"C05 reapproach resumes the same real weapon damage")
	await _capture("m501-range-03-reentered")


func _on_feedback(event: Dictionary) -> void:
	super._on_feedback(event)
	if event.kind != "shot":
		return
	_shot_error = maxf(_shot_error,float(event.predicted_muzzle_error))
	if _range_retreat:
		_range_retreat = false
		app.expedition.command_move(_retreat_goal)
	if _resume_capture:
		_resume_capture = false
		_instant_capture.call_deferred("m501-first-clear-moving-shot")


func _observe(actor: FieldActor, target: FieldActor, decision: AttackRules.Decision, stage: String) -> void:
	_observations.append({"stage":stage,"member_id":actor.actor_id + 1,"instance_id":actor.weapon_instance_id,
		"target_id":target.actor_id,"reason":String(decision.reason),"blocker_id":String(decision.blocker_id),
		"distance":decision.distance,"shot_from":decision.shot_from,"hit_to":decision.hit_to,
		"cooldown":actor.cooldown,"target_health":target.health,"elapsed":app.expedition.elapsed})


func _finish_proof() -> void:
	_expect(_shot_error < 0.001,"all actual shots use the same predicted and rendered muzzle")
	_write_json("combat-los-report.json",{"mode":_los_mode,"observations":_observations,"maximum_muzzle_error":_shot_error,
		"rule_status":"PROJECT_TEMP TMP-123..TMP-125, historical clues are not local V1.7.0F2 parity",
		"scope":"Same real street geometry. los-* stages are initialization-only isolated practice; normal mission loops are reported separately."})
	await super._finish_proof()
