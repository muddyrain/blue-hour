extends "res://tests/neighborhood_flow.gd"
## Default UI/business intents only; no completed-state, HP, reward or clock injection.
var scenario: String = "airdrop"
var task_freezes: Array = []
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--task-case="): scenario=arg.trim_prefix("--task-case=")
	root.unfocusable=true
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if label=="background renderer; Windows must use isolated desktop launcher":
		# An offscreen NSWindow can report key focus while its app is not foreground.
		# The external Mac launcher samples AppKit's actual frontmost process instead.
		var path: String = output.get_base_dir().path_join("foreground.json")
		var audit: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		value=audit is Dictionary and audit.samples>0 and not audit.pids.has(OS.get_process_id())
		label="AppKit foreground PID samples exclude renderer"
	super._check(value,label)

func _journey() -> void:
	await _tap(app._home_button); await _tap(app._new_game_confirmation.get_ok_button())
	var offers: Array[Dictionary] = await _menu()
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var original: String = WeaponInventory.for_member(app.camp_snapshot(),1).instance_id
	app.equip_weapon(1,WeaponInventory.for_member(app.camp_snapshot(),2).instance_id)
	app.equip_weapon(1,original); app.close_loadout()
	_check(TransactionReceipt.same({"v":offers},{"v":await _menu()}),"same-day equip and browse preserve candidates")
	await _start("rescue" if scenario.begins_with("rescue") else "supply" if scenario=="early" else scenario)
	var world: Expedition = app.expedition
	if world==null: return
	if scenario=="airdrop":
		world.request_search(&"cash")
		await _advance(world,func() -> bool:return world.search_site(&"cash").progress>=3)
		_check(world.task_event.started and world.task_event.resolutions.size()==2,"one bounded real airdrop pressure event")
		var progress: float = world.search_site(&"cash").progress
		var event: Dictionary = world.task_event.duplicate(true)
		world.request_search(&"cash") # Existing cancellation preserves site progress.
		world.request_search(&"cash")
		await _advance(world,func() -> bool:return world.search_site(&"cash").progress>progress+0.2)
		_check(TransactionReceipt.same(event,world.task_event),"cancel/retry cannot trigger another event")
		app.open_pause_menu(); await _hold(3)
		var exact: Dictionary = SortieSnapshot.capture(world)
		_write("world-exact.json",{"encoded":RecordEncoding.stringify(exact),"hash":SurvivalContracts.fingerprint(exact),"selected":_selected,"camp":_before,"event":event})
		await _shot("airdrop-partial")
		await _tap(app.pause_menu.buttons[4])
		_check(app.expedition==null and app._requires_continue,"original suspend ACK leaves no resources banked")
		var receipt: Dictionary = app.progress_session.inspect().receipt
		_check(SortieSnapshot.problem(exact,receipt).is_empty(),"selected task snapshot strictly authenticates")
		var bad: Dictionary = exact.duplicate(true); bad.task_event.extra=true
		_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"unknown event fact rejected after warm proof")
		bad=exact.duplicate(true); bad.task_event.started=false
		_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"working crate cannot retract trigger")
		bad=exact.duplicate(true); bad.generated.objective.site_ids=["foreign"]
		_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"foreign target cannot use cached proof")
		bad=exact.duplicate(true); bad.generated.cash+=1
		_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"changed budget cannot use cached proof")
		return
	await _complete_task(world)
	await _finish(world,scenario=="equipment")
	await _menu()
	if scenario=="rescue-roster4":
		await _start("rescue")
		await _complete_task(app.expedition)
		await _hud_sample(app.expedition)
		_check(app.expedition.survivors.size()==4,"second actual rescue creates four-person HUD")
		await _finish(app.expedition,false)
		await _menu()
	_write("daily-state.json",{"menu_history":menu_history,"selected":_selected,"reports":journey_reports})

func _resume() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/world-exact.json")))
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/report.json")))
	_check(int(prior.pid)!=OS.get_process_id(),"new PID resumes same airdrop")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_check(world!=null,"same suspended task reconstructed")
	if world==null: return
	world.set_process(false); world.set_physics_process(false)
	var actual: Dictionary = SortieSnapshot.capture(world)
	var exact: Dictionary = RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload
	_check(TransactionReceipt.same(actual,exact) and SurvivalContracts.fingerprint(actual)==expected.hash,"exact target/progress/event/enemies/carry/layout restored")
	_selected=expected.selected; _before=expected.camp
	world.finished.connect(func(report: Dictionary) -> void:journey_reports.append(report.duplicate(true)))
	await _shot("airdrop-restored")
	await _tap(app.pause_menu.buttons[0]); if world.is_paused: world.toggle_pause()
	await _advance(world,func() -> bool:return world.search_site(&"cash").searched)
	_check(TransactionReceipt.same(world.task_event,expected.event),"resume completes same crate without new pressure")
	_check(world.weapon_loot.size()==1 and world._searched_count()<world.sites.size(),"one weapon and actual partial task budget")
	await _finish(world,false)
	await _menu()
	_write("daily-state.json",{"menu_history":menu_history,"selected":_selected,"reports":journey_reports})

