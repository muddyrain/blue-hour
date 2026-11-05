extends "res://tests/campaign_flow.gd"
var recording: bool=false
## WIN-R1 real owners; fixed seed controls candidates, never HP/inventory/outcome.
func _menu(count: int) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible,"normal bus opens build candidates")
	for value: Dictionary in app.mission_select.daily_offers: _check(value.version==7 and value.campaign.preparations==count,"V7 binds departure mode and preparation")

func _journey() -> void:
	if capture_caption!=null: capture_caption.text="自动输入 · 1×片段 · 接缝剪辑 · 非物理输入/FPS"
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked,"new build journey enters confirmed camp")
	_check(BuildState.enabled(app.camp_snapshot()) and app.camp_snapshot().journey.build.owned.is_empty(),"fresh inventory and two empty slots")
	var gear_runs: int=0
	for count: int in range(4):
		await _menu(count)
		var offers: Array=app.mission_select.daily_offers.duplicate(true)
		if count==0:_check(offers.any(func(v:Dictionary)->bool:return v.type=="equipment"),"first action guarantees gear")
		await _tap(app.mission_select.cancel_button)
		await _menu(count)
		_check(TransactionReceipt.same({"v":offers},{"v":app.mission_select.daily_offers}),"cancel/browse retains drops")
		var best: int=0
		for index: int in range(offers.size()):
			if offers[index].food>offers[best].food: best=index
		if gear_runs<2:
			for index: int in range(offers.size()):
				if offers[index].type=="equipment": best=index; break
		var old: Dictionary=app.camp_snapshot()
		var world: Expedition=await _start(best)
		if world==null:return
		_check(world.basic_support.snapshot().cooldowns=={"heal":0.0,"airstrike":0.0},"new sortie starts support ready")
		_check(not world.request_heal() and world.basic_support.remaining("heal")==0,"full health refuses without cooldown")
		_check(not world.request_airstrike(Vector2(-100,-100)),"illegal strike refuses without cooldown")
		if world.supply.generated.type=="equipment":
			_check(app.camp_snapshot().journey.build.owned==old.journey.build.owned,"arrival grants no items")
			world.request_search(&"cash")
			await _until(world,func()->bool:return world.search_site(&"cash").progress>=25.0)
			if count==0: recording=true
			await _until(world,func()->bool:return world.search_site(&"cash").searched)
			_check(app.camp_snapshot().journey.build.owned==old.journey.build.owned,"real pickup remains carried until confirmation")
			gear_runs+=1
			await _shot("recovered-%d"%count)
			if count==0: await _hold(60)
			recording=false
		for site: Expedition.SearchSite in world.sites:
			if site.kind==&"food":
				world.request_search(site.id)
				await _until(world,func()->bool:return site.searched)
		await _extract(world)
		_check(not app._progress_blocked,"real extraction produces authenticated preview: "+app._progress_message)
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(not app._progress_blocked and app.camp_snapshot().journey.campaign.preparations==count+1,"one return confirmation banks resources and phase")
		var camp: Dictionary=app.camp_snapshot()
		_check(BuildState.problem(camp).is_empty(),"banked item sources validate")
		if not camp.journey.build.owned.is_empty():
			app.open_loadout()
			app.equip_build_item(0,camp.journey.build.owned[0])
			if camp.journey.build.owned.size()>1: app.equip_build_item(1,camp.journey.build.owned[1])
			if camp.journey.build.owned.size()>=3:
				recording=true
				await _hold(75)
				app.equip_build_item(0,camp.journey.build.owned[2])
				await _hold(75)
				_check(app.camp_snapshot().journey.build.slots[0]==camp.journey.build.owned[2],"three-plus actual inventory allows replacement")
			await _shot("inventory-%d"%count)
			app.close_loadout()
			recording=false
	_check(gear_runs>=2 and app.camp_snapshot().journey.build.owned.size()>=3,"two actual gear returns obtain at least three")
	await _menu(4)
	var world: Expedition=await _start(0)
	if world==null:return
	recording=true
	world.command_move(world.encounter.actor.position+Vector2(90,50))
	await _until(world,func()->bool:return world.survivors.any(func(a:FieldActor)->bool:return a.health>0 and a.damage_received>0))
	var health_before: Array=[]
	for actor: FieldActor in world.survivors: health_before.append(actor.health)
	app.progress_session.fault_hook=func(point:String)->Error:return ERR_CANT_CREATE if point=="after_record_flush" else OK
	_check(not world.request_heal(),"failed support publication does not apply healing")
	for index: int in range(world.survivors.size()): _check(world.survivors[index].health==health_before[index],"failed publication preserves exact HP")
	_check(world.basic_support.remaining("heal")==0.0 and world.is_paused,"failure keeps cooldown and recoverable paused intent")
	app.progress_session.fault_hook=Callable()
	world.toggle_pause()
	_check(not world.is_paused and world.basic_support.snapshot().accepted.size()==1,"same request retry durably accepts once")
	_check(world.basic_support.remaining("heal")==30.0,"accepted healing consumes independent cooldown")
	_check(not world.request_heal(),"repeat healing cannot apply twice")
	await _shot("support-healed")
	await _hold(45)
	await _until(world,func()->bool:return world.survivors.any(func(a:FieldActor)->bool:return a.health>0 and a.damage_received>BuildAuthority.healed(world.basic_support.snapshot().accepted,a.member_id)))
	recording=false
	world.toggle_pause()
	var snapshot: Dictionary=SortieSnapshot.capture(world)
	_build_negatives(world,snapshot)
	_check(app.progress_session.preview_suspend(snapshot).error==OK,"healed then damaged world remains suspendable")
	_write("checkpoint.json",{"encoded":RecordEncoding.stringify(snapshot),"fingerprint":RecordEncoding.fingerprint(snapshot),"pid":OS.get_process_id()})
	app.open_pause_menu()
	app.suspend_sortie()
	await _hold(3)
	_check(app.expedition==null and app._requires_continue,"original suspend publishes exact support world")

