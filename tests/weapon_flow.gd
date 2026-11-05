extends "res://tests/task_flow.gd"
## M7 normal owners; only explicitly named pressure fixtures schedule extra ordinary spawns.
var shots: Array[Dictionary]=[]
var sample: Array[Dictionary]=[]
var pressure: bool=false
var pressure_clock: float=0.0
var extra_spawns: int=0
var fixture_point: Vector2
var hit_events: Array[Dictionary]=[]
var reload_move_requested: bool=false
var reload_movement: Array=[]
var no_target_reload: Array=[]

func _journey() -> void:
	if scenario=="oldworld":await _old_prepare();return
	await _tap(app._home_button);await _tap(app._new_game_confirmation.get_ok_button())
	await _menu()
	var type: String="supply" if scenario=="long-drop" else scenario if scenario in ["supply","equipment","rescue"] else "airdrop"
	if scenario in ["loop","oldcamp"] and not app.mission_select.daily_offers.any(func(value: Dictionary) -> bool:return value.type==type):type="equipment"
	await _start(type)
	var world: Expedition=app.expedition
	if world==null:return
	if scenario=="four":
		await _four_hud(world);return
	if scenario in ["combat","partial","reload","lifecycle","indoor","death","gates"]:
		await _battle(world)
		return
	if scenario in ["supply","equipment","rescue"]:
		await _complete_task(world)
		if scenario=="rescue":
			var joined: FieldActor=world.survivors[-1]
			_check(joined.magazine!=null and joined.magazine.instance_id==joined.weapon_instance_id,"actual rescue initializes its own equipped magazine")
			var state: Dictionary=joined.magazine.snapshot()
			world.promote_target(world.field_joins[0])
			_check(TransactionReceipt.same(state,joined.magazine.snapshot()),"repeated promotion cannot refill rescue magazine")
		_write("smoke.json",{"case":scenario,"sites":WorldSites.facts(world),"joins":world.field_joins,"weapons":world.weapon_loot})
		return
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.searched)
	var reward: Dictionary=world.weapon_loot[0].duplicate(true)
	var def: Dictionary=_selected.sites.filter(func(site: Dictionary) -> bool:return site.weapon)[0]
	_check(TransactionReceipt.same(reward,WeaponInventory.site_reward(world.sortie_id,_selected,def,true)),"actual carried weapon matches frozen site choice")
	await _shot("actual-drop-"+reward.weapon_id)
	if scenario=="long-drop":
		# Parent expectation adapter: this deliberately leaves the food objective early.
		scenario="early";await _finish(world,false);scenario="long-drop"
	else:await _finish(world,scenario=="loop")
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var panel: LoadoutPanel=app.loadout_panel
	var index: int=app.weapons.find(WeaponInventory.find(app.camp_snapshot(),reward.instance_id))
	panel.items.select(index);panel._select(index)
	await _shot("damaged-"+reward.weapon_id)
	await _tap(panel.repair_button);await _tap(panel.confirmation.get_ok_button())
	var ready: Dictionary=WeaponInventory.find(app.camp_snapshot(),reward.instance_id)
	reward.condition="ready"
	_check(TransactionReceipt.same(ready,reward),"actual repair changes only condition, no gun/attribute reroll")
	await _tap(panel.equip_by_id[1])
	_check(WeaponInventory.for_member(app.camp_snapshot(),1).instance_id==reward.instance_id,"actual equip keeps exact drop instance")
	_check(panel._detail.text.contains("弹匣") and panel._detail.text.contains("自动换弹"),"camp detail exposes magazine and seconds")
	await _shot("equipped-"+reward.weapon_id)
	await _tap(panel.back_button);await _menu()
	await _start(app.mission_select.daily_offers[0].type)
	for actor: FieldActor in app.expedition.survivors:
		_check(actor.magazine!=null and actor.magazine.rounds==actor.magazine.capacity(),"next sortie initializes each equipped instance full")
	_write("loop.json",{"reward":reward,"camp":app.camp_snapshot(),"shots":shots})
	if scenario=="post-kill":await _post_kill(app.expedition)