func _start(type: String) -> void:
	_before=app.camp_snapshot()
	var slot: int = -1
	for i: int in range(3):
		if app.mission_select.daily_offers[i].type==type: slot=i; _selected=app.mission_select.daily_offers[i].duplicate(true)
	_check(slot>=0,"requested legal task offered: "+type)
	if slot<0: return
	await _shot(type+"-cards")
	await _tap(app.mission_select.choices[slot])
	var world: Expedition = app.expedition
	_check(world!=null,"normal selection starts registered task")
	if world==null: return
	world.set_physics_process(false); world.set_process(false)
	await _advance(world,func() -> bool:return not world.bus_view.running())
	world.finished.connect(func(report: Dictionary) -> void:journey_reports.append(report.duplicate(true)))
	_check(world.elapsed==0 and app.progress_session._transaction.recover().receipt.rules.data_version==(6 if world.supply.generated.version==5 else 5),"arrival preserves clock and selected task policy")
	world.camera.set_process(false)
	await _hud_sample(world)

func _advance(world: Expedition, until: Callable, limit: int = 7200) -> void:
	for index: int in range(limit):
		if until.call(): return
		if world.phase==Expedition.Phase.FINISHED and not world.bus_view.running(): break
		var was: int = world.phase
		var start: int = Time.get_ticks_usec()
		world.step(1.0/30.0)
		if was!=Expedition.Phase.FINISHED and world.phase==Expedition.Phase.FINISHED:
			task_freezes.append({"step_usec":Time.get_ticks_usec()-start,"size":_selected.layout["size"],"survivors":world.survivors.size(),"enemies":world.enemies.size(),"buildings":world._buildings.size(),"elapsed":world.elapsed})
		if is_instance_valid(world.search_actor): world.camera.position=world.search_actor.position+Vector2(200,-120)
		elif world.survivors.size()>0: world.camera.position=world.survivors[0].position+Vector2(200,-120)
		world.camera._clamp_position(); world.camera.force_update_scroll()
		if index%6==0: await _frame()
	_check(until.call(),"bounded real task checkpoint")

func _complete_task(world: Expedition) -> void:
	if scenario.begins_with("rescue"):
		await _tap(world.rescue_target.button)
		await _advance(world,func() -> bool:return not world.field_joins.is_empty())
		_check(world.field_joins.size()==1 and TaskActions.hud(world).contains("归航"),"real rescue joins, objective switches to return")
		if scenario=="rescue-death":
			await _death_stance(world)
			_check(world.rescue_target.npc.permanent_death,"target death is permanent through original damage gate")
	elif scenario!="early":
		for id: String in _selected.objective.site_ids:
			world.request_search(StringName(id))
			await _advance(world,func() -> bool:return world.search_site(StringName(id)).searched)
	# Actual optional food keeps the original hunger policy; no extra task award.
	if scenario=="early" or scenario.begins_with("rescue"):
		var site: Expedition.SearchSite = world.search_site(&"cash")
		world.request_search(site.id); await _advance(world,func() -> bool:return site.searched)
	await _shot(scenario+"-objective")

func _finish(world: Expedition, fault: bool) -> void:
	await super._finish(world,fault)
	var task: Dictionary = app.camp_snapshot().last_day.get("task",{})
	_check(not task.is_empty(),"confirmed camp retains task outcome")
	if task.is_empty(): return
	_check(task.status==("EARLY" if scenario=="early" else "TARGET_LOST" if scenario=="rescue-death" else "COMPLETED"),"actual objective outcome: "+str(task))
	_check(TaskActions.summary_text(task) in app.camp_scene.eligibility_text.text,"camp shows objective separately from actual gain")
	_write("task-performance.json",{"freezes":task_freezes,"input":"normal viewport/business intentions; accelerated 6 ticks per render","display_fps":"NOT_MEASURED"})
	await _shot(scenario+"-camp")

func _death_stance(world: Expedition) -> void:
	# Reuse the existing designated AI death fixture: suppress only subject fire,
	# walk real paths outside bystander range; natural enemies and PersistedDamageGate own death.
	var target: FieldActor = world.rescue_target.npc
	var reach: float = 0
	for actor: FieldActor in world.survivors:
		if actor!=target: reach=maxf(reach,actor.weapon_definition.shot_range)
	var destination: Vector2 = Vector2.INF
	var nearest: float = INF
	var edge: Vector2 = world.layout.enemy_points[2]
	for x: int in range(104,int(world.layout.world_bounds.size.x)-104,64):
		for y: int in range(104,int(world.layout.world_bounds.size.y)-104,64):
			var point: Vector2 = Vector2(x,y)
			if point.distance_to(world.layout.bus_door)<reach+180 or not world.navigation.is_clear(point) or not world.navigation.is_clear(point+Vector2(36,0)): continue
			if world.navigation.path_between(target.position,point).is_empty(): continue
			if point.distance_squared_to(edge)<nearest: destination=point; nearest=point.distance_squared_to(edge)
	_check(destination.is_finite(),"legal isolated death stance")
	if not destination.is_finite(): return
	world.command_move(world.layout.bus_door)
	target.command_path(world.navigation.path_between(target.position,destination))
	target.cooldown=999.0
	await _advance(world,func() -> bool:return target.permanent_death,12000)
	_write("death-stance.json",{"member_id":target.member_id,"destination":[destination.x,destination.y],"health":target.health,"method":"existing fire-suppressed subject fixture; real path, natural enemies, original damage/death writer; no HP/damage/reward injection"})
