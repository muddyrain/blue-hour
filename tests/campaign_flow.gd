extends "res://tests/playable_flow.gd"
## Fresh normal short journey; only UI controls and the original world intentions.
var reports: Array[Dictionary]=[]
var _before: Dictionary={}

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked,"normal new journey durably enters camp")
	_check(app.camp_snapshot().journey.campaign.preparations==0 and app.day==2,"new short run starts at zero preparations independently of day")
	await _tap(app.camp_scene.hotspots[&"training"])
	await _tap(app.training_panel.member_buttons[1])
	await _tap(app.training_panel.train_button)
	await _tap(app.training_panel.confirmation.get_ok_button())
	await _tap(app.training_panel.back_button)
	for count: int in range(4):
		await _menu(count)
		if count in [0,2]: await _shot("phase-%d"%count)
		var original: Array=app.mission_select.daily_offers.duplicate(true)
		await _tap(app.mission_select.cancel_button)
		await _menu(count)
		_check(TransactionReceipt.same({"v":original},{"v":app.mission_select.daily_offers}),"browsing cannot reroll phase or real candidates")
		var best: int=0
		for index: int in range(app.mission_select.daily_offers.size()):
			if app.mission_select.daily_offers[index].food>app.mission_select.daily_offers[best].food: best=index
		var world: Expedition=await _start(best)
		if world==null:return
		_check(is_equal_approx(world.tuning.spawn_seconds,7.0*(0.9 if count>=2 else 1.0)),"phase pressure multiplies original base interval exactly once")
		# First action exercises actual early extraction; later actions collect real supplies.
		if count!=1:
			for site: Expedition.SearchSite in world.sites:
				if site.kind==&"food" or (site.id==&"cash" and count==0):
					world.request_search(site.id)
					await _until(world,func()->bool:return site.searched)
		await _extract(world)
		_check(app._pending_settlement.get("journey",{}).get("campaign",{}).get("preparations")==count+1,"frozen preview contains one proposed preparation")
		_check(app.camp_snapshot().journey.campaign.preparations==count,"preview has not committed preparation count")
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(not app._progress_blocked and app.camp_snapshot().journey.campaign.preparations==count+1,"explicit confirmation commits one preparation")
		var saved: Dictionary=app.camp_snapshot()
		app.return_to_title()
		_check(TransactionReceipt.same(saved,app.camp_snapshot()),"duplicate confirmation cannot advance or reward twice")
	await _menu(4)
	_check(app.mission_select.daily_offers.size()==1 and app.mission_select.daily_offers[0].campaign.is_finale,"four confirmed preparations expose only fixed finale")
	var world: Expedition=await _start(0)
	if world==null:return
	_check(world.encounter!=null and world.encounter.actor!=null,"normal finale creates authoritative reachable boss")
	_write("pre-finale.json",{"camp":_before,"descriptor":world.supply.generated})
	# Approach through normal navigation. No actor positions, health or inventory edits.
	world.command_move(world.encounter.actor.position+Vector2(90,50))
	await _until(world,func()->bool:return world.encounter.behavior.snapshot().state=="slam_windup",12000)
	_check(world.encounter.health()>0 and world.encounter.behavior.snapshot().state=="slam_windup","real legal combat reaches boss ground warning")
	app.open_pause_menu();await _hold(2)
	var captured: Dictionary=SortieSnapshot.capture(world)
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	var issue: String=SortieSnapshot.problem(captured,receipt)
	_check(issue.is_empty(),"new campaign world validates before suspend: "+issue)
	_write("checkpoint.json",{"encoded":RecordEncoding.stringify(captured),"fingerprint":RecordEncoding.fingerprint(captured),"pid":OS.get_process_id(),"reports":reports})
	app.suspend_sortie();await _hold(3)
	_check(app.expedition==null and app._requires_continue,"boss windup saved through original suspend ACK")

