class_name M5Combat03Playtest
extends M5Combat02Playtest
## Fixed A/B intentions on real ordinary sorties; never places enemies or writes stats.

const ALayout: StreetLayout = preload("res://src/app/playtest_maps/market_loop_a.tres")
const BLayout: StreetLayout = preload("res://src/app/playtest_maps/market_loop_b.tres")
const SEEDS: Array[int] = [3103,4103,5103,6103,7103]
const OFFSETS: Array[int] = [-16,-8,0,8,16]

var _ab_mode: String = ""
var _ab_seed: int = 5103
var _ab_armed: bool = false
var _ab_acted: bool = false
var _ab_extracting: bool = false
var _ab_gathered: bool = false
var _ab_cue: float = -1.0
var _ab_ui_pending: bool = false
var _ab_guard: int = -1
var _ab_first_los: Dictionary = {}
var _ab_intents: Array[Dictionary] = []
var _ab_work: Array[Dictionary] = []
var _ab_clock: float = 0.0
var _ab_health_at_90: Array[float] = []
var _ab_first_hit_capture: bool = false


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--m402-mode="):
			_ab_mode = argument.trim_prefix("--m402-mode=")
		elif argument.begins_with("--ab-seed="):
			_ab_seed = int(argument.trim_prefix("--ab-seed="))
	if not _ab_mode.begins_with("ab-"):
		await super._run()
		return
	process_physics_priority = 100
	var sampler: M5Combat02Playtest.BeforeStep = M5Combat02Playtest.BeforeStep.new()
	sampler.audit = self
	sampler.process_physics_priority = -100
	add_child(sampler)
	app.get_node("World").child_entered_tree.connect(_attach_audit)
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	app.get_node("World").child_entered_tree.connect(_connect_pressure)
	app.get_node("World").child_entered_tree.connect(_connect_growth)
	app.get_node("World").child_entered_tree.connect(_connect_ux)
	app.audio_requested.connect(func(cue: StringName, world: bool, accepted: bool) -> void:
		_audio_events.append({"cue":String(cue),"world":world,"accepted":accepted,"frame":Engine.get_frames_drawn()}))
	await _run_ab()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _ab_armed or not is_instance_valid(_current) or _current.phase == Expedition.Phase.FINISHED:
		return
	var sortie: Expedition = _current
	for enemy: FieldActor in sortie.enemies:
		for actor: FieldActor in sortie.survivors:
			var key: String = "%d:%d" % [enemy.actor_id,actor.actor_id]
			if not _ab_first_los.has(key):
				var decision: AttackRules.Decision = sortie.evaluate_attack(actor,enemy)
				if decision.targetable:
					_ab_first_los[key] = {"enemy":enemy.actor_id,"member":actor.actor_id+1,"elapsed":sortie.elapsed,"distance":decision.distance,
						"enemy_foot":enemy.position,"member_foot":actor.position,"shot_from":decision.shot_from,"hit_to":decision.hit_to,"source":"readonly post-step legal LOS"}
	_ab_clock += delta
	if _ab_clock >= 0.25:
		_ab_clock = 0.0
		_ab_work.append({"elapsed":sortie.elapsed,"phase":sortie.phase,"search_member_id":sortie.search_actor.actor_id+1 if sortie.search_actor != null else -1,
			"search_hidden":sortie.search_actor != null and not sortie.search_actor.visible,"progress":sortie.search_progress,
			"searched":sortie.searched,"loot":sortie.loot,"health":[sortie.survivors[0].health,sortie.survivors[1].health],"frame":Engine.get_frames_drawn()})
	if _ab_mode.contains("avoid") and not _ab_acted and _ab_cue >= 0.0 and sortie.elapsed >= _ab_cue+0.25:
		_ab_acted = true
		if _ab_mode.ends_with("ui"):
			_ab_ui_pending = true
			_avoid_ui.call_deferred(sortie)
		else:
			_cancel_and_move(sortie)
	if not _ab_extracting and not _ab_ui_pending and (sortie.elapsed >= 90.0 or _ab_acted):
		_ab_health_at_90.assign([sortie.survivors[0].health,sortie.survivors[1].health])
		sortie.request_extraction()
		_ab_extracting = sortie.phase == Expedition.Phase.ENGINE
		_ab_intents.append({"action":"engine","elapsed":sortie.elapsed,"goal":sortie.goal})
	if _ab_extracting and not _ab_gathered and sortie.phase == Expedition.Phase.BOARDING:
		_ab_gathered = true
		sortie.request_bus_gather()
		_ab_intents.append({"action":"explicit_gather","elapsed":sortie.elapsed,"goal":sortie.goal})
	if not _ab_first_hit_capture and not _hits.is_empty():
		_ab_first_hit_capture = true
		_capture.call_deferred("ab-first-real-hit")


