extends "res://tests/persona_flow.gd"
## Isolated normal journey; only GUI input and original world intentions.
var follow_actor: bool=false
var segment_frames: int=0
var segment_limit: int=1260
var acceptance: Dictionary={}
var old_mode: bool=false

func _frame() -> void:
	if follow_actor and recording and is_instance_valid(app) and is_instance_valid(app.expedition):
		var world: Expedition=app.expedition
		world.camera.pan_by(world.survivors[0].position-world.camera.position)
	if recording:
		segment_frames+=1
		if segment_frames>segment_limit: recording=false
	await super._frame()

func _menu(_count: int=0) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible,"normal bus opens frozen exploration candidates")
	for value: Dictionary in app.mission_select.daily_offers:
		_check(DailyActions.problem(value).is_empty(),"full frozen candidate authenticates")

func _journey() -> void:
	FreezeProfile.enabled=true
	old_mode="--flow-legacy-exploration" in OS.get_cmdline_user_args()
	await _tap(app._home_button);await _tap(app._new_game_confirmation.get_ok_button())
	_check(ExplorationState.enabled(app.camp_snapshot())!=old_mode,"normal new root chooses explicit exploration capability")
	await _menu()
	var slot: int=0
	var requested: String="medium"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--flow-size="): requested=arg.trim_prefix("--flow-size=")
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].layout["size"]==requested:slot=i
	var started: int=Time.get_ticks_msec()
	var world: Expedition=await _start(slot)
	if world==null:return
	acceptance.initialization_ms=Time.get_ticks_msec()-started
	_check(world.setup_problem.is_empty() and world.exploration_mode()!=old_mode,"normal actual world creates intended mode")
	if old_mode:
		world.request_search(&"cash")
		for site: Expedition.SearchSite in world.sites:
			if site.id!=&"cash":world.request_search(site.id);break
		await _until(world,func()->bool:return world.elapsed>=8)
		await _suspend(world)
		return
	var generated: Dictionary=world.supply.generated
	acceptance.geometry={"size":generated.layout["size"],"bounds":generated.layout.bounds,"buildings":generated.layout.entities.size(),"routes":generated.exploration.metrics,"base_speed":125.0}
	_check(generated.layout["size"]==requested,"normal menu selects actual requested physical scale")
	if requested!="medium":
		var p: Vector2=TaskActions.site_point(generated,generated.sites[-1])
		world.command_move(p)
		await _until(world,func()->bool:return world.survivors[0].position.distance_to(world.layout.bus_door)>100)
		world.locate_objective("primary")
		await _shot("scale-"+requested)
		_write("acceptance.json",acceptance)
		return
	if capture_caption!=null:capture_caption.text="中型正常行动 · 自动输入 · 本片段1× · 非物理输入"
	recording=true
	await _hold(90)
	await _shot("objectives")
	var commands: Array=[]
	for actor: FieldActor in world.survivors:commands.append([actor.position,actor.path])
	var goal_before: Vector2=world.goal
	var jobs: Dictionary=world.search_assignments.snapshot().duplicate(true)
	await _tap(world._hud.view._exploration_objectives.locate_buttons[0])
	var after: Array=[]
	for actor: FieldActor in world.survivors:after.append([actor.position,actor.path])
	# Input itself advances the ordinary simulation; locating has no order/job side effect.
	_check(TransactionReceipt.same(world.search_assignments.snapshot(),jobs) and world.goal==goal_before,"objective GUI locate leaves jobs and team commands unchanged")
	var car: Expedition.SearchSite
	for definition: Dictionary in generated.sites:
		if definition.source=="vehicle" and generated.exploration.metrics.routes[definition.id].zone!="near":car=world.search_site(StringName(definition.id));break
	_check(car!=null,"medium action has non-near real vehicle")
	if car==null:return
	var origin_elapsed: float=world.elapsed
	var origin_position: Vector2=world.survivors[0].position
	world.command_move(car.door)
	follow_actor=true
	for tick: int in range(600):world.step(1.0/30.0);await _frame()
	follow_actor=false
	acceptance.actual_move={"simulation_seconds":world.elapsed-origin_elapsed,"displacement":world.survivors[0].position.distance_to(origin_position),"target_site":String(car.id),"route":generated.exploration.metrics.routes[String(car.id)]}
	recording=false
	world.camera.pan_by(world.survivors[0].position-world.camera.position)
	world._clicked_site(car.prop.position+Vector2(0,-40))
	_check(world.search_assignments.member_for(String(car.id))>0,"visible car center selects the car ahead of overlapping building hit")
	var other: Expedition.SearchSite=_closest(world,car.door,"optional_building")
	world.request_search(other.id)
	await _until(world,func()->bool:return car.progress>=2.0)
	world.camera.pan_by(car.prop.position-world.camera.position)
	segment_frames=0;segment_limit=300;recording=true
	var other_job: Dictionary=world.search_assignments.snapshot().duplicate(true)
	var before: float=car.progress
	var other_id: int=world.search_assignments.member_for(String(other.id))
	world.request_search(car.id)
	_check(car.progress==before and world.search_assignments.member_for(String(other.id))==other_id,"cancel preserves car progress and the other worker")
	world.request_search(car.id)
	await _until(world,func()->bool:return car.searched)
	_check(world.search_member(other_id)!=null and not car.prop.visible==false,"outdoor car remains visible during original work")
	await _shot("parallel-car")
	await _hold(maxi(0,300-segment_frames))
	recording=false
	await _until(world,func()->bool:return other.searched)
	var tree: Expedition.SearchSite=_closest(world,car.door,"fruit_tree")
	world.request_search(tree.id)
	await _until(world,func()->bool:return tree.progress>0)
	world.camera.pan_by(tree.door-Vector2(0,240)-world.camera.position)
	segment_frames=0;segment_limit=300;recording=true
	await _until(world,func()->bool:return tree.searched)
	await _hold(maxi(0,300-segment_frames))
	recording=false
	world.camera.pan_by(tree.door-Vector2(0,240)-world.camera.position)
	await _shot("harvested-tree")
	_check(world.loot>=1 and world.food_loot>=1 and world.weapon_loot.is_empty(),"actual optional car/tree carry exactly their resources without primary weapon")
	_check(TaskActions.outcome(generated,{"site_facts":WorldSites.facts(world),"field_joins":[],"member_results":[],"weapons":[],"evacuated":true}).status=="EARLY","optional resources do not claim the primary objective")
	for site: Expedition.SearchSite in world.sites:
		if not site.searched and world.search_assignments.ordered().size()<2:world.request_search(site.id)
	await _until(world,func()->bool:return world.search_assignments.ordered().any(func(job:Dictionary)->bool:return job.phase=="working" and world.search_site(StringName(job.site_id)).progress>0.3))
	_check(world.search_assignments.ordered().size()==2,"checkpoint owns two independent ongoing jobs")
	_check(world.search_assignments.ordered().any(func(job:Dictionary)->bool:return job.phase=="working"),"checkpoint includes actual ongoing work in addition to the second live job")
	acceptance.completed_car=String(car.id);acceptance.completed_tree=String(tree.id)
	acceptance.completed_facts=WorldSites.facts(world)
	await _suspend(world)