func _start(type: String) -> void:
	_before=app.camp_snapshot()
	var slot: int=-1
	for i: int in range(3):
		if app.mission_select.daily_offers[i].type==type:slot=i;_selected=app.mission_select.daily_offers[i].duplicate(true)
	_check(slot>=0,"requested V5 task offered: "+type)
	if slot<0:return
	await _tap(app.mission_select.choices[slot])
	var world: Expedition=app.expedition
	_check(world!=null,"normal selection opens V5 action")
	if world==null:return
	world.set_process(false);world.set_physics_process(false);world.camera.set_process(false)
	var initial: Array=[]
	for actor: FieldActor in world.survivors:initial.append(actor.magazine.snapshot())
	await _advance(world,func() -> bool:return not world.bus_view.running())
	for i: int in range(world.survivors.size()):_check(TransactionReceipt.same(initial[i],world.survivors[i].magazine.snapshot()),"arrival cannot advance magazines")
	world.finished.connect(func(report: Dictionary) -> void:journey_reports.append(report.duplicate(true)))
	world.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind=="shot":shots.append(event.duplicate(true)))
	_check(app.progress_session._transaction.recover().receipt.rules.data_version==6,"new authority is rules6")
	await _hud_sample(world)


func _pressure_fixture(world: Expedition) -> void:
	world.battle_drill=true
	world.drill_panel.queue_free();world.drill_panel=BattleDrillPanel.new();world.drill_panel.expedition=world
	world._hud.view.add_child(world.drill_panel)
	fixture_point=world.search_site(&"food" if scenario=="indoor" else &"cash").door
	world.command_move(fixture_point)
	pressure=true;pressure_clock=0.0
	await _advance(world,func() -> bool:return world.survivors.all(func(actor: FieldActor) -> bool:return actor.position.distance_to(fixture_point)<64))
	_check(world.survivors[0].magazine!=world.survivors[1].magazine,"two equipped instances own independent states")

func _battle(world: Expedition) -> void:
	if movie!=null:capture_caption.text="Mac 离屏实机 · 1×模拟 · 原刷怪owner压力夹具 · 无限备弹"
	world.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind=="hit":
			var actor: FieldActor=world.survivors.filter(func(member: FieldActor) -> bool:return member.member_id==event.member_id)[0]
			var row: Dictionary=event.duplicate(true);row.activity=actor.activity;row.magazine=actor.magazine.snapshot();hit_events.append(row))
	var initial: Array=[]
	for actor: FieldActor in world.survivors:initial.append(actor.magazine.snapshot())
	world.step(1.0/30.0)
	for i: int in range(2):_check(TransactionReceipt.same(initial[i],world.survivors[i].magazine.snapshot()),"no target cannot consume ammunition")
	await _pressure_fixture(world)
	if scenario=="gates":
		await _gates(world);return
	if scenario=="partial":
		await _advance(world,func() -> bool:return world.survivors[0].magazine.rounds<world.survivors[0].magazine.capacity() and world.survivors[0].magazine.rounds>0)
		await _suspend(world);return
	if scenario=="death":
		await _death(world);return
	if scenario in ["lifecycle","indoor"]:
		await _advance(world,func() -> bool:return world.survivors[0].magazine.reloading)
		await _lifecycle(world);return
	if scenario=="reload":
		await _advance(world,func() -> bool:return world.survivors[1].magazine.reloading and world.survivors[1].magazine.remaining<1.7)
		if scenario=="reload":await _suspend(world);return
		await _lifecycle(world);return
	await _advance(world,func() -> bool:return _shot_count(1)>=13 and _shot_count(2)>=6,5400)
	for actor: FieldActor in world.survivors:
		var own: Array=shots.filter(func(row: Dictionary) -> bool:return row.member_id==actor.member_id)
		var cap: int=actor.magazine.capacity()
		_check(own.size()>cap,"actual full magazine and later shot: "+str(actor.member_id))
		if own.size()<=cap:continue
		for i: int in range(cap):_check(own[i].magazine.rounds==cap-i-1 and own[i].applied_damage>0,"successful original damage spends exactly one round")
		_check(own[cap-1].magazine.reloading and own[cap-1].magazine.remaining==actor.magazine.seconds(),"last shot starts full timer without same-step advance")
		_check(own[cap].elapsed-own[cap-1].elapsed+0.000001>=actor.magazine.seconds(),"empty weapon waits entire reload before next legal shot")
	var rounds: int=world.survivors[0].magazine.rounds
	world._update_combat()
	_check(world.survivors[0].magazine.rounds==rounds,"immediate cooldown retry cannot spend another round")
	_check(not reload_movement.is_empty(),"actual paths move while independent reload clocks run")
	_check(not no_target_reload.is_empty(),"active reload progresses without an available target")
	await _hud_sample(world);await _shot("magazines-in-combat")
	if movie!=null:
		var end: float=world.elapsed+12.0
		await _advance(world,func() -> bool:return world.elapsed>=end)
	_write("combat.json",{"shots":shots,"hits":hit_events,"samples":sample,"reload_movement":reload_movement,"no_target_reload":no_target_reload,"extra_spawns":extra_spawns,"fixture":"bounded scheduling through original safe ordinary spawn owner; no HP/damage/position/completion injection"})

