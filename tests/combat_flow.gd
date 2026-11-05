extends "res://tests/campaign_flow.gd"
## Isolated normal V1 journey. Only original UI, movement, search, support and settlement owners.
var recording: bool=false
var toxic_seen: bool=false
var acquired: Array[String]=[]

func _menu(count: int) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible,"normal bus opens combat candidates")
	for value: Dictionary in app.mission_select.daily_offers: _check(value.version==8 and value.campaign.preparations==count,"V8 frozen mode/preparation")

func _journey() -> void:
	if capture_caption!=null: capture_caption.text="自动输入 · 1×必要片段/接缝 · 非物理输入/FPS"
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(CombatActions.enabled(app.camp_snapshot()),"normal fresh journey enables combat V1")
	for count: int in range(4):
		await _menu(count)
		var offers: Array=app.mission_select.daily_offers.duplicate(true)
		var best: int=0
		for index: int in range(offers.size()):
			if offers[index].food>offers[best].food: best=index
		for index: int in range(offers.size()):
			if offers[index].type=="equipment":
				for site: Dictionary in offers[index].sites:
					if site.weapon and site.drop.weapon_id in ["fire_axe_v1","shotgun_v1"] and site.drop.weapon_id not in acquired: best=index
		await _tap(app.mission_select.cancel_button)
		await _menu(count)
		_check(TransactionReceipt.same({"v":offers},{"v":app.mission_select.daily_offers}),"browsing preserves frozen combat drops")
		var world: Expedition=await _start(best)
		if world==null:return
		for site: Expedition.SearchSite in world.sites:
			if site.kind==&"food" or site.id==&"cash":
				world.request_search(site.id)
				await _until(world,func()->bool:return site.searched)
		if count>=2 and not toxic_seen: await _toxic_demo(world)
		if count==3:
			_check("fire_axe_v1" in acquired and "shotgun_v1" in acquired,"both actual new weapons recovered, repaired and equipped")
			await _boundary(world)
			return
		if count==0: recording=true
		await _extract(world)
		recording=false
		_check(not app._progress_blocked,"real recovery/return preview: "+app._progress_message)
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(not app._progress_blocked and app.camp_snapshot().journey.campaign.preparations==count+1,"original confirmation advances once")
		_write("camp-state-%d.json"%count,{"app":app.camp_snapshot(),"disk":app.progress_session.inspect()})
		app.open_loadout()
		for item: Dictionary in app.camp_snapshot().weapons:
			if item.weapon_id not in ["fire_axe_v1","shotgun_v1"]: continue
			if item.weapon_id not in acquired: acquired.append(item.weapon_id)
			if item.condition=="damaged": app.repair_weapon(item.instance_id)
			app.equip_weapon(1 if item.weapon_id=="fire_axe_v1" else 2,item.instance_id)
		if count==1:
			recording=true
			await _shot("new-equipment")
			await _hold(90)
			recording=false
		var camp: Dictionary=app.camp_snapshot()
		for slot: int in range(mini(2,camp.journey.build.owned.size())): app.equip_build_item(slot,camp.journey.build.owned[slot])
		app.close_loadout()

func _assist(world: Expedition) -> void:
	if world.support_available() and world.survivors.any(func(a:FieldActor)->bool:return a.health>0 and a.health<130): world.request_heal()

func _until(world: Expedition,done: Callable,limit: int=12000) -> void:
	for index: int in range(limit):
		if done.call() or world.phase==Expedition.Phase.FINISHED or world.is_paused: break
		_assist(world)
		world.step(1.0/30.0)
		if (movie!=null and recording) or index%30==0: await _frame()
	_check(done.call(),"bounded real simulation reaches requested checkpoint")
	if not done.call():
		_write("failure-%d.json"%rows.size(),{"elapsed":world.elapsed,"phase":world.phase,"paused":world.is_paused,"message":app._progress_message,"events":events})
		quit(1)
		await process_frame

func _resume() -> void:
	if capture_caption!=null: capture_caption.text="自动输入 · 1×必要片段/接缝 · 非物理输入/FPS"
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	if output.get_file()=="readback":
		_check(app.camp_snapshot().journey.campaign.outcome=="VICTORY","new PID reads confirmed combat victory")
		await _shot("confirmed-victory")
		return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	var world: Expedition=app.expedition
	_check(world!=null,"new PID reconstructs combat state: "+app._progress_message)
	if world==null:return
	world.set_physics_process(false)
	world.set_process(false)
	_check(RecordEncoding.fingerprint(SortieSnapshot.capture(world))==expected.fingerprint and expected.pid!=OS.get_process_id(),"new PID exactly restores action/reload/toxic clocks and HP")
	if app.pause_menu.visible: await _tap(app.pause_menu.buttons[0])
	if world.is_paused: world.toggle_pause()
	if not world.supply.generated.campaign.is_finale:
		await _extract(world)
		_check(not app._progress_blocked,"boundary sortie original result authenticates")
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(app.camp_snapshot().journey.campaign.preparations==4,"boundary return confirms fourth preparation")
		await _menu(4)
		world=await _start(0)
		if world==null:return
	recording=true
	for index: int in range(12000):
		if not world.encounter.defeat.is_empty() or world.is_paused or world.phase==Expedition.Phase.FINISHED:break
		_assist(world)
		_frame_boss(world)
		world.command_move(world.encounter.actor.position+Vector2(35,15))
		world.step(1.0/30.0)
		if index%30==0 or (movie!=null and index<450): await _frame()
		if index==449:recording=false
	_check(not world.encounter.defeat.is_empty(),"actual equipped combat defeats boss with original lethal proof")
	recording=true
	await _extract(world)
	recording=false
	_check(not app._progress_blocked,"new weapon defeat authenticates original settlement: "+app._progress_message)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app.camp_snapshot().journey.campaign.outcome=="VICTORY","explicit return confirms combat victory")
	await _shot("confirmed-victory")

