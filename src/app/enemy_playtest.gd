class_name EnemyPlaytest
extends QualityPlaytest
## Opt-in intentions only; original owners execute gameplay and writes.


func _task_path() -> String:
	return "/.local/m5-enemy-02/"


func _trait_problem(data: Dictionary) -> String:
	return EnemyState.problem(data)


func _run() -> void:
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="):
			camp_case = arg.trim_prefix("--camp-case=")
		if arg.begins_with("--camp-expected="):
			expected_path = arg.trim_prefix("--camp-expected=")
	if "--bh-battle-drill" in OS.get_cmdline_user_args() and camp_case in ["restore-enemy-hit","restore-enemy-dodge","same-resave","resave","resume"]:
		app.survival_pilot = false
	if camp_case not in ["probe","save-enemy","restore-enemy-hit","restore-enemy-dodge","night-repair","night-market","early-repair","early-market","move-repair","move-market","night-probe-repair"]:
		await super._run()
		return
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if camp_case.begins_with("restore-enemy"):
		await _restore_enemies()
		await _finish_camp()
		return
	await _enter()
	_initial = app.camp_snapshot()
	_expect(EnemyState.problem(_initial).is_empty(),"strict111 source camp")
	if camp_case=="save-enemy":
		await _save_enemies()
		await _finish_camp()
		return
	var before: String = _digest()
	if camp_case in ["probe","night-probe-repair"]:
		app.get_node("Interface/Screen").hide()
		var pairs: Array[Dictionary] = await EnemyProbe.pairs(get_tree(),_initial)
		for row: Dictionary in pairs:
			_expect(row.hp==0 and row.events.any(func(e: Dictionary) -> bool: return e.kind=="shot"),"actual same-condition original auto-combat defeats "+row.enemy+" with "+row.gun)
		var safety: Dictionary = await EnemyProbe.safety(get_tree(),_initial)
		_expect(safety.rush.samples.any(func(row: Dictionary) -> bool: return row.speed==34) and safety.rush.samples.any(func(row: Dictionary) -> bool: return row.speed==58),"rush actual approach accelerates only after near threshold")
		_expect(safety.rush.hidden_speed==34 and safety.rush.hidden_target==0,"hidden worker immediately cancels rush intent")
		_expect(safety.wall.target_clear and safety.wall.enemy_clear and safety.wall.path>0 and safety.wall.distance<95 and not safety.wall.los and safety.wall.speed==34,"real wall corner with reachable actors prevents sprint through blocked LOS")
		_expect(safety.pause.remaining_before==safety.pause.remaining_after and safety.pause.clock_before==safety.pause.clock_after and safety.pause.health==200,"pause freezes exact heavy windup and health")
		_expect(safety.dodge.health==200 and safety.dodge.state!="windup","actual navigation out of28 radius cancels heavy strike")
		_expect(safety.death.warned and safety.death.enemy_hp==0 and safety.death.health==200 and safety.death.state!="windup","real third long-rifle shot kills heavy during telegraph without a ghost hit")
		_expect(safety.gate_blocked.health==200 and safety.gate_blocked.paused and safety.gate_blocked.remaining==0 and safety.gate_retry.health==194 and safety.gate_retry.attempts.size()==2,"original damage gate failure preserves pending hit and retry applies once")
		var animation: Dictionary = await EnemyProbe.animation(get_tree(),_initial,_capture)
		_expect(animation.actor_hp<200 and animation.enemy_hp==0,"ordinary animation includes actual melee hit shot damage and death")
		var heavy: Dictionary = await EnemyProbe.heavy_tell(get_tree(),_initial,_capture)
		_expect(heavy.actor_hp==194 and heavy.enemy_hp==0 and heavy.moved,"heavy real6 damage once then movement cancels second windup")
		var rush: Dictionary = await EnemyProbe.rush_tell(get_tree(),_initial,_capture)
		_expect(rush.turned and rush.hidden_target_reset and rush.enemy_hp==0,"rush animation follows real navigation turn lost target and original shot death")
		_write(output_dir.path_join("enemy-pairs.json"),{"samples":pairs})
		_write(output_dir.path_join("ordinary-animation.json"),animation)
		_write(output_dir.path_join("heavy-tell.json"),heavy)
		_write(output_dir.path_join("enemy-safety.json"),safety)
		_write(output_dir.path_join("rush-animation.json"),rush)
		_expect(before==_digest(),"all diagnostic enemies and animation probes leave real camp bytes unchanged")
		app.get_node("Interface/Screen").show()
	if camp_case!="probe":
		await _natural_outing()
	await _finish_camp()


