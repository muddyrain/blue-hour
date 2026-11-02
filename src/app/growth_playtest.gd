class_name GrowthPlaytest
extends RescuePlaytest
## Explicit isolated verification. Simulation steps and viewport intentions are not physical input.

var growth_case: String = "rescue"
var _deployment: Array[Dictionary] = []
var _battle_events: Array[Dictionary] = []
var _lock_prepared: bool = false


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--growth-case="):
			growth_case = arg.trim_prefix("--growth-case=")
		if arg.begins_with("--growth-expected="):
			expected_path = arg.trim_prefix("--growth-expected=")
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if growth_case == "blocked":
		_expect(app._progress_blocked and not app._requires_continue,"invalid growth binding or unfinished action cannot fall back to old camp")
		await _capture("blocked.png")
		await _finish_growth()
		return
	if growth_case in ["save","resave","resume","three-save","three-resave","three-resume","death-save","death-resave","death-resume"]:
		# Explicit near-enemy fixture only. Normal growth launcher keeps pilot drills disabled.
		if growth_case.begins_with("death-"):
			app.survival_pilot = false
		await _growth_recovery()
		await _finish_growth()
		return
	await _enter()
	_initial = app.camp_snapshot()
	_expect(GrowthState.problem(_initial).is_empty() and _initial.schema_version == 104,"explicit strict104 trial, old formats remain independent")
	if not expected_path.is_empty():
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		_expect(TransactionReceipt.same(_initial,expected.camp),"fresh PID restores every original growth/HP/weapon/food/identity value")
	await _capture("camp-before.png")
	if growth_case == "hold":
		_write(output_dir.path_join("holding.json"),{"pid":OS.get_process_id()})
		for frame: int in range(1000):
			if FileAccess.file_exists(output_dir.path_join("release")):
				break
			await get_tree().create_timer(0.03).timeout
		await _finish_growth()
		return
	if growth_case in ["continue","long"]:
		if growth_case == "long":
			app.open_roster()
			await _settle()
			app.roster_panel.name_edit.text = "一二三四五六七八九十天地"
			await _tap(app.roster_panel.save_button)
			_expect(SurvivorRoster.member(app.crew,app.roster_panel.selected_member_id).call_sign.length() == 12,"actual name control accepts12 Chinese characters without changing growth")
			app.close_roster()
		await _profiles()
		await _finish_growth()
		return
	await _open_map(2 if growth_case in ["rescue","ready","ack","locked","skip"] else (0 if growth_case in ["repair","death3","sole2","starvation"] else 1))
	var world: Expedition = app.expedition
	if world == null:
		await _finish_growth()
		return
	world.set_physics_process(false)
	world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
	world.combat_feedback.connect(func(value: Dictionary) -> void: _battle_events.append(value.duplicate(true)))
	for actor: FieldActor in world.survivors:
		var member: Dictionary = SurvivorRoster.member(_initial.crew,actor.member_id)
		_expect(actor.max_health == GrowthRules.maximum(member) and actor.health == member.health,"deployed stable ID%d uses persisted current and derived max HP" % actor.member_id)
		_deployment.append({"id":actor.member_id,"health":actor.health,"max_health":actor.max_health,"weapon":actor.weapon_instance_id})
	await _rescue_ui(world)
	if growth_case in ["death3","sole2"]:
		rescue_case = growth_case
		await _real_death(world)
	if world.rescue_target != null and growth_case != "skip":
		await _tap(world.rescue_target.button)
		for frame: int in range(1800):
			if world.rescue_target.status == "RESCUED":
				break
			await _step(world)
		_expect(world.rescue_target.status == "RESCUED" and app.crew.size() == 2,"real assistance/NPC route precede camp recruitment and never grant XP")
		await _capture("rescued-world.png")
	await _search_and_return(world)
	if growth_case == "rescue" and _initial.settled_sorties >= 2:
		_expect(_deployment.any(func(row: Dictionary) -> bool: return row.max_health > 200 and _reports[0].member_results.any(func(result: Dictionary) -> bool: return result.id == row.id and result.damage_received > 0)),"naturally grown actor in next process takes original AI damage with new maxHP; unchanged guns, director and stats")
	await _finish_growth()