func _run_ab() -> void:
	_contact_mode = _ab_mode
	_mode = _ab_mode
	_sequence = _ab_mode
	_has_food = true
	DirAccess.make_dir_recursive_absolute(output_dir)
	_expect(_ab_seed in SEEDS,"prelocked seed identity is supported")
	_initial_save_hash = _hash(app.run_save.path)
	_initial_backup_hash = _hash(app.run_save.path+".bak")
	_expect(app._requires_continue,"A/B uses existing real v5 campaign fixture")
	_expected = app._pending_save.duplicate(true)
	await _click_screen(app._continue_button.get_global_rect().get_center())
	_before = app.camp_snapshot()
	_expect(_before == _expected,"A/B Continue preserves exact baseline progress")
	var supply: MissionSupply = preload("res://src/features/camp/supermarket.tres").duplicate(true)
	supply.layout = ALayout if _ab_mode.begins_with("ab-a-") else BLayout
	app.selected_supply = supply
	seed(_ab_seed)
	app.open_expedition()
	var sortie: Expedition = app.expedition
	sortie.toggle_pause()
	_tracing = true
	sortie.finished.connect(func(report: Dictionary) -> void: _sortie_reports.append(report.duplicate(true)))
	sortie.combat_feedback.connect(_ab_feedback)
	sortie.camera.zoom = Vector2.ONE * 1.1
	sortie.camera.position = Vector2(744,840)
	sortie.camera.force_update_scroll()
	# Search first preserves the original nearest-worker rule and the same role
	# across maps. These are fixed trial intentions, separate from natural UI play.
	sortie.request_search(&"cash")
	_ab_guard = 1-sortie.search_actor.actor_id
	var point: Vector2 = Vector2(568,864+OFFSETS[SEEDS.find(_ab_seed)])
	sortie.command_move(point)
	_ab_intents.append({"action":"search_cash","elapsed":sortie.elapsed,"worker":sortie.search_actor.actor_id+1})
	_ab_intents.append({"action":"move","elapsed":sortie.elapsed,"goal":point})
	_expect(not sortie.is_practice and not sortie.threat_rehearsal and sortie.elapsed == 0.0,"ordinary director starts at real zero without practice, time jumps or enemy initialization")
	_expect(_ab_guard == 1 and sortie.survivors[0].weapon_definition.id == &"long_rifle" and sortie.survivors[1].weapon_definition.id == &"carbine","same real v5 assignment: Gu works with long rifle, Xia guards with carbine")
	await _capture("ab-01-start")
	sortie._hud.hide()
	sortie.camera.zoom = Vector2.ONE * 0.48
	sortie.camera.position = Vector2(960,720)
	sortie.camera.force_update_scroll()
	await _capture("ab-wide-layout-only")
	sortie._hud.show()
	sortie.camera.zoom = Vector2.ONE * 1.1
	sortie.camera.position = Vector2(744,840)
	sortie.camera.force_update_scroll()
	_ab_armed = true
	sortie.toggle_pause()
	await _until_time(sortie,27.0)
	await _capture("ab-02-before-corner")
	await _until_time(sortie,31.0)
	await _capture("ab-03-contact-or-action")
	if app.phase == app.Phase.EXPEDITION:
		while sortie.elapsed < 40.0 and sortie.phase != Expedition.Phase.FINISHED:
			await _wait(0.1)
		await _capture("ab-04-after-window")
	var waits: int = 0
	while app.phase != app.Phase.RESULT and waits < 1800:
		await _wait(0.1)
		waits += 1
	_ab_armed = false
	_tracing = false
	_expect(app.phase == app.Phase.RESULT and _sortie_reports.size() == 1 and _sortie_reports[0].evacuated,"fixed trial ends with one real evacuation result")
	_expect(_audio_count("bus_start") == 1,"fixed trial starts engine exactly once")
	_expect(sortie.survivors[0].health == 200.0,"hidden worker was not given fake damage")
	_expect(sortie.living_count() == 2,"terrain trial never requires sacrificing a member")
	if _ab_mode.contains("avoid") and _ab_cue >= 0.0:
		_expect(_ab_acted and sortie.survivors[1].health == 200.0,"timely cue-based avoidance reaches camp without guard damage")
	else:
		_expect(sortie.searched and sortie.loot == 4,"stationary trial completes original thirty-second cash search and reward")
	await _capture("ab-05-result")
	await _check_finished(sortie)
	var trial: Dictionary = {"mode":_ab_mode,"seed":_ab_seed,"y_offset":OFFSETS[SEEDS.find(_ab_seed)],"map_revision":"A=88e21c3" if _ab_mode.begins_with("ab-a-") else "B05=local authored candidate",
		"cash_block":sortie.layout.cash_block,"cash_door":sortie.layout.cash_door,"guard_member_id":_ab_guard+1,
		"equipment":sortie.loadout_snapshot.duplicate(true),"intentions":_ab_intents,"first_legal_los":_ab_first_los.values(),"short_shot_cue":_ab_cue,
		"work":_ab_work,"health_at_extraction_order":_ab_health_at_90,"report":_sortie_reports[0],"scope":"Fixed input counterfactual, ordinary safe spawn/AI/navigation/attack. Seeds label prelocked positions; production generator is deterministic. Normal UI task is reported separately."}
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	var callback: Callable = app._finish_callback
	callback.call({})
	_expect(app.camp_snapshot() == _before and app._pending_settlement == proposal,"duplicate result cannot bank a second transaction")
	await _click_control("Interface/Screen/Result/Continue")
	callback.call({})
	_expect(app.camp_snapshot() == proposal and app.run_save.load_save() == OK and app.run_save.snapshot == proposal,"real return banks once and saves exact injury, records and loadout in v5")
	_expect(app.day == int(_before.day)+1 and app.loadout == _before.loadout,"terrain does not alter date progression or equipment ownership")
	await _capture("ab-06-saved-camp")
	_write_json("market-ab.json",trial)
	await _finish_proof()