func _natural_outing() -> void:
	var market: bool = camp_case.ends_with("market")
	await _open_map(1 if market else 0)
	var world: Expedition = _watch_world()
	var spawns: Array[Dictionary] = []
	world.spawn_resolved.connect(func(event: Dictionary) -> void: spawns.append(event.duplicate(true)))
	var observations: Array[Dictionary] = []
	var early: bool = camp_case.begins_with("early")
	var moving: bool = camp_case.begins_with("move")
	var target_time: float = 60.0 if early else 170.0
	world.request_search(&"food" if early and market else &"cash")
	var food_requested: bool = early and market
	var moved: bool = false
	var nearest: float = INF
	for tick: int in range(10000):
		if world.phase==Expedition.Phase.FINISHED or world.is_paused:
			break
		if world.searched and market and not food_requested:
			world.request_search(&"food")
			food_requested = true
		if moving and not moved and world.elapsed>=75.0:
			world.command_move(world.layout.bus_door+Vector2(0,-120))
			moved = true
		for enemy: FieldActor in world.enemies:
			for actor: FieldActor in world.survivors:
				if actor.visible and actor.health>0:
					nearest = minf(nearest,actor.position.distance_to(enemy.position))
		if tick%30==0:
			var types: Dictionary = {}
			for enemy: FieldActor in world.enemies:
				types[enemy.enemy_behavior.kind] = int(types.get(enemy.enemy_behavior.kind,0))+1
			observations.append({"elapsed":world.elapsed,"stage":world.threat.stage,"types":types,"health":world.survivors.map(func(actor: FieldActor) -> float: return actor.health),"alive":world.enemies.size()})
		if world.elapsed>=target_time and (world.searched or early and market) and (not market or world._food_site.searched):
			break
		await _step(world)
	_expect((world.searched or early and market) and (not market or world._food_site.searched),"natural outing completes real source search with no time or health injection")
	_expect(world.elapsed>=target_time,"natural elapsed reaches requested early or deep stage")
	await _capture("natural-"+("market" if market else "repair")+".png")
	var kinds: Array = []
	for event: Dictionary in spawns:
		if event.reason!="spawned":
			continue
		if not event.enemy_type in kinds:
			kinds.append(event.enemy_type)
		_expect(event.legal and event.active_enemies<=24,"original safe spawn and cap remain")
		_expect(event.enemy_type==EnemyRules.pick(world.sortie_id,int(event.enemy_id),int(event.stage)),"actual production type agrees with frozen identity and spawn index")
	if not early:
		_expect(kinds.has(EnemyRules.RUSH) and kinds.has(EnemyRules.HEAVY),"both special types appear through unmodified production spawn schedule")
	else:
		_expect(kinds==[EnemyRules.NORMAL],"early extraction avoids special-type stages")
	var map_id: String = String(world.layout.id)
	await _field_bus(world)
	_write(output_dir.path_join("natural.json"),{"map":map_id,"strategy":"early-food-only" if early and market else "early" if early else "move" if moving else "hold-search-late","spawns":spawns,"observations":observations,"types_during_strategy":kinds,"nearest_distance_during_strategy":nearest,"combat":_battle_events,"ended":_reports[-1].elapsed})


