class_name FieldJoinPlaytest
extends GrowthPlaytest
## Isolated native intentions. No physical OS input or direct XP/stat injection.

var field_case: String = "rescue"
var _npc_instance: int = 0
var _joined_at: int = -1


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--field-case="):
			field_case = arg.trim_prefix("--field-case=")
		if arg.begins_with("--field-expected="):
			expected_path = arg.trim_prefix("--field-expected=")
	growth_case = field_case
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _settle()
	await get_tree().create_timer(0.3).timeout
	if field_case == "blocked":
		_expect(app._progress_blocked and not app._requires_continue,"invalid105 action cannot fall back to camp")
		await _finish_field()
		return
	if field_case == "death-resume":
		app.survival_pilot = false
	if field_case in ["resave","resume","death-resume"]:
		await _restore_field()
		await _finish_field()
		return
	await _enter()
	_initial = app.camp_snapshot()
	_expect(FieldJoinState.problem(_initial).is_empty(),"strict explicit105 field-join camp")
	if not expected_path.is_empty():
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		_expect(TransactionReceipt.same(_initial,previous.camp),"new PID keeps complete growth/equipment/identity/food/death camp")
	await _capture("camp-before.png")
	if field_case == "hold":
		_write(output_dir.path_join("holding.json"),{"pid":OS.get_process_id()})
		for frame: int in range(1000):
			if FileAccess.file_exists(output_dir.path_join("release")):
				break
			await get_tree().create_timer(0.03).timeout
		await _finish_field()
		return
	if field_case == "continue":
		await _profiles()
		await _finish_field()
		return
	if field_case.begins_with("death-"):
		app.survival_pilot = false
	await _open_map(0 if field_case in ["repair","death-original"] else (1 if field_case == "market" else 2))
	var world: Expedition = app.expedition
	if world == null:
		await _finish_field()
		return
	world.set_physics_process(false)
	world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
	world.combat_feedback.connect(func(value: Dictionary) -> void: _battle_events.append(value.duplicate(true)))
	await _rescue_ui(world)
	if field_case == "death-original":
		await _field_death(world,1)
	if world.rescue_target != null and field_case not in ["skip","incomplete"]:
		var target: RescueTarget = world.rescue_target
		_npc_instance = target.npc.get_instance_id()
		_expect(world.survivors.size() == _initial.journey.active_member_ids.size(),"before rescue only original living departure actors")
		await _capture("before-join.png")
		if field_case in ["bus-ready","bus-engine","bus-boarding"]:
			for frame: int in range(1500):
				if world.elapsed >= world.tuning.bus_ready_seconds:
					break
				await _step(world)
			world.request_search(&"food")
		await _tap(target.button)
		if field_case == "bus-boarding":
			world.request_bus_action()
		for frame: int in range(1500):
			if target.progress > 9.5:
				break
			await _step(world)
		await _capture("rescue-nearly-complete.png")
		if field_case == "bus-engine":
			world.request_bus_action()
		var worker: FieldActor = world.search_actor
		var work_progress: float = world._active_site.progress if worker != null else 0

		if field_case == "save-before":
			await _save_field(world)
			await _finish_field()
			return
		if field_case in ["join-write","join-binding"]:
			var point: String = "before_record_write" if field_case == "join-write" else "before_binding_write"
			app.progress_session.fault_hook = func(at: String) -> Error: return ERR_CANT_CREATE if at == point else OK
		for frame: int in range(120):
			if target.status == "IN_FIELD_JOINED":
				break
			await _step(world)
		if field_case in ["join-write","join-binding"]:
			_expect(world.is_paused and world.survivors.size() == _initial.journey.active_member_ids.size() and not world.field_join_error.is_empty(),"unacknowledged join never adds actor/HUD/attack authority")
			_expect(SortieSnapshot.capture(world).is_empty(),"unacknowledged join blocks unsafe snapshot")
			var frozen: Dictionary = {"time":world.elapsed,"growth":world.growth_inputs.snapshot(world.sortie_id,world.layout.id,world.elapsed),"xp":world.xp_inputs.snapshot(world),"actors":world.survivors.map(func(actor: FieldActor) -> Dictionary: return SortieSnapshot._fields(actor,SortieSnapshot.ACTOR))}
			await _key_battle(KEY_SPACE)
			world.command_move(world.layout.bus_door)
			world.request_search(&"cash")
			for frame: int in range(30):
				await _step(world)
			_expect(world.is_paused and TransactionReceipt.same(frozen,{"time":world.elapsed,"growth":world.growth_inputs.snapshot(world.sortie_id,world.layout.id,world.elapsed),"xp":world.xp_inputs.snapshot(world),"actors":world.survivors.map(func(actor: FieldActor) -> Dictionary: return SortieSnapshot._fields(actor,SortieSnapshot.ACTOR))}),"failed join seals time/path/HP/kills/XP against pause/move/search until ACK")
			await _capture("join-unacknowledged.png")
			app.progress_session.fault_hook = Callable()
			await _tap(target.button)
			_expect(world.field_join_error.is_empty(),"same cached join identity retries through original writer")
			if world.is_paused:
				await _key_battle(KEY_SPACE)
		_expect(target.status == "IN_FIELD_JOINED" and world.survivors.size() == _initial.journey.active_member_ids.size()+1,"real10 seconds immediately add same-map ID3 to live team")
		_expect(target.npc.get_instance_id() == _npc_instance and world.survivors.has(target.npc),"same original NPC node promoted, never cloned or teleported")
		_expect(target.npc.member_id == 3 and target.npc.weapon_instance_id == RescueState.weapon(_initial.profile_id).instance_id and target.npc.damage_gate.is_valid(),"stable ID3 owns original unique gun and existing persistent death gate")
		_expect(world.boarding_status().required == world.living_count() and world.boarding_status().required == _initial.journey.active_member_ids.size()+1,"bus denominator includes new ID3 immediately before any camp commit")
		_expect(TransactionReceipt.same(_initial,app.camp_snapshot()),"field membership does not precommit camp or rations")
		_joined_at = int(world.field_joins[0].at_ms)
		await _capture("joined-three.png")
		if field_case.begins_with("bus-"):
			_expect(world.phase == (Expedition.Phase.ENGINE if field_case == "bus-engine" else (Expedition.Phase.BOARDING if field_case == "bus-boarding" else Expedition.Phase.ACTIVE)),"join occurs in requested natural bus phase")
			_expect(worker != null and world.search_actor == worker and world._active_site.progress >= work_progress,"existing food worker remains assigned through membership and engine change")
			await _key_battle(KEY_ESCAPE)
			await _layout("joined-menu")
			await _frozen(world,"joined-menu")
			await _key_battle(KEY_ESCAPE)
			await _tap(world._hud.view._help_button)
			_expect(world.boarding_status().required == 3,"help retains dynamic three-person bus denominator")
			await _key_battle(KEY_ESCAPE)

		var positions: Array[Vector2] = []
		for actor: FieldActor in world.survivors:
			positions.append(actor.position)
		world.command_move(Vector2(1152,1008))
		for frame: int in range(30):
			await _step(world)
		for index: int in range(world.survivors.size()):
			if world.survivors[index] == world.search_actor:
				_expect(world.search_actor == worker,"formation preserves active original worker")
				continue
			_expect(world.survivors[index].position.distance_to(positions[index]) > 1,"same original ground formation command moves member%d" % world.survivors[index].member_id)
		await _capture("formation-three.png")
		if field_case == "save-joined":
			await _save_field(world)
			await _finish_field()
			return
	if field_case == "incomplete":
		await _tap(world.rescue_target.button)
		for frame: int in range(1200):
			if world.rescue_target.progress > 3:
				break
			await _step(world)
		world.command_move(world.layout.bus_door)
		_expect(world.field_joins.is_empty() and world.survivors.size() == 2,"cancelled partial assistance never creates member or gun")
	if field_case == "danger":
		app.request_exit("home")
		await _settle()
		await _tap(app.pause_menu.buttons[1])
		_expect(app.expedition == null and app._progress_blocked and TransactionReceipt.same(_initial,app.camp_snapshot()),"joined but dangerous abandonment cannot register camp or return old journey")
		await _capture("danger-blocked.png")
		await _finish_field()
		return
	if field_case == "death-terminal":
		for id: int in [3,1,2]:
			await _field_death(world,id)
		_expect(_reports.size() == 1 and not _reports[0].evacuated and app.camp_snapshot().journey.state == "FAILED" and app.camp_snapshot().recruits[0].field_status == "LOST","all confirmed deaths end105 journey with history/gun and no living recruit")
		await _capture("terminal.png")
		await _finish_field()
		return
	if field_case == "death-save":
		await _field_death(world,3)
		await _save_field(world)
		await _finish_field()
		return
	await _field_search(world)
	await _field_bus(world)
	await _finish_field()


