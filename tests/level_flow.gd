extends "res://tests/exploration_flow.gd"
## Normal cards and real intentions; synthetic isolated progress, no earned-state edits.
var task_kind: String = "supply"
var sample_size: String = "medium"
var preview_only: bool = false
var move_record: Array = []

func _menu(_count: int=0) -> void:
	await super._menu(_count)
	await _hold(2)
	var visible: bool=viewport.get_visible_rect().encloses(app.mission_select.cancel_button.get_global_rect())
	for button: Button in app.mission_select.choices:
		visible=visible and viewport.get_visible_rect().encloses(button.get_global_rect())
	_check(visible,"normal task descriptions keep all departure and cancel controls inside the viewport")

func _journey() -> void:
	FreezeProfile.enabled = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level-type="):
			task_kind = arg.trim_prefix("--level-type=")
		if arg.begins_with("--flow-size="):
			sample_size = arg.trim_prefix("--flow-size=")
	preview_only = "--flow-preview" in OS.get_cmdline_user_args()
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(WorldgenState.level_enabled(app.camp_snapshot()), "new ordinary root opts into level policy")
	await _menu()
	var offered: Array = app.mission_select.daily_offers.duplicate(true)
	await _tap(app.mission_select.cancel_button)
	await _menu()
	_check(TransactionReceipt.same({"v":offered}, {"v":app.mission_select.daily_offers}), "browsing and returning to camp cannot redraw the day")
	var slot: int = -1
	for index: int in range(offered.size()):
		if offered[index].type == task_kind and offered[index].layout["size"] == sample_size:
			slot = index
	_check(slot >= 0, "fixed initial journey legitimately offers requested task and scale")
	if slot < 0:
		return
	var world: Expedition = await _start(slot)
	if world == null:
		return
	var generated: Dictionary = world.supply.generated
	_write("frozen-action.json", generated)
	acceptance = {"departure":_before.duplicate(true), "task":task_kind, "action":generated.id, "seed":generated.seed, "layout_seed":generated.layout.seed, "size":sample_size, "versions":[generated.version, generated.layout.version, generated.worldgen.version], "camera_zoom":world.camera.zoom.x, "buildings":generated.layout.entities.size(), "objects":generated.layout.objects.size(), "sites":generated.sites.size(), "routes":generated.exploration.level, "parameters":_parameters(world), "daylight":world.tuning.daylight_seconds, "late_at":world.tuning.daylight_seconds * world.threat.rules.late_fraction}
	world.locate_objective("primary")
	await _shot(task_kind)
	if preview_only:
		_write("acceptance.json", acceptance)
		return
	var primary: Array = generated.objective.site_ids
	var started: float = world.elapsed
	follow_actor = true
	segment_frames = 0
	segment_limit = 180
	recording = true
	if capture_caption != null:
		capture_caption.text = "普通任务 · 自动输入 · 1×原速片段 · 非物理输入"
	if task_kind == "rescue":
		await _tap(world.rescue_target.button)
		await _until(world, func() -> bool: return world.rescue_target.progress > 0.5)
		world.rescue_target.cancel()
		_check(world.field_joins.is_empty(), "cancel before rescue completion grants no member")
		await _tap(world.rescue_target.button)
		await _until(world, func() -> bool: return not world.field_joins.is_empty())
		_check(world.survivors.size() == 3, "original ten-second assistance adds one real actor")
	else:
		for id: String in primary:
			world.request_search(StringName(id))
		if task_kind=="airdrop":
			await _until(world,func() -> bool: return world.search_site(&"cash").progress>2.0)
			var worker: FieldActor=world.search_member(world.search_assignments.member_for("cash"))
			_check(worker.visible and world._combatant(worker).available and world.task_event.started and world.task_event.resolutions.size()==2,"original outdoor worker remains an available combat target and triggers exactly one bounded event")
			acceptance.task_event=world.task_event.duplicate(true)
			var progress: float=world.search_site(&"cash").progress
			world.request_search(&"cash")
			world.request_search(&"cash")
			await _until(world,func() -> bool: return world.search_site(&"cash").progress>progress+0.2)
			_check(TransactionReceipt.same(world.task_event,acceptance.task_event),"cancel and restart preserve progress without another pressure event")
			await _suspend(world)
			return
		if task_kind == "supply" and primary.size() == 2:
			await _until(world, func() -> bool: return world.search_site(StringName(primary[0])).progress > 1.0)
			var other_worker: int = world.search_assignments.member_for(primary[1])
			_check(other_worker>0 and other_worker!=world.search_assignments.member_for(primary[0]), "two distinct actual workers own food jobs")
			world.request_search(StringName(primary[0]))
			_check(world.search_assignments.member_for(primary[1]) == other_worker, "cancel one food job preserves the independent second worker")
			world.request_search(StringName(primary[0]))
		await _until(world, func() -> bool: return primary.all(func(id: String) -> bool: return world.search_site(StringName(id)).searched))
	acceptance.primary_seconds = world.elapsed - started
	acceptance.primary_elapsed = world.elapsed
	acceptance.primary_threat = world.threat.snapshot()
	acceptance.primary_carry = {"cash":world.loot, "food":world.food_loot, "weapons":world.weapon_loot.duplicate(true)}
	acceptance.worker_factors = []
	for actor: FieldActor in world.survivors:
		acceptance.worker_factors.append({"id":actor.member_id,"speed":actor.effective_speed(),"work":actor.trait_search_factor * actor.persona_work_factor * BuildItems.factors(generated.build.slots).work})
	recording = false
	follow_actor = false
	world.camera.pan_by(world.survivors[0].position - Vector2(0, 100) - world.camera.position)
	if task_kind=="equipment":
		world.camera.pan_by(world.search_site(&"cash").door-Vector2(0,140)-world.camera.position)
	await _shot(task_kind)
	if task_kind == "equipment":
		_check(world.weapon_loot.size() == 1, "real deep equipment site carries exactly one original weapon")
		if "--level-direct" in OS.get_cmdline_user_args():
			await _finish_level(world)
			return
		var optional: Expedition.SearchSite = world.search_site(StringName(generated.exploration.level.optional.site_id))
		var extra_start: float = world.elapsed
		world.request_search(optional.id)
		acceptance.optional_worker = world.search_assignments.member_for(String(optional.id))
		acceptance.optional_position = [world.search_member(acceptance.optional_worker).position.x,world.search_member(acceptance.optional_worker).position.y]
		await _until(world, func() -> bool: return optional.progress > 0.5)
		acceptance.optional_started = extra_start
		acceptance.optional_site = String(optional.id)
		await _suspend(world)
		return
	await _finish_level(world)

