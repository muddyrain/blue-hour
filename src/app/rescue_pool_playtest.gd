class_name RescuePoolPlaytest
extends WeaponPlaytest
## Opt-in final-package intentions. Gameplay, membership and persistence stay in original owners.

var candidate: int = 0
var original_npc: int = 0


func _task_path() -> String:
	return "/.local/m5-rescue-02/"


func _trait_problem(data: Dictionary) -> String:
	return RescuePoolState.problem(data)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="):
			camp_case = arg.trim_prefix("--camp-case=")
		if arg.begins_with("--camp-expected="):
			expected_path = arg.trim_prefix("--camp-expected=")
	field_case = camp_case
	if camp_case=="measure":
		await super._run()
		return
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if camp_case=="blocked":
		var digest: String = _digest()
		await _tap(app._continue_button)
		_expect(app._progress_blocked and app.expedition==null and digest==_digest(),"invalid journal or second writer cannot mutate profile or enter world")
		await _finish_camp()
		return
	if camp_case in ["resume","resave","same-resave"]:
		await _restore_pool()
		await _finish_camp()
		return
	await _enter()
	_initial = app.camp_snapshot()
	_expect(_initial.schema_version==108 and RescuePoolState.problem(_initial).is_empty(),"strict108 authoritative camp before original intentions")
	if not expected_path.is_empty():
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		_expect(TransactionReceipt.same(_initial,expected.camp),"independent PID restores full identities equipment growth training and economy")
	await _camp_ui("camp-before")
	if camp_case=="hold":
		_write(output_dir.path_join("holding.json"),{"pid":OS.get_process_id()})
		for frame: int in range(1000):
			if FileAccess.file_exists(output_dir.path_join("release")):
				break
			await get_tree().create_timer(0.03).timeout
	elif camp_case=="continue":
		await _profiles()
	elif camp_case in ["train","train-write","train-ack","train-locked","kill-ready","kill-after-write"]:
		var id: int = int(_initial.crew[-1].id)
		await _train_member(id)
	elif camp_case=="death-one":
		await _open_map(0)
		var world: Expedition = _watch_world()
		await _field_death(world,int(_initial.crew[-1].id))
		await _field_bus(world)
	else:
		if camp_case in ["worker-down","join-death"]:
			app.survival_pilot = false
		await _open_map(1 if camp_case=="market" else 0 if camp_case=="repair" else 2)
		if app.expedition!=null:
			var world: Expedition = _watch_world()
			if world.rescue_target!=null:
				candidate = world.candidate_id()
				original_npc = world.rescue_target.npc.get_instance_id()
				_expect(candidate==app.progress_session._transaction.recover().receipt.rules.candidate.member_id,"visible NPC equals durably frozen candidate")
				await _capture("candidate.png")
				if camp_case in ["join-write","join-binding"]:
					app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point==("before_record_write" if camp_case=="join-write" else "before_binding_write") else OK
				await _tap(world.rescue_target.button)
				for frame: int in range(1800):
					if world.rescue_target.progress>=(2.0 if camp_case in ["cancel","worker-down","redirect"] else 9.5 if camp_case=="save-before" else 10.0):
						break
					await _step(world)
				if camp_case=="save-before":
					await _save_field(world)
					await _finish_camp()
					return
				if camp_case=="worker-down":
					await _worker_attack(world)
				elif camp_case in ["cancel","redirect"]:
					if camp_case=="redirect":
						world.command_move(world.layout.bus_door)
					else:
						await _tap(world.rescue_target.button)
					_expect(world.field_joins.is_empty() and world.rescue_target.status=="AVAILABLE","cancelled partial assistance grants no member or gun")
				else:
					if camp_case in ["join-write","join-binding"]:
						_expect(world.is_paused and not world.field_join_error.is_empty() and world.survivors.size()==_initial.journey.active_member_ids.size(),"unacknowledged join never promotes live actor or bus authority")
						_expect(SortieSnapshot.capture(world).is_empty(),"unacknowledged candidate blocks unsafe suspend")
						var elapsed: float = world.elapsed
						await _key_battle(KEY_SPACE)
						world.command_move(world.layout.bus_door)
						for frame: int in range(5):
							await _step(world)
						_expect(world.is_paused and elapsed==world.elapsed,"failed join seals simulation until exact original ACK")
						app.progress_session.fault_hook = Callable()
						await _tap(world.rescue_target.button)
						if world.is_paused:
							await _key_battle(KEY_SPACE)
					await _verify_join(world)
					if camp_case=="join-death":
						await _field_death(world,candidate)
			await _field_search(world)
			if camp_case=="save-after":
				await _save_field(world)
			else:
				await _field_bus(world)
				if app.camp_scene.is_visible_in_tree():
					await _maintenance()
	await _finish_camp()


func _watch_world() -> Expedition:
	var world: Expedition = app.expedition
	world.set_physics_process(false)
	world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
	world.combat_feedback.connect(func(value: Dictionary) -> void: _battle_events.append(value.duplicate(true)))
	return world