func _resume() -> void:
	if capture_caption!=null:capture_caption.text="自动输入 · 首领战与归航 1× · 非物理输入/显示器FPS"
	var phase_name: String=output.get_file()
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	if phase_name in ["readback","defeat-readback","new-journey"]:
		var outcome: String="DEFEAT" if phase_name=="defeat-readback" else "VICTORY"
		_check(CampaignState.ended(app.camp_snapshot()) and app.camp_snapshot().journey.campaign.outcome==outcome,"new process reads durable "+outcome)
		_check(app.progress_session.inspect().state=="ENDED","one authoritative end state survives process restart")
		app.open_mission_select();app.open_expedition()
		_check(app.expedition==null and not app.mission_select.visible,"ended journey cannot start another action")
		await _shot("confirmed-"+outcome.to_lower())
		if phase_name=="new-journey":
			var old:Dictionary=app.camp_snapshot()
			await _tap(app._battle_new_button)
			_check(app._new_game_confirmation.visible,"explicit new journey confirmation is available after ending")
			await _tap(app._new_game_confirmation.get_ok_button())
			var fresh:Dictionary=app.camp_snapshot()
			_check(fresh.profile_id!=old.profile_id and fresh.journey.seed!=old.journey.seed and fresh.journey.campaign.preparations==0,"new journey creates fresh identity and zero preparations")
			_check(Array(DirAccess.get_files_at(app.progress_path.get_base_dir())).any(func(name:String)->bool:return name.begins_with(app.progress_path.get_file()+".previous-")),"original ended journey remains archived")
		return
	var source: String="fight" if phase_name in ["victory","wipe"] else "first"
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(source+"/checkpoint.json")))
	_check(expected.pid!=OS.get_process_id(),"boss checkpoint resumes in different process")
	var world: Expedition=app.expedition
	_check(world!=null,"original boss world reconstructs through normal continue")
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	var actual: Dictionary=SortieSnapshot.capture(world)
	_check(RecordEncoding.fingerprint(actual)==expected.fingerprint,"boss identity HP windup point timers summons map actors and partial magazines restore exactly")
	_write("restored.json",{"actual":actual,"expected":RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload})
	await _world_negatives(world,actual)
	world.combat_feedback.connect(func(event:Dictionary)->void:events.append(event.duplicate(true)))
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:world.toggle_pause()
	if phase_name=="early":
		world.command_move(world.layout.bus_door)
		await _extract(world)
		_check(app._pending_settlement.journey.campaign.outcome=="ACTIVE" and app._pending_settlement.journey.campaign.preparations==4,"undefeated boss extraction is not victory or another preparation")
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(app.camp_snapshot().journey.campaign.outcome=="ACTIVE" and app.camp_snapshot().last_day.food_consumed>0,"early finale still pays original ration settlement")
		await _menu(4)
		var retry_world:Expedition=await _start(0)
		_check(retry_world.encounter.health()==BossDefinition.POLICY.health and retry_world.encounter.definition.boss_id!=actual.encounter.boss_id,"retry is a newly bound battlefield and fresh boss")
		return
	if phase_name in ["fight","stationary"]:
		await _fight(world,phase_name!="stationary")
		_check(not world.encounter.defeat.is_empty() and world.encounter.health()==0,"boss defeated by real weapons and original fatal-shot receipt")
		_check(world.living_count()>0,"at least one real survivor remains after boss fight")
		if phase_name=="stationary":
			_write("balance.json",{"events":events,"elapsed":world.elapsed,"health":world.survivors.map(func(member:FieldActor)->float:return member.health),"defeat":world.encounter.defeat})
			return
		await _shot("boss-defeated")
		app.open_pause_menu();await _hold(2)
		var killed:Dictionary=SortieSnapshot.capture(world)
		var receipt:Dictionary=app.progress_session._transaction.recover().receipt
		var issue:String=SortieSnapshot.problem(killed,receipt)
		_check(issue.is_empty(),"actual summons and defeated boss validate before second suspend: "+issue)
		_write("checkpoint.json",{"encoded":RecordEncoding.stringify(killed),"fingerprint":RecordEncoding.fingerprint(killed),"pid":OS.get_process_id(),"events":events})
		app.suspend_sortie();await _hold(3)
		_check(app.expedition==null and app._requires_continue,"real defeated-boss proof is durably suspended without winning")
		return
	if phase_name=="wipe":
		# Negative damage-owner fixture: suppress survivor firing only. No HP/death injection.
		for member:FieldActor in world.survivors:member.cooldown=1000000.0
		await _until(world,func()->bool:return world.phase==Expedition.Phase.FINISHED,18000)
		_check(world.living_count()==0 and app.camp_snapshot().journey.campaign.outcome=="DEFEAT","boss dead plus original enemy full wipe stays durable defeat")
		_check(app.progress_session.inspect().state=="ENDED","original all-wipe automatic failure commit remains authoritative")
		return
	_check(not world.encounter.defeat.is_empty(),"second process retains exact real boss defeat proof")
	await _extract(world)
	_check(app._pending_settlement.get("journey",{}).get("campaign",{}).get("outcome")=="VICTORY","legitimate boss defeat plus bus extraction creates victory preview")
	_check(app.camp_snapshot().journey.campaign.outcome=="ACTIVE","preview is not permanent victory")
	app.progress_session.fault_hook=func(point_name:String)->Error:return ERR_CANT_CREATE if point_name=="before_commit_receipt" else OK
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app._progress_blocked and not app._pending_settlement.is_empty() and app.camp_snapshot().journey.campaign.outcome=="ACTIVE","failed victory save retains frozen result and cannot claim victory")
	_check(app._battle_new_button.disabled,"failed victory save cannot start a fresh journey")
	app.open_mission_select();app.open_expedition()
	_check(app.expedition==world and not app.mission_select.visible,"unconfirmed victory cannot open another action")
	app.progress_session.fault_hook=Callable()
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app.camp_snapshot().journey.campaign.outcome=="VICTORY" and not app._progress_blocked,"same frozen confirmation retry durably wins")
	_check("旅程胜利" in app.get_node("Interface/Screen/Result/Heading").text,"confirmed victory visible only after successful save")
	await _shot("confirmed-victory")
	var saved: Dictionary=app.camp_snapshot()
	app.return_to_title()
	_check(TransactionReceipt.same(saved,app.camp_snapshot()) and app.settled_sorties==5,"duplicate confirmation keeps exact resources XP preparations and five actions")
	_write("journey-results.json",{"fight_events":expected.events,"final_events":events,"camp":saved})