func _resume() -> void:
	FreezeProfile.enabled = true
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	acceptance = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/acceptance.json")))
	_before = acceptance.departure
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_check(world != null, "new PID restores through ordinary Continue: " + app._progress_message)
	if world == null:
		return
	world.set_process(false)
	world.set_physics_process(false)
	_check(prior.pid != OS.get_process_id() and RecordEncoding.fingerprint(SortieSnapshot.capture(world)) == prior.fingerprint, "new PID restores exact geometry target carry work clock members magazines and personal factors")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()
	if acceptance.task=="airdrop":
		_check(TransactionReceipt.same(world.task_event,acceptance.task_event),"new PID retains original one-shot airdrop event")
		world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
		await _until(world,func() -> bool: return world.search_site(&"cash").searched)
		_check(world.weapon_loot.size()==1 and TransactionReceipt.same(world.task_event,acceptance.task_event),"continued airdrop yields the original single weapon without reinforcements replay")
		await _finish_level(world)
		return
	var before: Dictionary = world.support_world()
	var caller: FieldActor
	for actor: FieldActor in world.survivors:
		if actor.visible and actor.health > 0:
			caller = actor
	_check(caller != null, "working checkpoint leaves an actual outside support caller")
	if caller == null:
		return
	var target: Vector2 = Vector2.INF
	for offset: Vector2 in [Vector2(0,40), Vector2(40,0), Vector2(-40,0), Vector2(0,-40)]:
		if not world.support_plan_airstrike(caller.position + offset).is_empty():
			target = caller.position + offset
			break
	_check(target.is_finite() and world.request_airstrike(target), "original support commits a full-world reconstruction")
	_check(TransactionReceipt.same(world.support_world().sites,before.sites) and TransactionReceipt.same(world.search_assignments.snapshot(),before.jobs), "support retains site and work sources without rerolling")
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	var optional: Expedition.SearchSite = world.search_site(StringName(acceptance.optional_site))
	await _until(world, func() -> bool: return optional.searched)
	acceptance.optional_elapsed = world.elapsed
	acceptance.optional_seconds = world.elapsed - float(acceptance.optional_started)
	acceptance.optional_threat = world.threat.snapshot()
	world.camera.pan_by(optional.door - Vector2(0, 120) - world.camera.position)
	await _shot("equipment-continued")
	await _finish_level(world)