func _shot_count(member: int) -> int:
	return shots.filter(func(event: Dictionary) -> bool:return event.member_id==member).size()

func _suspend(world: Expedition) -> void:
	await _shot("before-"+scenario)
	app.open_pause_menu();await _hold(3)
	var exact: Dictionary=SortieSnapshot.capture(world)
	_check(exact.version==8 and app.progress_session.preview_suspend(exact).error==OK,"V8 actual partial magazine/reload preview authenticates")
	_write("world-exact.json",{"encoded":RecordEncoding.stringify(exact),"selected":_selected,"camp":_before,"shots":shots,"case":scenario})
	await _tap(app.pause_menu.buttons[4])
	_check(app.expedition==null and app._requires_continue,"original suspend ACK releases same combat world")
	var receipt: Dictionary=app.progress_session.inspect().receipt
	_check(SortieSnapshot.problem(exact,receipt).is_empty(),"V8 agrees with published health checkpoint")
	for change: String in ["instance","swap","negative","capacity","fraction","time","nan","phase","unknown","version"]:
		var bad: Dictionary=exact.duplicate(true)
		var mag: Dictionary=bad.survivors[0].magazine
		match change:
			"instance":mag.instance_id="wrong"
			"swap":mag.instance_id=bad.survivors[1].magazine.instance_id
			"negative":mag.rounds=-1
			"capacity":mag.rounds=100
			"fraction":mag.rounds=0.5
			"time":mag.remaining=100
			"nan":mag.remaining=NAN
			"phase":mag.reloading=not mag.reloading
			"unknown":mag.extra=1
			"version":mag.version=2
		_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"strict world rejects magazine "+change)

	if scenario=="reload":
		var journal: ReceiptJournal=app.progress_session._transaction._journal
		var valid: Dictionary=journal.read_all()
		var path: String=journal.directory.path_join("%08d/record.json"%int(valid.receipt.revision))
		var original: String=FileAccess.get_file_as_string(path)
		var digest: String=FileAccess.get_sha256(path)
		for kind: String in ["rounds","identity","timer"]:
			var changed: Dictionary=valid.receipt.duplicate(true)
			var mag: Dictionary=changed.envelope.world.survivors[0].magazine
			if kind=="rounds":mag.rounds=-1
			elif kind=="identity":mag.instance_id="foreign"
			else:mag.remaining=100.0
			changed.envelope.world_hash=SurvivalContracts.fingerprint(changed.envelope.world)
			var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
			file.store_string(RecordEncoding.stringify(changed));file.close()
			_check(journal.read_all().error!=OK,"warm byte proof rejects rehashed magazine "+kind)
			file=FileAccess.open(path,FileAccess.WRITE);file.store_string(original);file.close()
			_check(journal.read_all().error==OK and FileAccess.get_sha256(path)==digest,"warm negative restores exact receipt bytes "+kind)