func _fight(world:Expedition, mobile:bool) -> void:
	var last_sequence:int=-1
	for index:int in range(12000):
		if not world.encounter.defeat.is_empty() or world.phase==Expedition.Phase.FINISHED or world.is_paused:break
		var state:Dictionary=world.encounter.behavior.snapshot()
		if mobile and state.state in ["slam_windup","melee_windup"] and int(state.sequence)!=last_sequence:
			last_sequence=int(state.sequence)
			var locked:Vector2=SortieSnapshot._vec(state.point)
			var candidates:Array[Vector2]=[]
			for offset:Vector2 in [Vector2(150,0),Vector2(-150,0),Vector2(0,150),Vector2(0,-150),Vector2(110,110),Vector2(-110,-110)]:
				var target:Vector2=world.encounter.actor.position+offset
				if target.distance_to(locked)>110 and world.navigation.is_clear(target) and not world.navigation.path_between(world.survivors[0].position,target).is_empty():candidates.append(target)
			if not candidates.is_empty():
				candidates.sort_custom(func(a:Vector2,b:Vector2)->bool:return a.distance_to(world.survivors[0].position)<b.distance_to(world.survivors[0].position))
				world.command_move(candidates[0])
		if index==0:await _shot("boss-warning")
		world.step(1.0/30.0)
		if movie!=null or index%30==0:await _frame()
	_check(not world.encounter.defeat.is_empty(),"bounded original combat defeats boss" if mobile else "stationary comparison reaches outcome")