func _finish_level(world: Expedition) -> void:
	acceptance.return_started = world.elapsed
	acceptance.actual_carry = {"cash":world.loot,"food":world.food_loot,"weapons":world.weapon_loot.duplicate(true)}
	world.command_move(world.layout.bus_door)
	await _until(world, func() -> bool: return world.survivors.all(func(actor: FieldActor) -> bool: return actor.health <= 0 or actor.position.distance_to(world.layout.bus_door) < 110))
	world.camera.pan_by(world.layout.bus_door - Vector2(0, 160) - world.camera.position)
	segment_frames = 0
	segment_limit = 240
	recording = true
	await _extract(world)
	await _hold(maxi(0,240-segment_frames))
	recording = false
	acceptance.return_elapsed = world.elapsed
	acceptance.return_threat = world.threat.snapshot()
	acceptance.freeze_profile = FreezeProfile.latest.duplicate(true)
	_check(not app._progress_blocked and not reports.is_empty(), "original real bus departure produces one authenticated result")
	if not reports.is_empty():
		acceptance.report = reports[-1]
		acceptance.outcome = TaskActions.outcome(world.supply.generated, reports[-1])
		_check(acceptance.outcome.status == "COMPLETED", "real task report marks completed main objective")
	var completed: Dictionary = world.supply.generated.duplicate(true)
	var result_token: Dictionary = app.progress_session.token.duplicate(true)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(not app._progress_blocked and app.camp_snapshot().journey.campaign.preparations == 1, "one original confirmation durably banks the task")
	var saved: Dictionary = app.camp_snapshot()
	var duplicate: Dictionary = app.progress_session._transaction.commit(result_token)
	_check(duplicate.error==OK, "same result token accepts idempotent confirmation")
	app.return_to_title()
	_check(TransactionReceipt.same(saved,app.camp_snapshot()), "returning again cannot duplicate carry or weapon")
	acceptance.camp = saved
	var report: Dictionary = acceptance.report
	_check(saved.cash==_before.cash+report.loot and saved.last_day.food_found==report.food, "actual money and food report bank exactly the carried source")
	_check(saved.food==_before.food+saved.last_day.food_stored-saved.last_day.food_consumed, "original food storage and ration algorithm balances exactly")
	for item: Dictionary in report.weapons:
		_check(saved.weapons.filter(func(weapon: Dictionary) -> bool: return weapon.instance_id==item.instance_id).size()==1, "original weapon instance is banked exactly once")
	if completed.type=="rescue":
		_check(saved.crew.any(func(member: Dictionary) -> bool: return member.id==completed.recruit and member.health>0), "actual rescued candidate returns alive into the original roster")
	await _menu()
	_check(app.camp_snapshot().day>_before.day and app.mission_select.daily_offers.all(func(offer: Dictionary) -> bool: return offer.id!=completed.id), "confirmed next day exposes newly sourced candidates")
	acceptance.next_offers = app.mission_select.daily_offers.duplicate(true)
	var exact: FileAccess=FileAccess.open(output.path_join("camp-exact.json"),FileAccess.WRITE)
	exact.store_string(RecordEncoding.stringify({"camp":saved,"offers":app.mission_select.daily_offers}))
	exact.close()
	_write("acceptance.json", acceptance)

func _suspend(world: Expedition) -> void:
	recording=false
	app.open_pause_menu()
	await _hold(2)
	var captured: Dictionary=SortieSnapshot.capture(world)
	_write("checkpoint.json",{"fingerprint":RecordEncoding.fingerprint(captured),"pid":OS.get_process_id(),"legacy":false})
	FreezeProfile.start({"phase":"suspend-gui","buildings":world.layout.world_data.entities.size(),"objects":world.layout.world_data.objects.size(),"sites":world.sites.size(),"journal_generations":app.progress_session._transaction.recover().receipt.revision})
	var started: int=Time.get_ticks_usec()
	app.suspend_sortie()
	acceptance.suspend_gui_sync_usec=Time.get_ticks_usec()-started
	FreezeProfile.finish()
	_write("suspend-profile.json",FreezeProfile.latest)
	await _hold(3)
	_check(app.expedition==null and app._requires_continue,"original suspend obtains durable ACK before title")
	var durable: Dictionary=app.progress_session._transaction.recover().receipt
	var exact: FileAccess=FileAccess.open(output.path_join("oracle.json"),FileAccess.WRITE)
	exact.store_string(RecordEncoding.stringify({"world":captured,"receipt":durable,"camp":app.camp_snapshot()}))
	exact.close()
	_write("acceptance.json",acceptance)