func _closest(world: Expedition, point: Vector2, source: String) -> Expedition.SearchSite:
	var result: Expedition.SearchSite
	var distance: float=INF
	for definition: Dictionary in world.supply.generated.sites:
		if definition.source==source:
			var site: Expedition.SearchSite=world.search_site(StringName(definition.id))
			var path: PackedVector2Array=world.navigation.path_between(point,site.door)
			var length: float=ExplorationLayout._length(path)
			if not site.searched and not path.is_empty() and length<distance:result=site;distance=length
	return result

func _suspend(world: Expedition) -> void:
	recording=false
	app.open_pause_menu();await _hold(2)
	var captured: Dictionary=SortieSnapshot.capture(world)
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	var preview: Dictionary=app.progress_session.preview_suspend(captured)
	var issue: String=preview.get("reason","") if preview.error!=OK else ""
	_check(captured.version==(14 if old_mode else 15) and issue.is_empty(),"strict explicit world validates before suspend: "+issue)
	_write("checkpoint.json",{"fingerprint":RecordEncoding.fingerprint(captured),"pid":OS.get_process_id(),"legacy":old_mode})
	var started: int=Time.get_ticks_msec()
	app.suspend_sortie();await _hold(3)
	acceptance.suspend_ms=Time.get_ticks_msec()-started
	_check(app.expedition==null and app._requires_continue,"original durable suspend ACK completes")
	var durable: Dictionary=app.progress_session._transaction.recover().receipt
	var file: FileAccess=FileAccess.open(output.path_join("oracle.json"),FileAccess.WRITE)
	file.store_string(RecordEncoding.stringify({"world":captured,"receipt":durable,"camp":app.camp_snapshot()}));file.close()
	_write("acceptance.json",acceptance)