func _resume() -> void:
	if scenario=="oldworld":await _old_resume();return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/world-exact.json")))
	var previous: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/report.json")))
	app.survival_pilot=false # Reconstruct the explicit diagnostic flag, never low-HP seeding.
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	app.survival_pilot=true
	var world: Expedition=app.expedition
	_check(world!=null and previous.pid!=OS.get_process_id(),"new PID continues same magazine action")
	if world==null:return
	world.set_process(false);world.set_physics_process(false);world.camera.set_process(false)
	var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload
	_check(TransactionReceipt.same(exact,SortieSnapshot.capture(world)),"exact identity/HP/enemies/drop/rounds/reload remaining restored")
	_selected=expected.selected;_before=expected.camp
	var member: int=1 if scenario=="partial" else 2
	var actor: FieldActor=world.survivors[member-1]
	var rounds: int=actor.magazine.rounds
	var remaining: float=actor.magazine.remaining
	var elapsed_before: float=world.elapsed
	world.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind=="shot":shots.append(event.duplicate(true)))
	await _shot("restored-"+scenario)
	await _tap(app.pause_menu.buttons[0]);if world.is_paused:world.toggle_pause()
	await _advance(world,func() -> bool:return _shot_count(member)>0)
	var first: Dictionary=shots.filter(func(row: Dictionary) -> bool:return row.member_id==member)[0]
	_check(first.magazine.rounds==(rounds-1 if scenario=="partial" else actor.magazine.capacity()-1),"resume gives no free extra rounds")
	if scenario=="reload":_check(first.elapsed-elapsed_before+0.000001>=remaining,"half reload retains outstanding wait")
	_write("resumed.json",{"shots":shots,"remaining_before":remaining,"rounds_before":rounds,"expected":expected.case})

func _lifecycle(world: Expedition) -> void:
	var actor: FieldActor=world.survivors[0]
	var other: FieldActor=world.survivors[1]
	var kind: StringName=&"food" if scenario=="indoor" else &"cash"
	var site: Expedition.SearchSite=world.search_site(kind)
	var away: Vector2=Vector2.INF
	for offset: Vector2 in [Vector2(96,0),Vector2(-96,0),Vector2(0,96),Vector2(0,-96)]:
		if world.navigation.is_clear(site.door+offset) and not world.navigation.path_between(other.position,site.door+offset).is_empty():away=site.door+offset;break
	_check(away.is_finite(),"reachable bystander stance")
	other.command_path(world.navigation.path_between(other.position,away))
	actor.command_path(world.navigation.path_between(actor.position,site.door))
	await _advance(world,func() -> bool:return actor.position.distance_to(site.door)<14 and other.position.distance_to(site.door)>50)
	_check(actor.magazine.reloading,"real paths reach work with a partial reload")
	world.request_search(kind)
	await _advance(world,func() -> bool:return site.progress>0)
	_check(world.search_actor==actor,"reloading member is actual worker")
	var remaining: float=actor.magazine.remaining
	var hp: float=actor.health
	var progress: float=site.progress
	await _advance(world,func() -> bool:return site.progress>progress+0.5)
	_check(actor.magazine.reloading and actor.magazine.remaining==remaining,"working pauses existing reload without refill")
	var elapsed_before: float=world.elapsed
	world.toggle_pause();world.step(2.0)
	_check(actor.magazine.remaining==remaining and world.elapsed==elapsed_before,"pause cannot advance reload or combat")
	world.toggle_pause()
	if kind==&"cash":
		for button: Button in world.drill_panel.buttons:
			if int(button.get_meta("member_id"))==actor.member_id:await _tap(button)
		await _advance(world,func() -> bool:return hit_events.any(func(event: Dictionary) -> bool:return event.member_id==actor.member_id and event.activity==FieldActor.Activity.RECOVERING))
		_check(actor.visible and actor.health<hp and actor.magazine.remaining==remaining,"outdoor reload-paused worker remains visible and takes original AI damage")
	else:
		_check(not actor.visible and actor.activity==FieldActor.Activity.SEARCHING and actor.health==hp and not world._combatant(actor).available,"indoor original protected work pauses reload")
	world._update_ui();await _shot("work-paused-reload-"+String(kind))
	app.open_pause_menu()
	_check(app.progress_session.preview_suspend(SortieSnapshot.capture(world)).error==OK,"work plus partial reload is valid in original suspend owner")
	await _tap(app.pause_menu.buttons[0]);if world.is_paused:world.toggle_pause()
	world.request_search(kind)
	_check(world.search_actor==null and actor.magazine.remaining==remaining,"cancel releases work without resetting ammunition")
	world.step(1.0/30.0)
	_check(not actor.magazine.reloading or actor.magazine.remaining<remaining,"release resumes original reload clock")
	_write("lifecycle.json",{"kind":String(kind),"paused_remaining":remaining,"released":actor.magazine.snapshot(),"hits":hit_events,"shots":shots})