func _field_search(world: Expedition) -> void:
	if world.search_actor != null and world._active_site.kind != &"cash":
		for frame: int in range(3000):
			if world.search_actor == null:
				break
			await _step(world)
	if not world.searched and world.search_actor == null:
		world.request_search(&"cash")
	for frame: int in range(3000):
		if world.searched:
			break
		await _step(world)
	if world.supply.supports(&"food") and not world._food_site.searched and field_case != "starvation":
		world.request_search(&"food")
		for frame: int in range(3000):
			if world._food_site.searched:
				break
			await _step(world)
	if not world.field_joins.is_empty() and world.rescue_target.npc.health > 0:
		world.command_move(Vector2(568,864))
		for frame: int in range(1800):
			if world.rescue_target.npc.confirmed_kills > 0:
				break
			await _step(world)
		_expect(world.rescue_target.npc.confirmed_kills > 0,"ID3 truly defeats an enemy in this rescue outing with original automatic combat")
		await _capture("id3-combat.png")


func _save_field(world: Expedition) -> void:
	if not app.pause_menu.root.visible:
		await _key_battle(KEY_ESCAPE)
	captured = SortieSnapshot.capture(world)
	_write(output_dir.path_join("snapshot.json"),captured)
	_expect(not captured.is_empty(),"105 complete actors/join/XP/rescue snapshot exists")
	await _tap(app.pause_menu.buttons[4])
	var state: Dictionary = app.progress_session.inspect()
	_expect(state.error == OK and state.state == "SUSPENDED" and app.expedition == null,"original writer ACKs complete105 snapshot before leaving")
	if state.error == OK and state.has("receipt"):
		_expect(TransactionReceipt.same(captured,state.receipt.envelope.world),"readback preserves joined member and all authority")
	_reject_replays("LATEST_SUSPEND")
	await _capture("saved-home.png")