func _save_enemies() -> void:
	app.survival_pilot = false
	await _open_map(1)
	var world: Expedition = _watch_world()
	_expect(world.battle_drill,"timed snapshot scenario explicitly marked diagnostic")
	var heavy: FieldActor
	var rush: FieldActor
	var spawns: Array[Dictionary] = []
	world.spawn_resolved.connect(func(event: Dictionary) -> void: spawns.append(event.duplicate(true)))
	for tick: int in range(9000):
		heavy = null
		rush = null
		for enemy: FieldActor in world.enemies:
			if enemy.enemy_behavior.kind==EnemyRules.HEAVY and enemy.health>32:
				heavy = enemy
			if enemy.enemy_behavior.kind==EnemyRules.RUSH:
				rush = enemy
		if heavy!=null and rush!=null:
			break
		await _step(world)
	_expect(heavy!=null and rush!=null,"snapshot subjects originate from real natural production spawn chain")
	if heavy==null or rush==null:
		return
	var index: int = 0
	for enemy: FieldActor in world.enemies:
		enemy.clear_order()
		if enemy!=heavy and enemy!=rush:
			enemy.position = Vector2(80+(index%12)*128,80+(index/12)*32)
			index+=1
	for actor: FieldActor in world.survivors:
		actor.clear_order()
		actor.position = Vector2(832,704+56*actor.actor_id)
		actor.cooldown = 999.0
	heavy.position = world.survivors[0].position+Vector2(24,0)
	heavy.cooldown = 0.0
	rush.position = world.survivors[1].position+Vector2(70,0)
	var old_hp: float = heavy.health
	world.survivors[0].cooldown = 0.0
	await _step(world)
	world.survivors[0].cooldown = 999.0
	for tick: int in range(5):
		await _step(world)
	_expect(heavy.health==old_hp-18 and heavy.enemy_behavior.state=="windup" and heavy.enemy_behavior.windup_remaining>0,"actual carbine hit leaves partial heavy HP and unfinished windup")
	_expect(rush.enemy_behavior.state=="rush" and rush.speed==58,"actual nearby rush state before suspend")
	world._show_notice("恢复诊断：仅重排既有自然敌人的站位，未生成类型/修改HP\n原枪实际18伤；停火夹具保留真实前摇/目标/冲刺，随后原Esc暂存")
	await _capture("snapshot-windup.png")
	_write(output_dir.path_join("enemy-control.json"),{"heavy_id":heavy.actor_id,"rush_id":rush.actor_id,"heavy":heavy.enemy_behavior.snapshot(),"heavy_hp":heavy.health,"rush":rush.enemy_behavior.snapshot(),"spawns":spawns,"scope":"explicit spatial and cease-fire fixture over real spawned identities; not natural difficulty"})
	await _save_field(world)


func _restore_enemies() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_expect(app.expedition!=null,"new PID reconstructs strict111 world before claim")
	if app.expedition==null:
		return
	var world: Expedition = _watch_world()
	_initial = app.camp_snapshot()
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	captured = SortieSnapshot.capture(world)
	_expect(TransactionReceipt.same(expected,captured),"full kind HP target path timers sprint and gait phase restore exactly")
	_write(output_dir.path_join("restored.json"),captured)
	var heavy: FieldActor
	for enemy: FieldActor in world.enemies:
		if enemy.enemy_behavior.state=="windup":
			heavy = enemy
	_expect(heavy!=null,"unfinished heavy telegraph remains pending after restart")
	if heavy==null:
		return
	var target: FieldActor = heavy.enemy_behavior.locked_target(world)
	var health_before: float = target.health
	var remaining: float = heavy.enemy_behavior.windup_remaining
	var start: float = world.elapsed
	for frame: int in range(12):
		await _step(world)
	_expect(world.elapsed==start and heavy.enemy_behavior.windup_remaining==remaining and target.health==health_before,"restored pause advances neither windup nor damage")
	await _capture("restored-windup.png")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		await _key_battle(KEY_SPACE)
	if camp_case.ends_with("dodge"):
		world.command_move(target.position+Vector2(0,-120))
	for tick: int in range(18):
		await _step(world)
	var hits: Array = _battle_events.filter(func(event: Dictionary) -> bool: return event.kind=="hit" and event.get("enemy_id",-1)==heavy.actor_id)
	if camp_case.ends_with("hit"):
		_expect(hits.size()==1 and target.health==health_before-6 and hits[0].elapsed-start>=remaining-0.000001,"only one6 damage after restored remaining telegraph finishes")
	else:
		_expect(hits.is_empty() and target.health==health_before and heavy.enemy_behavior.state!="windup","real movement avoids restored telegraph without any heavy damage")
	_write(output_dir.path_join("enemy-resume.json"),{"remaining":remaining,"elapsed_after":world.elapsed-start,"hits":hits,"target_hp_before":health_before,"target_hp_after":target.health,"state":heavy.enemy_behavior.snapshot()})
	# Release the declared cease-fire fixture before the original search/bus completion.
	for actor: FieldActor in world.survivors:
		actor.cooldown = 0.0
	await _field_search(world)
	await _field_bus(world)