func _world_negatives(world:Expedition, snapshot:Dictionary) -> void:
	var receipt:Dictionary=app.progress_session._transaction.recover().receipt
	_check(SortieSnapshot.problem(snapshot,receipt).is_empty(),"warm authoritative snapshot valid")
	for kind:String in ["identity","timer","life","behavior","xp","magazine","defeat"]:
		var bad:Dictionary=snapshot.duplicate(true)
		match kind:
			"identity":bad.encounter.boss_id+="-foreign"
			"timer":bad.encounter.behavior.remaining=99.0
			"life":bad.encounter.health=BossDefinition.POLICY.health+1
			"behavior":bad.encounter.behavior=[]
			"xp":bad.xp_inputs=[]
			"magazine":bad.survivors[0].magazine.rounds=999
			"defeat":bad.encounter.defeat={"defeated":true}
		_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"warm snapshot rejects forged "+kind)
		_check(app.progress_session.preview_suspend(bad).error!=OK,"original suspend preview rejects rehashed changed "+kind)
	_check(world.encounter.behavior.snapshot()==snapshot.encounter.behavior,"negative checks do not mutate authoritative behavior")
	if snapshot.encounter.health>0:
		# Read-only combatant fixture. It never replaces a real actor or produces damage.
		var gate:FieldActor=FieldActor.new()
		var legal_member:FieldActor=world.survivors.filter(func(member:FieldActor)->bool:return world.encounter.legal(member,BossDefinition.POLICY.slam_range))[0]
		gate.position=legal_member.position;gate.health=1;gate.visible=true
		gate.activity=FieldActor.Activity.RECOVERING
		_check(world.encounter.legal(gate,BossDefinition.POLICY.slam_range),"boss gate permits a visible outdoor recovery combatant")
		gate.activity=FieldActor.Activity.SEARCHING;gate.visible=false
		_check(not world.encounter.legal(gate,BossDefinition.POLICY.slam_range),"same boss gate protects a hidden indoor worker")
		gate.free()

func _shot(label:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _hold(2);RenderingServer.force_draw()
	viewport.get_texture().get_image().save_png(output.path_join(label+".png"))

func _menu(count: int) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible,"normal bus opens actual cards")
	var offers: Array=app.mission_select.daily_offers
	_check(offers.size()==(1 if count==4 else 3),"legal task count for current phase")
	for value:Dictionary in offers:_check(value.version==6 and value.campaign.preparations==count,"descriptor freezes confirmed preparation count")

func _start(slot: int) -> Expedition:
	_before=app.camp_snapshot()
	await _tap(app.mission_select.choices[slot])
	var world: Expedition=app.expedition
	_check(world!=null and not app._progress_blocked,"selected signed action enters existing world")
	if world!=null:
		world.set_physics_process(false);world.set_process(false)
		await _until(world,func()->bool:return not world.bus_view.running())
		world.finished.connect(func(report:Dictionary)->void:reports.append(report.duplicate(true)))
		world.combat_feedback.connect(func(event:Dictionary)->void:events.append(event.duplicate(true)))
	return world

func _until(world: Expedition, done: Callable, limit: int=12000) -> void:
	for index:int in range(limit):
		if done.call() or world.phase==Expedition.Phase.FINISHED or world.is_paused:break
		world.step(1.0/30.0)
		if movie!=null or index%30==0:await _frame()
	_check(done.call(),"bounded real simulation reaches checkpoint")
	if not done.call():
		_write("checkpoint-failure-%d.json"%rows.size(),{"elapsed":world.elapsed,"phase":world.phase,"paused":world.is_paused,"camp":app.camp_snapshot(),"encounter":world.encounter.snapshot() if world.encounter!=null else {}})
		quit(1);await process_frame

func _extract(world: Expedition) -> void:
	await _until(world,func()->bool:return world.elapsed>=world.tuning.bus_ready_seconds)
	world.request_bus_action()
	await _until(world,func()->bool:return world.phase==Expedition.Phase.BOARDING)
	world.request_bus_gather()
	await _until(world,func()->bool:return world.phase==Expedition.Phase.FINISHED)
	_check(app.phase==app.Phase.RESULT and world.boarding_status().arrived==world.living_count(),"original bus gathers actual living actors before result")
	for index:int in range(300):
		if not world.bus_view.running():break
		world.step(1.0/30.0)
		if movie!=null:await _frame()
	await _hold(3)