func _resume() -> void:
	FreezeProfile.enabled=true
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	old_mode=prior.legacy
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition=app.expedition
	_check(world!=null,"new PID normal Continue restores world: "+app._progress_message)
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	_check(prior.pid!=OS.get_process_id() and RecordEncoding.fingerprint(SortieSnapshot.capture(world))==prior.fingerprint,"new PID restores exact immutable geometry facts jobs traits clocks carry and enemies")
	if old_mode:
		_check(world.supply.generated.version==8 and world.supply.generated.layout.version==3,"old14 remains original geometry and rules")
		_write("acceptance.json",{"legacy":true,"restored":true})
		return
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:world.toggle_pause()
	var original: Dictionary=world.support_world()
	var job: Dictionary=world.search_assignments.ordered()[0]
	world.request_search(StringName(job.site_id))
	var caller: FieldActor=world.survivors.filter(func(a:FieldActor)->bool:return a.visible and a.health>0)[0]
	var target: Vector2=Vector2.INF
	for offset: Vector2 in [Vector2(0,40),Vector2(40,0),Vector2(-40,0),Vector2(0,-40)]:
		if not world.support_plan_airstrike(caller.position+offset).is_empty():target=caller.position+offset;break
	var parameters: Array=_parameters(world)
	var before: Dictionary=world.support_world()
	_check(target.is_finite() and world.request_airstrike(target),"original airstrike commits a full-world replacement")
	_check(TransactionReceipt.same(world.support_world().sites,before.sites) and world.loot==int(before.sim.loot) and world.food_loot==int(before.sim.food_loot) and TransactionReceipt.same(world.search_assignments.snapshot(),before.jobs),"support replacement retains exact sites carry and remaining jobs")
	_check(_parameters(world)==parameters and TransactionReceipt.same(world.powers,before.powers),"support reconstruction never stacks personal move damage reload or refills power state")
	segment_frames=0;segment_limit=240;recording=true
	if capture_caption!=null:capture_caption.text="新PID恢复 · 原支援世界重建 · 自动输入 · 1×"
	await _hold(240)
	await _shot("restored-world")
	recording=false
	for live: Dictionary in world.search_assignments.ordered():world.request_search(StringName(live.site_id))
	var carried: Dictionary={"cash":world.loot,"food":world.food_loot}
	world.command_move(world.layout.bus_door)
	var started: int=Time.get_ticks_msec()
	await _bank(world)
	acceptance.evacuation_and_settlement_ms=Time.get_ticks_msec()-started
	_check(not app._progress_blocked and app.camp_snapshot().journey.campaign.preparations==1,"partial optional completion returns through one original confirmation")
	var saved: Dictionary=app.camp_snapshot()
	app.return_to_title()
	_check(TransactionReceipt.same(saved,app.camp_snapshot()),"duplicate confirmation cannot bank carry twice")
	acceptance.carried=carried;acceptance.camp=saved
	_write("acceptance.json",acceptance)

func _bank(world: Expedition) -> void:
	await _extract(world)
	_write("freeze-profile.json",FreezeProfile.latest)
	_check(not app._progress_blocked,"original frozen extraction accepts partial exploration: "+app._progress_message)
	var started: int=Time.get_ticks_msec()
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	acceptance.confirmation_ms=Time.get_ticks_msec()-started
	_check(not app._progress_blocked and BuildState.problem(app.camp_snapshot()).is_empty(),"original confirmation durably banks immutable exploration source")

func _parameters(world: Expedition) -> Array:
	var values: Array=[]
	for actor: FieldActor in world.survivors:values.append([actor.member_id,actor.speed,actor.weapon_definition.damage,actor.magazine.reload_factor if actor.magazine!=null else 0.0])
	return values
