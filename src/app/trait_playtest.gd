class_name TraitPlaytest
extends CampScenePlaytest
## New106 intentions reuse old real UI/gameplay; no progress injection.

var trait_effects: Array[Dictionary] = []
var search_measurements: Array[Dictionary] = []


func _run() -> void:
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="):
			camp_case = arg.trim_prefix("--camp-case=")
	if camp_case == "death-resume":
		app.survival_pilot = false
		field_case = "resume"
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--camp-expected="):
				expected_path = arg.trim_prefix("--camp-expected=")
		await _settle()
		await _restore_field()
		var member: Dictionary = SurvivorRoster.member(app.crew,3)
		_expect(member.health==0 and member.condition=="dead","new PID keeps confirmed ID3 death and Trait history")
		await _finish_camp()
		return
	if camp_case == "hold":
		await _settle()
		await _enter()
		_initial = app.camp_snapshot()
		_write(output_dir.path_join("holding.json"),{"pid":OS.get_process_id()})
		for frame: int in range(1000):
			if FileAccess.file_exists(output_dir.path_join("release")):
				break
			await get_tree().create_timer(0.03).timeout
		await _finish_camp()
		return
	if camp_case == "save-search":
		await _settle()
		await _enter()
		_initial = app.camp_snapshot()
		await _open_map(0)
		var world: Expedition = app.expedition
		world.set_physics_process(false)
		world.request_search(&"cash")
		for frame: int in range(2000):
			if world.search_progress >= 8:
				break
			await _step(world)
		_expect(world.search_progress>=8 and not world.searched and world.trait_inputs.events.is_empty(),"partial actual search has no completion award")
		await _save_field(world)
		await _finish_camp()
		return
	if camp_case in ["death-one","death-save","death-all"]:
		field_case = camp_case
		await _settle()
		await _enter()
		_initial = app.camp_snapshot()
		await _open_map(0)
		var world: Expedition = app.expedition
		world.set_physics_process(false)
		world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
		world.combat_feedback.connect(func(value: Dictionary) -> void: _battle_events.append(value.duplicate(true)))
		if camp_case == "death-all":
			for id: int in [3,1,2]:
				if id not in _initial.journey.active_member_ids:
					continue
				await _field_death(world,id)
			_expect(_reports.size()==1 and not _reports[0].evacuated and app.camp_snapshot().journey.state=="FAILED","all real confirmed deaths commit terminal106 with no living actors")
			for member: Dictionary in app.crew:
				_expect(TransactionReceipt.same(member.growth.trait,SurvivorRoster.member(_initial.crew,int(member.id)).growth.trait),"dead Trait history retained without grant or revival")
			await _capture("terminal.png")
		else:
			var id: int = 3 if camp_case=="death-save" else 1
			await _field_death(world,id)
			if camp_case=="death-save":
				await _save_field(world)
			else:
				await _field_bus(world)
				_expect(TransactionReceipt.same(SurvivorRoster.member(app.crew,id).growth.trait,SurvivorRoster.member(_initial.crew,id).growth.trait),"confirmed dead member keeps original Trait history")
		await _finish_camp()
		return
	if camp_case != "effects":
		await super._run()
		return
	await _settle()
	await _enter()
	_initial = app.camp_snapshot()
	var digest: String = _digest()
	app.get_node("Interface/Screen").hide()
	var samples: Array[Dictionary] = await TraitEffectProbe.run(get_tree(),_initial,_capture)
	app.get_node("Interface/Screen").show()
	_write(output_dir.path_join("causal-effects.json"),{"samples":samples,"source":"PROJECT_TEMP controlled actor profiles, not natural trait progress"})
	for row: Dictionary in samples:
		_expect(row.arrived and row.path_clear and row.searched and row.blocked_no_fire and row.down_no_fire and row.pause_freezes and row.cancel_no_reward and row.zero_defeat_diagnostic,"real handlers preserve navigation/LOS/down/pause/cancel for ID%d/Lv%d" % [int(row.member_id),int(row.trait_level_fixture)])
		var level: int = int(row.trait_level_fixture)
		var shot: float = 1.0 if level==0 or row.member_id!=1 else (0.95 if level==1 else 0.925)
		var search: float = 1.0 if level==0 or row.member_id!=2 else (0.9 if level==1 else 0.85)
		var speed: float = 1.0 if level==0 or row.member_id!=3 else (1.08 if level==1 else 1.12)
		_expect(absf(row.interval-0.65*shot)<0.0011 and absf(row.search_seconds-30*search)<0.011 and row.speed==125*speed,"measured actual personal shot/search/move effects match treatment and nonowners remain unchanged")
	_expect(digest==_digest() and TransactionReceipt.same(_initial,app.camp_snapshot()),"causal fixtures never create camp progress/XP/member or modify saved journey")
	await _finish_camp()