func _death(world: Expedition) -> void:
	var actor: FieldActor=world.survivors[0]
	await _advance(world,func() -> bool:return _shot_count(1)==11 and actor.magazine.rounds==1)
	pressure=false
	world.survivors[1].command_path(world.navigation.path_between(world.survivors[1].position,world.layout.bus_door))
	actor.cooldown=999.0 # Existing designated-subject fixture; HP remains original AI/writer output.
	await _advance(world,func() -> bool:return actor.health<=8.0,9000)
	_check(actor.health>0 and actor.magazine.rounds==1,"actual AI produces low HP while one real round remains")
	if actor.health<=0:return
	actor.cooldown=0.0 # Release the named fixture, not a change to shot interval or reload speed.
	await _advance(world,func() -> bool:return actor.permanent_death,900)
	_check(actor.permanent_death and actor.magazine.reloading,"original AI death occurs during actual automatic reload")
	var remaining: float=actor.magazine.remaining
	world.step(0.4)
	_check(actor.magazine.remaining==remaining,"death stops reload without filling magazine")
	_write("death.json",{"health":actor.health,"remaining":remaining,"magazine":actor.magazine.snapshot(),"shots":shots,"hits":hit_events})

func _advance(world: Expedition, until: Callable, limit: int=7200) -> void:
	for tick: int in range(limit):
		if until.call():return
		if world.phase==Expedition.Phase.FINISHED and not world.bus_view.running():break
		if pressure and world.elapsed<70.0 and extra_spawns<12:
			pressure_clock-=1.0/30.0
			if pressure_clock<=0:
				world._spawn_enemy(EnemyRules.NORMAL,fixture_point);extra_spawns+=1;pressure_clock=2.0
		if scenario=="combat" and not reload_move_requested and world.survivors.any(func(actor: FieldActor) -> bool:return actor.magazine.reloading):
			reload_move_requested=true
			world.command_move(fixture_point+Vector2(72,0))
		var without_target: Dictionary={}
		for actor: FieldActor in world.survivors:
			if actor.magazine!=null and actor.magazine.reloading and actor.health>0 and world._attack_target(actor)==null:without_target[actor.member_id]=actor.magazine.remaining
		var before: Array=[]
		for actor: FieldActor in world.survivors:before.append(actor.position)
		var was: int=world.phase
		var started: int=Time.get_ticks_usec()
		world.step(1.0/30.0)
		if was!=Expedition.Phase.FINISHED and world.phase==Expedition.Phase.FINISHED:task_freezes.append({"step_usec":Time.get_ticks_usec()-started,"size":_selected.layout["size"],"survivors":world.survivors.size(),"enemies":world.enemies.size(),"elapsed":world.elapsed})
		for i: int in range(world.survivors.size()):
			var actor: FieldActor=world.survivors[i]
			if without_target.has(actor.member_id) and actor.magazine.remaining<without_target[actor.member_id] and no_target_reload.size()<4:no_target_reload.append({"member":actor.member_id,"elapsed":world.elapsed,"before":without_target[actor.member_id],"after":actor.magazine.remaining})
			if actor.magazine!=null and actor.magazine.reloading and actor.position.distance_to(before[i])>0.01 and reload_movement.size()<6:reload_movement.append({"member":actor.member_id,"elapsed":world.elapsed,"remaining":actor.magazine.remaining})
		if tick%30==0:
			var magazines: Array=[]
			for actor: FieldActor in world.survivors:magazines.append({"member":actor.member_id,"position":[actor.position.x,actor.position.y],"activity":actor.activity,"health":actor.health,"state":actor.magazine.snapshot() if actor.magazine!=null else {}})
			sample.append({"elapsed":world.elapsed,"magazines":magazines})
		var point: Vector2=world.search_actor.position if world.search_actor!=null else world.survivors[0].position
		world.camera.position=point+Vector2(200,-120);world.camera._clamp_position();world.camera.force_update_scroll()
		if movie!=null or tick%6==0:await _frame()
	_check(until.call(),"bounded M7 real checkpoint")