func _resume() -> void:
	if capture_caption!=null: capture_caption.text="自动输入 · 1×片段 · 接缝剪辑 · 非物理输入/FPS"
	var phase_name: String=output.get_file()
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	if phase_name=="readback":
		_check(app.camp_snapshot().journey.campaign.outcome=="VICTORY","new PID reads confirmed victory")
		recording=true
		await _shot("confirmed-victory")
		await _hold(120)
		recording=false
		return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	var world: Expedition=app.expedition
	_check(world!=null,"new PID reconstructs healed active sortie: "+app._progress_message)
	if world==null:return
	world.set_physics_process(false)
	world.set_process(false)
	_check(RecordEncoding.fingerprint(SortieSnapshot.capture(world))==expected.fingerprint and expected.pid!=OS.get_process_id(),"new PID exact HP/healing/cooldown/magazine/boss restore")
	recording=true
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused: world.toggle_pause()
	_build_negatives(world,world.support_world())
	var strike: bool=false
	for index: int in range(12000):
		if not world.encounter.defeat.is_empty() or world.phase==Expedition.Phase.FINISHED:break
		_frame_boss(world)
		if world.encounter.health()<=72 and world.basic_support.ready("airstrike"):
			strike=world.request_airstrike(world.encounter.actor.position)
			if strike: break
		world.step(1.0/30.0)
		if movie!=null or index%30==0: await _frame()
	_check(strike and BuildAuthority.ability(world.encounter.defeat),"real airstrike lethal owns exact boss proof")
	await _shot("support-airstrike")
	await _extract(world)
	_check(not app._progress_blocked,"ability defeat and healing enter original settlement: "+app._progress_message)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app.camp_snapshot().journey.campaign.outcome=="VICTORY" and not app._progress_blocked,"explicit return confirms durable build victory")
	await _shot("confirmed-victory")

func _build_negatives(world: Expedition, before: Dictionary) -> void:
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	var original: Dictionary=receipt.duplicate(true)
	for row: Dictionary in before.survivors: SurvivorRoster.member(original.health,int(row.state.member_id)).health=row.state.health
	_check(SortieSnapshot.problem(before,original).is_empty(),"build snapshot validates complete current inputs")
	var bad: Dictionary=before.duplicate(true)
	bad.support.cooldowns.heal=0.0
	_check(not SortieSnapshot.problem(bad,original).is_empty(),"zeroing nonzero heal cooldown rejects even with rehash")
	bad=before.duplicate(true)
	bad.generated.build.owned=[]
	_check(not SortieSnapshot.problem(bad,original).is_empty(),"current inventory cannot rewrite frozen departure proof")
	_check(BuildAuthority.propose(before,{"id":"bad","kind":"heal","payload":[]}).is_empty(),"malformed typed payload rejected without mutation")
	var plan: Dictionary=BuildAuthority.plan_airstrike(before,world.encounter.actor.position)
	if not plan.is_empty():
		var proposal: Dictionary=BuildAuthority.propose(before,world.basic_support.request("airstrike",plan))
		_check(not proposal.is_empty(),"nonlethal strike produces pure full proposal")
		if not proposal.is_empty():
			var next: Dictionary=original.duplicate(true)
			next.support=proposal.support.accepted.duplicate(true)
			for row: Dictionary in proposal.survivors: SurvivorRoster.member(next.health,int(row.state.member_id)).health=row.state.health
			var issue: String=SortieSnapshot.problem(proposal,next)
			_check(issue.is_empty(),"nonlethal boss strike preserves strict threshold and pending proofs: "+issue)
	_check(RecordEncoding.fingerprint(before)==RecordEncoding.fingerprint(SortieSnapshot.capture(world)) if world.is_paused else true,"negative/pure proposals never mutate world")

func _shot(label: String) -> void:
	if app.loadout_panel!=null and app.loadout_panel.visible and app.loadout_panel.build_panel.visible:
		for control: Control in app.loadout_panel.build_panel.slot_choices:
			_check(viewport.get_visible_rect().encloses(control.get_global_rect()),"saved item selector inside viewport")
	if app.expedition!=null and app.expedition.support_panel!=null:
		var panel: Control=app.expedition.support_panel
		_check(viewport.get_visible_rect().encloses(panel.get_global_rect()),"support buttons inside viewport")
		_check(panel.get_global_rect().position.y>=152.0,"support panel clear of top HUD")
	await super._shot(label)

func _frame() -> void:
	var encoder: StreamPeerTCP=movie
	if not recording: movie=null
	await super._frame()
	movie=encoder

func _until(world: Expedition, done: Callable, limit: int=12000) -> void:
	for index: int in range(limit):
		if done.call() or world.phase==Expedition.Phase.FINISHED or world.is_paused: break
		world.step(1.0/30.0)
		if (movie!=null and recording) or index%30==0: await _frame()
	_check(done.call(),"bounded real simulation reaches checkpoint")
	if not done.call(): quit(1); await process_frame