func _expect(value: bool, label: String) -> void:
	super._expect(value,label.replace("105","106"))


func _profiles() -> void:
	await _tap(app.camp_scene.hotspots[&"crew"])
	for member: Dictionary in app.crew:
		await _tap(app.roster_panel.member_buttons[int(member.id)-1])
		_expect(app.roster_panel._service.text.contains(TraitRules.NAMES[int(member.id)-1]) and app.roster_panel._service.text.contains("Trait Lv"),"profile separately shows personal Trait and ordinary XP for ID%d" % int(member.id))
		await _capture("profile-%d.png" % int(member.id))
		await _tap(app.roster_panel.growth_button)
		_expect(app.growth_panel.status.text.contains("普通") and app.growth_panel.status.text.contains(TraitRules.NAMES[int(member.id)-1]),"growth archive has separate level, progress and actual effect")
		_expect(app.growth_panel.training_button.disabled,"food training stays unavailable")
		_expect(app.growth_panel.back_button.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y,"profile return remains inside actual viewport")
		await _capture("trait-%d.png" % int(member.id))
		await _key_battle(KEY_ESCAPE)
	await _key_battle(KEY_ESCAPE)
	_expect(app.camp_scene.is_visible_in_tree(),"Esc returns to existing camp")


func _field_search(world: Expedition) -> void:
	for actor: FieldActor in world.survivors:
		var member: Dictionary = SurvivorRoster.member(world._setup_crew,actor.member_id)
		_expect(actor.speed == world.tuning.survivor_speed*TraitRules.factor(member,"move") and actor.trait_shot_factor == TraitRules.factor(member,"shot") and actor.trait_search_factor == TraitRules.factor(member,"search"),"all real personal effects use frozen departure profile for ID%d" % actor.member_id)
		trait_effects.append({"member_id":actor.member_id,"trait":member.growth.trait.duplicate(true),"speed":actor.speed,"shot_factor":actor.trait_shot_factor,"search_factor":actor.trait_search_factor,"ordinary_level":member.growth.level,"xp_total":member.growth.xp_total})
	# A real formation destination puts ID2 at the building's center slot.
	for kind: StringName in [&"cash",&"food"]:
		if not world.supply.supports(kind) or world.search_site(kind).searched:
			continue
		if world.search_actor != null:
			world.request_search(world._active_site.kind)
		world.command_move(world.search_site(kind).door)
		for frame: int in range(1500):
			if world.survivors.all(func(actor: FieldActor) -> bool: return actor.activity != FieldActor.Activity.MOVING):
				break
			await _step(world)
		world.request_search(kind)
		var worker: int = world.search_actor.member_id if world.search_actor != null else 0
		var factor: float = world.search_actor.trait_search_factor
		var initial_progress: float = world.search_site(kind).progress
		var work_seconds: float = 0
		for frame: int in range(3000):
			if world.search_site(kind).searched:
				break
			var before_progress: float = world.search_site(kind).progress
			var before_time: float = world.elapsed
			await _step(world)
			if world.search_site(kind).progress > before_progress:
				work_seconds += world.elapsed-before_time
		_expect(world.search_site(kind).searched,"actual search completes at existing building")
		var entries: Array = world.trait_inputs.events.filter(func(row: Dictionary) -> bool: return row.site == String(kind))
		_expect(entries.size() == 1 and entries[0].member_id == worker,"one actual completion records its real worker only")
		search_measurements.append({"member_id":worker,"site":String(kind),"factor":factor,"initial_progress":initial_progress,"actual_work_seconds":work_seconds,"expected_work_seconds":(world.tuning.search_seconds-initial_progress)*factor})
		_expect(absf(work_seconds-(world.tuning.search_seconds-initial_progress)*factor)<0.037,"real worker clock measures its frozen Trait search effect")
		await _capture("search-"+String(kind)+".png")
	await super._field_search(world)