func _restore_field() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_expect(world != null,"single first Continue reconstructs original105 world")
	if world == null:
		return
	world.set_physics_process(false)
	_initial = app.camp_snapshot()
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	captured = SortieSnapshot.capture(world)
	_write(output_dir.path_join("restored.json"),captured)
	_expect(TransactionReceipt.same(expected,captured),"independent PID restores every actor/XP/health/weapon/join/clock/path value")
	for folder: String in DirAccess.get_directories_at(app.progress_path+".txn/journal"):
		var record: Dictionary = app.progress_session._transaction._journal._read_record((app.progress_path+".txn/journal").path_join(folder).path_join("record.json")).receipt
		if record.phase == "SUSPEND_READY":
			replay_tokens.append({"token":RunTransaction.token_for(record),"hash":record.envelope.world_hash,"generation":record.envelope.previous_head})
	_reject_replays("RESUME_CLAIMED")
	world.finished.connect(func(value: Dictionary) -> void: _reports.append(value.duplicate(true)))
	world.combat_feedback.connect(func(value: Dictionary) -> void: _battle_events.append(value.duplicate(true)))
	await _capture("restored-paused.png")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		await _key_battle(KEY_SPACE)
	if world.rescue_target != null and world.field_joins.is_empty():
		if world.rescue_target.worker == 0:
			await _tap(world.rescue_target.button)
		for frame: int in range(1200):
			if not world.field_joins.is_empty():
				break
			await _step(world)
		_expect(world.field_joins.size() == 1 and world.survivors.size() == 3,"partial S1 really completes assistance and joins same-map third")
	if not world.field_joins.is_empty():
		_joined_at = int(world.field_joins[0].at_ms)
	if field_case == "death-resume":
		_expect(world.rescue_target.npc.health == 0 and world.rescue_target.npc.permanent_death,"S2/journal never revives confirmed field recruit")
	if field_case == "resave":
		await _field_search(world)
		_reject_replays("JOINED_AND_FOUGHT")
		await _save_field(world)
	else:
		await _field_search(world)
		await _field_bus(world)


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
	_expect(FieldJoinState.problem(after).is_empty(),"strict105 committed camp with source membership and growth")
	if not _reports[0].field_joins.is_empty():
		var third: Dictionary = SurvivorRoster.member(after.crew,3)
		_expect(after.recruits.size() == 1 and third.growth.xp_total == (SurvivorRoster.member(_reports[0].member_results,3).kills*10 if third.health > 0 and not _reports[0].xp_inputs.diagnostic else 0),"this outing's real ID3 XP survives unique camp registration")
		_expect(after.last_day.food_required == _reports[0].member_results.filter(func(row: Dictionary) -> bool: return row.health > 0 and not SurvivorRoster.member(_initial.crew,int(row.id)).is_empty()).size(),"first rescue meal retains departure-only policy")
	var digest: String = _digest()
	app.progress_session.activate()
	_expect(digest == _digest(),"duplicate activation cannot add member/gun/XP/HP/meal/date")
	_reject_replays("COMMITTED")
	await _capture("camp-after.png")
	await _profiles()