func _search_and_return(world: Expedition) -> void:
	if not world.searched and world.search_actor == null:
		world.request_search(&"cash")
	if growth_case == "pressure":
		world.request_search(&"food")
		world.command_move(Vector2(568,864))
	for frame: int in range(3600):
		if world.searched:
			break
		await _step(world)
	if world.supply.supports(&"food") and not world._food_site.searched and growth_case != "starvation":
		world.request_search(&"food")
		for frame: int in range(3600):
			if world._food_site.searched:
				break
			await _step(world)
	if growth_case == "pressure":
		for frame: int in range(2400):
			if world.survivors.any(func(actor: FieldActor) -> bool: return actor.max_health > 200 and actor.damage_received > 0):
				break
			if world.elapsed >= 140.0:
				break
			await _step(world)
		_expect(world.survivors.any(func(actor: FieldActor) -> bool: return actor.max_health > 200 and actor.damage_received > 0),"subsequent upgraded actor takes real original AI damage with grown maximum, no stat or spawn override")
	await _capture("battle-pending-xp.png")
	_expect(TransactionReceipt.same(app.camp_snapshot(),_initial),"real battle XP stays pending; no mid-sortie level or healing")
	for frame: int in range(1800):
		if world.elapsed >= world.tuning.bus_ready_seconds:
			break
		await _step(world)
	world.request_bus_action()
	for frame: int in range(180):
		if world.phase == Expedition.Phase.BOARDING:
			break
		await _step(world)
	world.request_bus_gather()
	for frame: int in range(3600):
		if world.phase == Expedition.Phase.FINISHED:
			break
		await _step(world)
	_expect(_reports.size() == 1 and _reports[0].evacuated,"original real bus freezes exactly one complete result")
	if _reports.is_empty():
		return
	var state: Dictionary = app.progress_session.inspect()
	_expect(state.error == OK and state.state in ["RECOVERY_READY","ENDED"] and not state.receipt.envelope.result.get("xp",{}).is_empty(),"original transaction freezes full XP ledger with economy and life history")
	if state.error != OK or not state.has("receipt"):
		_write(output_dir.path_join("prepare-failure.json"),state)
		return
	_write(output_dir.path_join("frozen.json"),state.receipt)
	_reject_replays("RESULT_READY")
	await _capture("result-growth.png")
	if growth_case == "ready":
		return
	if not app._pending_settlement.is_empty():
		if growth_case == "ack":
			app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_commit_receipt" else OK
		if growth_case == "locked":
			app.progress_session.fault_hook = _lock_barrier
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		if growth_case in ["ack","locked"]:
			_expect(app._progress_blocked and TransactionReceipt.same(_initial,app.camp_snapshot()),"persistent ACK failure does not apply XP/recruitment in memory")
			await _capture("ack-failed.png")
			if growth_case == "locked":
				_write(output_dir.path_join("unlock-request.json"),{"pid":OS.get_process_id()})
				for frame: int in range(500):
					if FileAccess.file_exists(output_dir.path_join("unlocked")):
						break
					await get_tree().create_timer(0.02).timeout
			app.progress_session.fault_hook = Callable()
			await _tap(app._retry_button)
	var after: Dictionary = app.camp_snapshot()
	_expect(GrowthState.problem(after).is_empty(),"acknowledged growth camp validates all identities and derived attributes")
	var ledger: Dictionary = state.receipt.envelope.result.xp
	for participant: Dictionary in _reports[0].participants:
		var row: Dictionary = GrowthRules.member_row(ledger.members,int(participant.id))
		var member: Dictionary = SurvivorRoster.member(after.crew,int(participant.id))
		var old: Dictionary = SurvivorRoster.member(_initial.crew,int(participant.id))
		_expect(row.xp_after == member.growth.xp_total and row.level_after == member.growth.level,"ledger and camp agree for original ID%d" % int(participant.id))
		_expect(member.growth.xp_total == int(old.growth.xp_total)+(int(row.defeats)*10 if row.eligible else 0),"personal XP uses full owned defeat evidence for ID%d" % int(participant.id))
		_expect(member.health == row.health_before+5*(int(row.level_after)-int(row.level_before)) if row.eligible else member.health == row.health_before,"level gain preserves absolute wounds and never revives ID%d" % int(participant.id))
	if _initial.recruits.is_empty() and after.recruits.size() == 1:
		var recruit: Dictionary = SurvivorRoster.member(after.crew,3)
		_expect(recruit.growth.xp_total == 0 and recruit.growth.level == 1 and recruit.health == 200 and recruit.service.kills == 0,"newly rescued ID3 never receives earlier teammates' XP")
	var bytes: String = _digest()
	app.progress_session.activate()
	_expect(bytes == _digest(),"repeated committed activation cannot add XP/HP/recruit/food/date again")
	_reject_replays("COMMITTED")
	await _capture("camp-after.png")
	await _profiles()