func _verify_join(world: Expedition) -> void:
	_expect(world.field_joins.size()==1 and world.rescue_target.npc.get_instance_id()==original_npc and world.survivors.has(world.rescue_target.npc),"same NPC becomes real member only after original join ACK")
	_expect(world.survivors.size()==_initial.journey.active_member_ids.size()+1 and world.boarding_status().required==world.living_count(),"new recruit immediately enters real team and bus denominator")
	await _capture("joined-in-field.png")


func _restore_pool() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_expect(app.expedition!=null,"Continue reconstructs existing108 frozen world")
	if app.expedition==null:
		return
	var world: Expedition = _watch_world()
	_initial = app.camp_snapshot()
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	captured = SortieSnapshot.capture(world)
	_expect(TransactionReceipt.same(expected,captured),"all frozen actors identities weapons Trait progress clocks and candidate restore exactly")
	_write(output_dir.path_join("restored.json"),captured)
	for folder: String in DirAccess.get_directories_at(app.progress_path+".txn/journal"):
		var row: Dictionary = app.progress_session._transaction._journal._read_record((app.progress_path+".txn/journal").path_join(folder).path_join("record.json")).receipt
		if row.phase=="SUSPEND_READY":
			replay_tokens.append({"token":RunTransaction.token_for(row),"hash":row.envelope.world_hash,"generation":row.envelope.previous_head})
	_reject_replays("RESUME_CLAIMED")
	if camp_case=="same-resave":
		await _save_field(world)
		_expect(TransactionReceipt.same(expected,captured),"paused equal-content re-suspend preserves exact world with fresh durable generation")
		return
	if world.rescue_target!=null:
		candidate = world.candidate_id()
		original_npc = world.rescue_target.npc.get_instance_id()
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		await _key_battle(KEY_SPACE)
	if world.rescue_target!=null and world.field_joins.is_empty():
		if world.rescue_target.worker==0:
			await _tap(world.rescue_target.button)
		for frame: int in range(1200):
			if not world.field_joins.is_empty():
				break
			await _step(world)
		await _verify_join(world)
	await _field_search(world)
	if camp_case=="resave":
		await _save_field(world)
	else:
		await _field_bus(world)
		await _camp_ui("resumed-camp")


func _field_search(world: Expedition) -> void:
	for kind: StringName in [&"cash",&"food"]:
		if not world.supply.supports(kind) or world.search_site(kind).searched:
			continue
		world.command_move(world.search_site(kind).door)
		for frame: int in range(1600):
			if world.survivors.all(func(actor: FieldActor) -> bool: return actor.activity!=FieldActor.Activity.MOVING):
				break
			await _step(world)
		world.request_search(kind)
		for frame: int in range(3200):
			if world.search_site(kind).searched:
				break
			await _step(world)
		_expect(world.search_site(kind).searched,"original real search completes "+String(kind))
	if not world.field_joins.is_empty() and world.rescue_target.npc.health>0:
		world.command_move(Vector2(568,864))
		for frame: int in range(1800):
			if world.rescue_target.npc.confirmed_kills>0:
				break
			await _step(world)
		_expect(world.rescue_target.npc.confirmed_kills>0,"new candidate actually defeats enemy with original weapon AI")
		await _capture("recruit-combat.png")


func _field_bus(world: Expedition) -> void:
	for frame: int in range(1000):
		if world.elapsed>=world.tuning.bus_ready_seconds:
			break
		await _step(world)
	world.request_bus_action()
	for frame: int in range(180):
		if world.phase==Expedition.Phase.BOARDING:
			break
		await _step(world)
	world.request_bus_gather()
	if camp_case=="missing" and not world.field_joins.is_empty():
		var recruit: FieldActor = world.rescue_target.npc
		recruit.clear_order()
		for frame: int in range(400):
			if world.boarding_status().arrived==world.boarding_status().required-1:
				break
			await _step(world)
		_expect(world.phase==Expedition.Phase.BOARDING and world.boarding_status().arrived<world.boarding_status().required and _reports.is_empty(),"missing living recruit prevents bus completion and camp grant")
		await _capture("bus-waits-for-recruit.png")
		world.request_bus_gather()
	for frame: int in range(3200):
		if world.phase==Expedition.Phase.FINISHED:
			break
		await _step(world)
	_expect(_reports.size()==1 and _reports[0].evacuated,"original bus waits for every living member and emits one result")
	var state: Dictionary = app.progress_session.inspect()
	_expect(state.error==OK and state.state=="RECOVERY_READY","original frozen READY contains all108 candidate and progression provenance: "+str(state.get("reason","")))
	if state.error!=OK:
		return
	_write(output_dir.path_join("frozen.json"),state.receipt)
	await _capture("field-result.png")
	if camp_case=="ready":
		return
	if camp_case=="ack":
		app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point=="before_commit_receipt" else OK
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	if camp_case=="ack":
		_expect(app._progress_blocked and TransactionReceipt.same(_initial,app.camp_snapshot()),"unknown ACK cannot apply camp membership or economy in memory")
		app.progress_session.fault_hook = Callable()
		await _tap(app._retry_button)
	var after: Dictionary = app.camp_snapshot()
	_expect(RescuePoolState.problem(after).is_empty(),"strict108 full camp and histories validate")
	_expect(after.last_day.food_required==_reports[0].member_results.filter(func(row: Dictionary) -> bool: return row.health>0 and not SurvivorRoster.member(_initial.crew,int(row.id)).is_empty()).size(),"rescue meal counts departure survivors; later outings count actual four")
	var digest: String = _digest()
	app.progress_session.activate()
	_expect(digest==_digest(),"duplicate activation cannot repeat member gun XP meal date or commit")
	_reject_replays("COMMITTED")
	await _capture("camp-after.png")