func _field_bus(world: Expedition) -> void:
	for frame: int in range(900):
		if world.elapsed >= world.tuning.bus_ready_seconds:
			break
		await _step(world)
	world.request_bus_action()
	for frame: int in range(180):
		if world.phase == Expedition.Phase.BOARDING:
			break
		await _step(world)
	await _capture("waiting-team.png")
	world.request_bus_gather()
	var captured_wait: bool = false
	for frame: int in range(3000):
		var status: Dictionary = world.boarding_status()
		if not captured_wait and status.arrived > 0 and status.arrived < status.required:
			captured_wait = true
			_expect(world.phase != Expedition.Phase.FINISHED,"partly arrived team never extracts early")
			await _capture("not-all-arrived.png")
		if world.phase == Expedition.Phase.FINISHED:
			break
		await _step(world)
	_expect(_reports.size() == 1 and _reports[0].evacuated,"all real live participants reach original bus and freeze one result")
	var boarding: Dictionary = world.boarding_status()
	_write(output_dir.path_join("boarding.json"),boarding)
	_expect(boarding.arrived == boarding.required and boarding.required == world.living_count(),"final actual bus has every living action member at door")
	var state: Dictionary = app.progress_session.inspect()
	_expect(state.error == OK and state.state == "RECOVERY_READY","original READY includes dynamic member XP and immutable join")
	if state.error != OK:
		_write(output_dir.path_join("prepare-failure.json"),state)
		return
	_write(output_dir.path_join("frozen.json"),state.receipt)
	_reject_replays("RESULT_READY")
	await _capture("field-result.png")
	if field_case == "ready":
		return
	if field_case == "ack":
		app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_commit_receipt" else OK
	if field_case == "locked":
		app.progress_session.fault_hook = _lock_barrier
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	if field_case in ["ack","locked"]:
		_expect(app._progress_blocked and TransactionReceipt.same(_initial,app.camp_snapshot()),"failed ACK never applies membership/XP/food in memory")
		await _capture("ack-failed.png")
		if field_case == "locked":
			_write(output_dir.path_join("unlock-request.json"),{"pid":OS.get_process_id()})
			for frame: int in range(500):
				if FileAccess.file_exists(output_dir.path_join("unlocked")):
					break
				await get_tree().create_timer(0.02).timeout
		app.progress_session.fault_hook = Callable()
		await _tap(app._retry_button)
	var after: Dictionary = app.camp_snapshot()
	_expect(_trait_problem(after).is_empty(),"strict106 committed camp with source membership and growth")
	if not _reports[0].field_joins.is_empty():
		var third: Dictionary = SurvivorRoster.member(after.crew,3)
		_expect(after.recruits.size() == 1 and third.growth.xp_total == (SurvivorRoster.member(_reports[0].member_results,3).kills*10 if third.health > 0 and not _reports[0].xp_inputs.diagnostic else 0),"this outing's real ID3 XP survives unique camp registration")
		_expect(after.last_day.food_required == _reports[0].member_results.filter(func(row: Dictionary) -> bool: return row.health > 0 and not SurvivorRoster.member(_initial.crew,int(row.id)).is_empty()).size(),"first rescue meal retains departure-only policy")
	var ledger: Dictionary = state.receipt.envelope.result.traits
	_expect(ledger.ruleset_id == TraitRules.RULESET,"separate Trait ledger committed with original XP ledger")
	for row: Dictionary in ledger.members:
		var member: Dictionary = SurvivorRoster.member(after.crew,int(row.member_id))
		var source: Array = _reports[0].trait_inputs.events if row.member_id == 2 else _reports[0].xp_inputs.events
		var personal: int = source.filter(func(event: Dictionary) -> bool: return event.member_id == row.member_id).size()
		_expect(row.gained == (personal if row.eligible else 0) and member.growth.trait.progress == row.before.progress+row.gained,"only actual owned actions grant Trait progress to ID%d" % int(row.member_id))
		_expect(TransactionReceipt.same(member.growth.trait,row.after),"saved Trait matches its independent ledger")
	var digest: String = _digest()
	app.progress_session.activate()
	_expect(digest == _digest(),"duplicate activation cannot add member/gun/XP/HP/meal/date")
	_reject_replays("COMMITTED")
	await _capture("camp-after.png")
	await _profiles()



func _finish_camp() -> void:
	_write(output_dir.path_join("trait-effects.json"),{"effects":trait_effects,"search_measurements":search_measurements})
	await super._finish_camp()


func _task_path() -> String:
	return "/.local/m5-trait-01/"


func _trait_problem(data: Dictionary) -> String:
	return TraitState.problem(data)