func _ab_feedback(event: Dictionary) -> void:
	if event.kind != "shot":
		return
	if event.foot_distance < 100.0 and _ab_cue < 0.0:
		_ab_cue = float(event.elapsed)
	var key: String = "%d:%d" % [int(event.target),int(event.actor)]
	if not _ab_first_los.has(key):
		_ab_first_los[key] = {"enemy":event.target,"member":int(event.actor)+1,"elapsed":event.elapsed,"distance":event.foot_distance,
			"enemy_foot":event.to,"member_foot":event.from,"shot_from":event.shot_from,"hit_to":event.hit_to,"source":"actual first production shot before post-step sample"}


func _cancel_and_move(sortie: Expedition) -> void:
	if sortie.search_actor != null:
		sortie.request_search(&"cash")
	sortie.command_move(sortie.layout.bus_door)
	_ab_intents.append({"action":"cancel_and_retreat","elapsed":sortie.elapsed,"cue":_ab_cue,"goal":sortie.goal,"input":"fixed production intention API"})
	_capture.call_deferred("ab-avoidance-ordered")


func _avoid_ui(sortie: Expedition) -> void:
	# Both actual click targets are visible to the left of the opaque action panel.
	var block: Rect2 = sortie.layout.cash_block
	if sortie.search_actor != null:
		await _click_world(sortie,Vector2(block.get_center().x,block.end.y-30))
	await _click_world(sortie,Vector2(760,1040))
	_expect(sortie.search_actor == null and sortie.goal.distance_to(Vector2(760,1040)) < 1.0,"real mouse cancels search and orders a safe retreat without HUD penetration")
	_ab_intents.append({"action":"cancel_and_retreat","elapsed":sortie.elapsed,"cue":_ab_cue,"goal":sortie.goal,"input":"real viewport mouse events"})
	_ab_ui_pending = false
	await _capture("ab-avoidance-real-mouse")