func _camp_ui(label: String) -> void:
	var data: Dictionary = app.camp_snapshot()
	var ids: Array[int] = []
	for member: Dictionary in data.crew:
		if member.health>0:
			ids.append(int(member.id))
	ids.sort()
	_expect(app.camp_scene.is_visible_in_tree() and app.camp_scene.world.visible_member_ids==ids,"camp displays exact living stable IDs without array reindexing")
	for id: int in ids:
		_expect(app.camp_scene.world.residents[id].get_meta("definition_id")==SurvivorRoster.member(data.crew,id).definition_id,"actual camp portrait belongs to stable ID%d" % id)
		_expect(get_viewport().get_visible_rect().encloses(app.camp_scene.member_buttons[id].get_global_rect()),"member hotspot remains in actual logical viewport")
	await _capture(label+".png")
	await _weapons_ui(label)
	await _pool_training_view(label)


func _profiles() -> void:
	await _tap(app.camp_scene.hotspots[&"crew"])
	for member: Dictionary in app.crew:
		var button: Button = app.roster_panel.buttons_by_id[int(member.id)]
		button.grab_focus()
		await _settle()
		await _tap(button)
		_expect(app.roster_panel._identity.text==SurvivorRoster.definition_for(member).default_display_name,"roster detail preserves actual template identity")
		await _tap(app.roster_panel.growth_button)
		_expect(app.growth_panel.status.text.contains(TraitRules.NAMES[TraitRules.role(member)-1]),"ordinary XP and correct personal Trait remain separate")
		await _capture("profile-%d.png" % int(member.id))
		await _key_battle(KEY_ESCAPE)
	await _key_battle(KEY_ESCAPE)


func _pool_training_view(label: String) -> void:
	var before: Dictionary = app.camp_snapshot()
	var digest: String = _digest()
	await _tap(app.camp_scene.hotspots[&"training"])
	var panel: TrainingPanel = app.training_panel
	for member: Dictionary in before.crew:
		if member.health<=0:
			_expect(not panel.member_buttons.has(int(member.id)),"dead member cannot be trained")
			continue
		var button: Button = panel.member_buttons[int(member.id)]
		button.grab_focus()
		await _settle()
		await _tap(button)
		_expect(panel.detail.text.contains(TraitRules.NAMES[TraitRules.role(member)-1]),"training preview matches actual stable ID and existing Trait")
	await _capture(label+"-training.png")
	await _key_battle(KEY_ESCAPE)
	_expect(digest==_digest(),"four-member training browsing changes no saved bytes")


func _worker_attack(world: Expedition) -> void:
	var target: RescueTarget = world.rescue_target
	var worker: FieldActor
	for actor: FieldActor in world.survivors:
		actor.cooldown = 999.0
		if actor.member_id==target.worker:
			worker = actor
	var progress: float = target.progress
	# Explicit danger fixture: twelve existing enemies, unchanged HP/damage/AI.
	for index: int in range(12):
		var point: Vector2 = worker.position+Vector2(36 if index%2==0 else -36,0)
		var enemy: FieldActor = world._make_actor(true,11000+index,point)
		world.enemies.append(enemy)
	for frame: int in range(1000):
		if worker.permanent_death:
			break
		await _step(world)
	await _step(world) # Rescue state observes the confirmed death on its next normal tick.
	_expect(worker.health==0 and worker.permanent_death and worker.damage_received>=200,"original enemy AI and original4 damage genuinely kill assistance worker")
	_expect(target.status=="AVAILABLE" and target.progress>=progress and target.progress<10 and world.field_joins.is_empty(),"worker death interrupts partial aid without free success")
	for actor: FieldActor in world.survivors:
		actor.cooldown = 0
	await _capture("worker-death-interrupts.png")


func _finish_camp() -> void:
	_write(output_dir.path_join("pool-identity.json"),{"candidate":candidate,"npc_instance":original_npc,"five_person":"NOT_IMPLEMENTED / NO-GO-FIVE"})
	await super._finish_camp()