func _gates(world: Expedition) -> void:
	var original: Array[ShotObstacle]=world.shot_obstacles.duplicate()
	world.shot_obstacles.append(ShotObstacle.new(&"M7_TEST_WALL",Rect2(-10000,-10000,20000,20000),true))
	var actor: FieldActor=world.survivors[0]
	await _advance(world,func() -> bool:return world.survivors.all(func(member: FieldActor) -> bool:return member.magazine.can_fire() and member.cooldown==0) and world.enemies.any(func(enemy: FieldActor) -> bool:return enemy.position.distance_to(actor.position)<actor.weapon_definition.shot_range))
	var target: FieldActor=world._nearest_target(actor,world.enemies,actor.weapon_definition.shot_range)
	var state: Array=[]
	for member: FieldActor in world.survivors:state.append(member.magazine.snapshot())
	var hp: float=target.health
	world._update_combat()
	_check(world.evaluate_attack(actor,target).reason==&"blocked" and target.health==hp and TransactionReceipt.same(state[0],actor.magazine.snapshot()),"original LOS refusal cannot damage or consume a round")
	world.shot_obstacles=original
	var ranges: Array=[]
	for member: FieldActor in world.survivors:ranges.append(member.weapon_definition.shot_range);member.weapon_definition.shot_range=1.0
	world._update_combat()
	_check(world.evaluate_attack(actor,target).reason==&"out_of_range" and target.health==hp and TransactionReceipt.same(state[0],actor.magazine.snapshot()),"controlled range refusal cannot consume ammunition")
	for i: int in range(2):world.survivors[i].weapon_definition.shot_range=ranges[i]
	var events_before: Array[Dictionary]=world.xp_inputs.events.duplicate(true)
	world.xp_inputs.events.resize(GrowthRules.MAX_EVENTS) # Isolated capacity fixture; never saved.
	var shot_count: int=shots.size()
	world._update_combat()
	_check(world.is_paused and target.health==hp and shots.size()==shot_count and TransactionReceipt.same(state[0],actor.magazine.snapshot()),"original capacity gate aborts before damage, fire feedback or ammo")
	world.xp_inputs.events.assign(events_before);world.toggle_pause()
	world._update_combat()
	var after: Dictionary=actor.magazine.snapshot()
	world._update_combat()
	_check(TransactionReceipt.same(after,actor.magazine.snapshot()),"same-frame cooldown repeat cannot spend another round")
	_write("gates.json",{"checks":rows,"fixture":"temporary LOS wall, range bound and full-capacity input; all restored; no HP/damage writes","shots":shots})

func _four_hud(world: Expedition) -> void:
	var hud: C1ExpeditionHud=world._hud.view
	var members: Array=[]
	for i: int in range(4):
		var gun: String="carbine" if i%2==0 else "long_rifle"
		members.append({"id":i+1,"call_sign":"布局样本"+str(i+1),"hp":200,"max_hp":200,"status":"回收 · 换弹暂停" if i==2 else "移动 · 换弹1.5s","ammo":"%s 0/%d · ∞"%[WeaponInventory.definition(gun).display_name,WeaponDefinition.MAGAZINES[gun].capacity]})
	hud.refresh({"mission_title":"四人HUD布局夹具 · 非真实编制","day_text":"第2天","survivors":members})
	await _hold(5)
	_check(hud.get_node("MissionPanel").size.y<=144,"four-person weapon/reload HUD stays compact")
	for row: Dictionary in hud._members:
		_check(row.ammo.get_line_count()==1 and row.status.get_line_count()==1 and row.ammo.get_minimum_size().x<=row.box.size.x,"each weapon/ammo/status fits one readable column")
	await _shot("four-person-magazine-hud")
	_write("four-hud.json",{"height":hud.get_node("MissionPanel").size.y,"members":members,"fixture":"UI layout only, no crew or campaign edits"})


func _old_prepare() -> void:
	var path: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon-legacy="):path=arg.trim_prefix("--weapon-legacy=")
	assert(path.begins_with(ProjectSettings.globalize_path("res://.local/")))
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(source.encoded)).payload
	_check(exact.version==7 and source.selected.version==4,"retained synthetic V7/V4 source, never player data")
	var created: Dictionary=app.progress_session.create(source.camp)
	_check(created.error==OK,"original writer registers same old synthetic camp at new isolated binding")
	if created.error!=OK:return
	app._apply_progress(source.camp);app._hunger_consented=true
	app.progress_session.daily_actions=false # Fixture reconstructs the old selected action; normal offers remain V5.
	app._select_mission(TaskActions.supply(source.selected))
	if app.expedition!=null:app.expedition.set_physics_process(false);app.expedition.set_process(false)
	var saved: Dictionary=app.progress_session.suspend_world(exact)
	_check(saved.error==OK,"old world authenticates in fresh binding without reinterpretation: "+str(saved.get("reason","")))
	_write("old-source.json",source)