func _growth_recovery() -> void:
	var resuming: bool = growth_case in ["resave","resume","three-resave","three-resume","death-resave","death-resume"]
	if not resuming:
		await _enter()
		_initial = app.camp_snapshot()
		await _open_map(1 if growth_case == "three-save" else (0 if growth_case == "death-save" else 2))
	else:
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible:
			await _tap(app._hunger_confirmation.get_ok_button())
		_initial = app.camp_snapshot()
	var world: Expedition = app.expedition
	_expect(world != null,"first Continue/departure opens actual104 world")
	if world == null:
		return
	world.set_physics_process(false)
	world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
	if growth_case == "death-resave":
		rescue_case = "death3"
	if resuming:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		captured = SortieSnapshot.capture(world)
		_write(output_dir.path_join("restored.json"),captured)
		_expect(TransactionReceipt.same(expected,captured),"full XP events/owners/suffix/HP/rescue/world exactly restore across independent PIDs")
		for record: String in DirAccess.get_directories_at(app.progress_path+".txn/journal"):
			var path: String = (app.progress_path+".txn/journal").path_join(record).path_join("record.json")
			var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)).payload
			if payload.phase == "SUSPEND_READY":
				replay_tokens.append({"token":RunTransaction.token_for(payload),"hash":payload.envelope.world_hash,"generation":payload.envelope.previous_head})
		_reject_replays("RESUME_CLAIMED")
		await _capture("restored-paused.png")
		await _tap(app.pause_menu.buttons[0])
		if world.is_paused:
			await _key_battle(KEY_SPACE)
		if growth_case == "death-resave":
			if world.search_actor != null:
				world.request_search(world._active_site.kind)
			await _real_death(world)
			_reject_replays("CONFIRMED_DEATH")
		if growth_case == "death-resume":
			_expect(world.survivors[2].permanent_death and world.survivors[2].health == 0,"latest S2 cannot revive confirmed ID3 death")
	if growth_case in ["resume","three-resume","death-resume"]:
		if world.rescue_target != null:
			if world.rescue_target.worker == 0:
				await _tap(world.rescue_target.button)
			for frame: int in range(1800):
				if world.rescue_target.status == "RESCUED":
					break
				await _step(world)
		await _search_and_return(world)
		return
	if world.rescue_target != null:
		if world.rescue_target.worker == 0:
			await _tap(world.rescue_target.button)
		for frame: int in range(1800):
			if world.rescue_target.progress > (5.0 if resuming else 1.0):
				break
			await _step(world)
		_expect(world.rescue_target.progress > 0 and world.rescue_target.status == "IN_PROGRESS","rescue is genuinely partial before104 suspend")
	else:
		if world.search_actor == null and not world.searched:
			world.request_search(&"cash")
		for frame: int in range(1500):
			if world.elapsed > (35.0 if resuming else 25.0):
				break
			await _step(world)
	await _key_battle(KEY_ESCAPE)
	await _frozen(world,"growth-suspend")
	captured = SortieSnapshot.capture(world)
	_write(output_dir.path_join("snapshot.json"),captured)
	_expect(captured.xp_inputs.events.size() == world.xp_inputs.events.size(),"104 suspend never truncates complete pending XP evidence")
	await _tap(app.pause_menu.buttons[4])
	var state: Dictionary = app.progress_session.inspect()
	_expect(state.error == OK and state.state == "SUSPENDED" and app.expedition == null,"safe suspend acknowledged before leaving native world")
	if state.error == OK and state.has("receipt"):
		_expect(TransactionReceipt.same(captured,state.receipt.envelope.world),"readback preserves exact growth snapshot")
	_reject_replays("NEW_SUSPEND")
	await _capture("saved-home.png")


func _profiles() -> void:
	if app.camp_snapshot().journey.state == "FAILED":
		_expect(app.crew.all(func(member: Dictionary) -> bool: return member.health == 0),"terminal hunger/death keeps full dead history and no roster editing")
		await _capture("terminal.png")
		return
	app.open_roster()
	await _settle()
	for member: Dictionary in app.crew:
		await _tap(app.roster_panel.member_buttons[int(member.id)-1])
		_expect(app.roster_panel._health.max_value == GrowthRules.maximum(member),"profile HP bar uses derived maximum for ID%d" % int(member.id))
		_expect(app.roster_panel._service.get_global_rect().end.x <= get_viewport().get_visible_rect().size.x and app.roster_panel.back_button.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y,"profile text and return action fit actual viewport")
		await _capture("profile-%d.png" % int(member.id))
	app.open_growth(3 if app.crew.size() == 3 else 2)
	await _settle()
	_expect(app.growth_panel.training_button.disabled,"Trait and food training stay unavailable and cannot charge food")
	_expect(app.growth_panel.training_button.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y,"growth training boundary remains inside viewport")
	await _capture("growth-detail.png")
	app.close_growth()
	app.close_roster()


func _lock_barrier(point: String) -> Error:
	if point != "before_camp_write" or _lock_prepared:
		return OK
	_write(output_dir.path_join("lock-request.json"),{"pid":OS.get_process_id()})
	var deadline: int = Time.get_ticks_msec()+10000
	while not FileAccess.file_exists(output_dir.path_join("locked")) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(20)
	_lock_prepared = true
	return OK if FileAccess.file_exists(output_dir.path_join("locked")) else ERR_CANT_CREATE


func _finish_growth() -> void:
	_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,"case":growth_case,"initial":_initial,"camp":app.camp_snapshot(),"reports":_reports,"deployment":_deployment,"battle_events":_battle_events,"window_size":DisplayServer.window_get_size(),"input_layer":"native viewport and original gameplay intents, NOT physical OS"})
	app.audio.shutdown()
	OS.delay_msec(150)
	await _settle()
	get_tree().quit(0 if _failures == 0 else 1)