func _finish_field() -> void:
	_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"case":field_case,"checks":_checks,"failures":_failures,"initial":_initial,"camp":app.camp_snapshot(),"reports":_reports,"battle_events":_battle_events,"joined_at_ms":_joined_at,"npc_instance":_npc_instance,"window_size":DisplayServer.window_get_size(),"input_layer":"native viewport/original intentions; NOT physical OS"})
	app.audio.shutdown()
	OS.delay_msec(150)
	await _settle()
	get_tree().quit(0 if _failures == 0 else 1)


func _field_death(world: Expedition, id: int) -> void:
	if world.drill_panel != null:
		world.drill_panel.queue_free()
	world.battle_drill = true
	world.drill_panel = BattleDrillPanel.new()
	world.drill_panel.expedition = world
	world._hud.view.add_child(world.drill_panel)
	await _settle()
	var target: FieldActor = world.drill_panel._member(id)
	_expect(target != null,"explicit contact fixture has requested stable ID")
	if target == null:
		return
	if target.permanent_death:
		_expect(target.health == 0,"already confirmed death stays dead")
		return
	world.command_move(world.layout.bus_door)
	target.clear_order()
	for actor: FieldActor in world.survivors:
		actor.cooldown = 999.0
	for button: Button in world.drill_panel.buttons:
		if int(button.get_meta("member_id")) == id:
			await _tap(button)
	for frame: int in range(6000):
		if target.permanent_death:
			break
		await _step(world)
	_expect(target.permanent_death and target.health == 0,"original AI/4 damage/death writer confirm ID%d, no direct health mutation" % id)
	_expect(world.boarding_status().required == world.living_count(),"bus removes real confirmed death immediately")
	for actor: FieldActor in world.survivors:
		actor.cooldown = 0
	await _capture("confirmed-death.png")