func _old_resume() -> void:
	if output.get_file()=="camp":
		var expected: Dictionary=RecordEncoding.unpack(JSON.parse_string(JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("resume/old-camp.json"))).encoded)).payload
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
		_check(TransactionReceipt.same(expected,app.camp_snapshot()),"new PID preserves old completed money/crew/inventory and attributes")
		await _menu();await _start(app.mission_select.daily_offers[0].type)
		_check(app.expedition.supply.generated.version==5 and app.expedition.survivors.all(func(actor: FieldActor) -> bool:return actor.magazine!=null and actor.magazine.rounds==actor.magazine.capacity()),"old completed camp begins a new full-magazine V5 action")
		return
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/old-source.json")))
	app.survival_pilot=false
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	app.survival_pilot=true
	var world: Expedition=app.expedition
	_check(world!=null,"old V7 underway can continue under original unlimited-fire policy")
	if world==null:return
	world.set_process(false);world.set_physics_process(false)
	var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(source.encoded)).payload
	_check(TransactionReceipt.same(exact,SortieSnapshot.capture(world)) and world.survivors.all(func(actor: FieldActor) -> bool:return actor.magazine==null),"old state restores exactly, no missing-ammo refill or field migration")
	_selected=source.selected;_before=source.camp
	world.finished.connect(func(report: Dictionary) -> void:journey_reports.append(report.duplicate(true)))
	await _tap(app.pause_menu.buttons[0]);if world.is_paused:world.toggle_pause()
	await _advance(world,func() -> bool:return world.searched)
	_check(world.weapon_loot.size()==1 and world.weapon_loot[0].weapon_id=="long_rifle" and not world.weapon_loot[0].has("drop"),"old actual completion still yields original fixed long rifle")
	await _finish(world,false)
	_write("old-camp.json",{"encoded":RecordEncoding.stringify(app.camp_snapshot())})


func _post_kill(world: Expedition) -> void:
	_check(world.survivors[0].weapon_definition.id==&"carbine" and WeaponInventory.for_member(_before,1).has("drop"),"second sortie really equips the repaired new carbine")
	await _pressure_fixture(world)
	await _advance(world,func() -> bool:return world.survivors[0].confirmed_kills>0)
	_check(world.growth_inputs._recent[1].any(func(event: Dictionary) -> bool:return event.weapon_id=="carbine" and event.instance_id==world.survivors[0].weapon_instance_id),"real defeat records actual dropped carbine identity")
	world.request_search(&"cash");await _advance(world,func() -> bool:return world.searched)
	# Replenish the actual second-day ration through real sites, never a fixture food edit.
	for site: Expedition.SearchSite in world.sites:
		if site.kind==&"food" and not site.searched:
			world.request_search(site.id);await _advance(world,func() -> bool:return site.searched)
	await _advance(world,func() -> bool:return world.elapsed>=world.tuning.bus_ready_seconds)
	world.request_bus_action();await _advance(world,func() -> bool:return world.phase==Expedition.Phase.BOARDING)
	world.request_bus_gather();await _advance(world,func() -> bool:return world.phase==Expedition.Phase.FINISHED)
	_check(not app._progress_blocked and world.bus_view.running(),"new-carbine kill history permits strict frozen return: "+app._progress_message)
	if app._progress_blocked:
		_write("post-kill.json",{"blocked":true,"reason":app._progress_message,"reports":journey_reports});return
	await _advance(world,func() -> bool:return not world.bus_view.running())
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app.day==_before.day+1 and TransactionReceipt.camp_problem(app.camp_snapshot()).is_empty(),"second confirmed camp retains actual gun and growth history")
	var actual: Dictionary=app.camp_snapshot()
	var legacy: Dictionary=WeaponState.projected(actual)
	_check(SurvivorGrowth.validate_member(actual.crew[0],actual).is_empty(),"actual carbine history authenticates before projection")
	var bad: Dictionary=actual.duplicate(true)
	bad.crew[0].growth.last_action.recent[0].weapon_id="long_rifle"
	_check(not TransactionReceipt.camp_problem(bad).is_empty(),"forged dropped-gun history remains rejected")
	_check(actual.crew[0].growth.last_action.recent[0].weapon_id=="carbine","legacy view cannot mutate serialized actual history")
	_write("post-kill.json",{"blocked":false,"camp":actual,"legacy_valid":RosterState.problem(legacy,true).is_empty(),"shots":shots})