func _frame() -> void:
	var encoder: StreamPeerTCP=movie
	if not recording:movie=null
	await super._frame()
	movie=encoder

func _toxic_demo(world: Expedition) -> void:
	var caster: FieldActor=null
	for index: int in range(5400):
		for actor: FieldActor in world.enemies:
			if actor.enemy_behavior!=null and actor.enemy_behavior.kind==CombatEnemyRules.TOXIC: caster=actor
		if caster!=null or world.is_paused or world.phase==Expedition.Phase.FINISHED: break
		_assist(world)
		world.step(1.0/30.0)
		if index%30==0:await _frame()
	if caster==null:return
	var point: Vector2=Vector2.INF
	for heading: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var candidate: Vector2=caster.position+heading*210.0
		if world.navigation.is_clear(candidate) and ToxicV1.line_clear(caster.position,candidate,world.shot_obstacles) and world.navigation.path_between(world.survivors[0].position,candidate).size()>=2: point=candidate;break
	if not point.is_finite():return
	world.command_move(point)
	for index: int in range(2100):
		if not is_instance_valid(caster) or caster.health<=0 or world.is_paused:break
		_assist(world)
		world.step(1.0/30.0)
		if world.combat.holds(caster): world.command_move(SortieSnapshot._vec(world.combat.toxic.casters[str(caster.actor_id)].point))
		if not world.combat.toxic.zones.is_empty():break
		if index%30==0:await _frame()
	if world.combat.toxic.zones.is_empty():return
	recording=true
	var zone: Dictionary=world.combat.toxic.zones[0].duplicate(true)
	world.camera.pan_by(SortieSnapshot._vec(zone.point)-world.camera.position)
	world.camera.force_update_scroll()
	await _shot("toxic-warning-and-zone")
	for index: int in range(35):
		_assist(world)
		world.step(1.0/30.0)
		await _frame()
	var before: int=events.filter(func(e:Dictionary)->bool:return e.kind=="toxic_hit" and e.zone_id==zone.id).size()
	toxic_seen=before>0
	world.command_move(SortieSnapshot._vec(zone.point)+Vector2(110,0))
	var after_exit: int=-1
	for index: int in range(120):
		_assist(world)
		world.step(1.0/30.0)
		if after_exit<0 and world.survivors.filter(func(a:FieldActor)->bool:return a.health>0).all(func(a:FieldActor)->bool:return a.position.distance_to(SortieSnapshot._vec(zone.point))>60.0): after_exit=events.filter(func(e:Dictionary)->bool:return e.kind=="toxic_hit" and e.zone_id==zone.id).size()
		await _frame()
	if after_exit>=0: _check(events.filter(func(e:Dictionary)->bool:return e.kind=="toxic_hit" and e.zone_id==zone.id).size()==after_exit,"old zone causes no further ticks after actual exit")
	if toxic_seen: _check(true,"natural toxic release causes real original-owner damage")
	_check(world.survivors.filter(func(a:FieldActor)->bool:return a.health>0).all(func(a:FieldActor)->bool:return a.position.distance_to(SortieSnapshot._vec(zone.point))>60.0),"actual movement leaves locked danger area")
	await _shot("toxic-evaded")
	recording=false

func _boundary(world: Expedition) -> void:
	var found: bool=false
	world.command_move(world.survivors[0].position)
	for index: int in range(5400):
		if world.is_paused or world.phase==Expedition.Phase.FINISHED:break
		_assist(world)
		world.step(1.0/30.0)
		var attacking: bool=world.survivors.any(func(a:FieldActor)->bool:return (a.magazine!=null and a.magazine.reloading) or world.combat.actions.get(str(a.member_id),{}).get("remaining",0.0)>0)
		if attacking and not world.combat.toxic.zones.is_empty() and events.any(func(e:Dictionary)->bool:return e.kind=="toxic_hit"):found=true;break
		if index%30==0:await _frame()
	_check(found,"real windup/reload overlaps an active original toxic zone")
	world.toggle_pause()
	var snapshot: Dictionary=SortieSnapshot.capture(world)
	var preview: Dictionary=app.progress_session.preview_suspend(snapshot)
	_check(preview.error==OK,"combat boundary validates: "+str(preview.get("reason","")))
	_write("checkpoint.json",{"encoded":RecordEncoding.stringify(snapshot),"fingerprint":RecordEncoding.fingerprint(snapshot),"pid":OS.get_process_id(),"acquired":acquired,"events":events})
	await _shot("combat-checkpoint")
	app.open_pause_menu()
	app.suspend_sortie()
	await _hold(3)
	_check(app.expedition==null and app._requires_continue,"original suspend ACK publishes exact overlapping combat state")
