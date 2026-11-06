extends "res://tests/campaign_flow.gd"
## Real normal acquisition and transactions; fixture-only cases are labelled separately.
var equipped: String=""
var recording: bool=false
var recorded_camp: bool=false

func _hold(count: int=8) -> void:
	for i: int in range(count):
		if recording and is_instance_valid(app) and is_instance_valid(app.expedition):app.expedition.step(1.0/30.0)
		await _frame()

func _frame() -> void:
	var stream: StreamPeerTCP=movie
	if not recording:movie=null
	await super._frame()
	movie=stream

func _until(world: Expedition, done: Callable, limit: int=12000) -> void:
	for index: int in range(limit):
		if done.call() or world.phase==Expedition.Phase.FINISHED or world.is_paused:break
		world.step(1.0/30.0)
		if recording or index%30==0:await _frame()
	_check(done.call(),"bounded real simulation reaches checkpoint")
	if not done.call():
		_write("checkpoint-failure.json",{"elapsed":world.elapsed,"paused":world.is_paused,"phase":world.phase})
		quit(1);await process_frame


func _menu(_count: int=0) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible,"normal bus opens frozen candidates")
	for offer: Dictionary in app.mission_select.daily_offers: _check(PowerActions.problem(offer).is_empty(),"power capability preserves full V8 projection")

func _gear_slot() -> int:
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].type=="equipment": return i
	return 0

func _collect(world: Expedition) -> void:
	for site: Expedition.SearchSite in world.sites:
		if (site.id==&"cash" or site.kind==&"food") and not site.searched:
			if world.search_assignments.member_for(String(site.id))==0:world.request_search(site.id)
			await _until(world,func()->bool:return site.searched)

func _bank(world: Expedition) -> void:
	await _extract(world)
	_check(not app._progress_blocked,"real extraction authenticates frozen preview: "+app._progress_message)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(not app._progress_blocked and PowerState.problem(app.camp_snapshot()).is_empty(),"original confirmation banks strictly sourced ability: "+app._progress_message)

func _equip(id: String) -> void:
	app.open_loadout();await _hold(3)
	await _tap(app.loadout_panel.power_panel.choices[id])
	_check(app.camp_snapshot().journey.build.powers.slot==id,"camp single-slot choice is durably equipped")
	if not id.is_empty() and not recorded_camp:
		recording=true
		if capture_caption!=null:capture_caption.text="自动界面输入 · 装配与效果 1×片段 · 接缝剪辑 · 非物理输入"
		await _hold(150)
		await _shot("camp-powers")
		recording=false;recorded_camp=true
	await _tap(app.loadout_panel.back_button)
	equipped=id

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(PowerState.enabled(app.camp_snapshot()) and app.camp_snapshot().journey.build.powers.owned.is_empty(),"new mode begins without a free ability")
	await _menu()
	var offers: Array=app.mission_select.daily_offers.duplicate(true)
	await _tap(app.mission_select.cancel_button);await _menu()
	_check(TransactionReceipt.same({"v":offers},{"v":app.mission_select.daily_offers}),"browse does not reroll ability, weapon or passive")
	var world: Expedition=await _start(_gear_slot())
	if world==null:return
	_check(not world.request_power() and world.survivors.all(func(a:FieldActor)->bool:return a.effective_speed()==a.speed),"empty slot has no activation or speed effect on actual first sortie")
	await _collect(world)
	_check(app.camp_snapshot().journey.build.powers.owned.is_empty(),"actual sample is only carried before confirmation")
	await _bank(world)
	var owned: Array=app.camp_snapshot().journey.build.powers.owned
	_check(owned.size()==1,"first actual legal gear return grants one ability")
	if owned.size()!=1:return
	await _equip(owned[0])
	await _equip("")
	await _equip(owned[0])
	await _menu()
	world=await _start(_gear_slot())
	if world==null:return
	world.request_search(&"cash")
	for site: Expedition.SearchSite in world.sites:
		if site.id!=&"cash" and not site.searched:world.request_search(site.id);break
	var scroll: InputEventMouseButton=InputEventMouseButton.new();scroll.button_index=MOUSE_BUTTON_WHEEL_DOWN;scroll.pressed=true;scroll.position=Vector2(640,360)
	for i: int in range(5):viewport.push_input(scroll,true);await _frame()
	_check(world.camera.zoom.x>=0.7 and world.camera.zoom.x<0.71,"power transaction uses original strict minimum zoom")
	var echo: InputEventKey=InputEventKey.new();echo.keycode=KEY_3;echo.pressed=true;echo.echo=true;viewport.push_input(echo,true);await _frame()
	_check(world.powers.accepted.is_empty() and world.pending_power.is_empty(),"echo cannot initiate an activation")
	await _until(world,func()->bool:return world.elapsed>=8.0)
	_check(world.search_assignments.ordered().size()==2,"two original jobs remain independently assigned")
	app.open_pause_menu();await _key(KEY_3)
	_check(world.powers.accepted.is_empty() and world.pending_power.is_empty(),"menu input cannot activate special power")
	await _tap(app.pause_menu.buttons[0])
	var text: LineEdit=LineEdit.new();world._hud.view.add_child(text);text.position=Vector2(300,300);text.size=Vector2(150,40);await _hold(2);text.grab_focus()
	_check(viewport.gui_get_focus_owner()==text,"text fixture actually owns viewport focus")
	await _key(KEY_3)
	_check(world.powers.accepted.is_empty() and world.pending_power.is_empty(),"text focus cannot activate special power")
	text.release_focus();text.queue_free();await _hold(2)
	var fired: Dictionary={"once":false}
	app.progress_session.fault_hook=func(point:String)->Error:
		if point=="after_record_flush" and not fired.once:fired.once=true;return ERR_CANT_CREATE
		return OK
	_write("input-debug.json",{"focus":str(viewport.gui_get_focus_owner()),"paused":world.is_paused,"pending":world.pending_power,"input_enabled":world.is_processing_unhandled_input(),"powers":world.powers,"available":world.support_available(),"callback":world.power_commit.is_valid()})
	await _key(KEY_3)
	_check(fired.once and world.is_paused and not world.pending_power.is_empty() and world.powers.accepted.is_empty(),"real publication failure pauses without exposing use or effect")
	if world.pending_power.is_empty():return
	var request: Dictionary=world.pending_power.duplicate(true)
	app.progress_session.fault_hook=Callable();world.toggle_pause()
	_check(not world.is_paused and world.pending_power.is_empty() and world.powers.accepted.size()==1,"original request ACK retry accepts exactly once")
	if world.powers.accepted.is_empty():return
	_check(world.powers.accepted[0].at==request.before.sim.elapsed,"retry cannot extend activation interval")
	await _key(KEY_3)
	_check(world.powers.accepted.size()==1 and not world.request_power(),"repeated key and button intention cannot refill daily use")
	recording=true
	for i: int in range(30):world.step(1.0/30.0);await _frame()
	await _shot("first-effect")
	recording=false
	app.open_pause_menu();await _hold(2)
	var captured: Dictionary=SortieSnapshot.capture(world)
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	_check(SortieSnapshot.problem(captured,receipt).is_empty(),"active power and complete M10 jobs authenticate exactly")
	_check(SpecialPowers.remaining(world.powers,world.elapsed)>0,"cross-PID checkpoint is inside actual effect interval")
	var oracle_file: FileAccess=FileAccess.open(output.path_join("oracle.json"),FileAccess.WRITE)
	oracle_file.store_string(RecordEncoding.stringify({"world":captured,"receipt":receipt,"camp":app.camp_snapshot()}));oracle_file.close()
	_write("checkpoint.json",{"encoded":RecordEncoding.stringify(captured),"fingerprint":RecordEncoding.fingerprint(captured),"pid":OS.get_process_id()})
	app.suspend_sortie();await _hold(3)
	_check(app.expedition==null and app._requires_continue,"original suspend and ACK preserve active effect")

func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	var world: Expedition=app.expedition
	_check(world!=null,"new process restores active power world: "+app._progress_message)
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	_check(expected.pid!=OS.get_process_id() and RecordEncoding.fingerprint(SortieSnapshot.capture(world))==expected.fingerprint,"different PID exactly restores interval, use, actors, jobs, progress and actions")
	equipped=world.powers.equipped
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:world.toggle_pause()
	_check(not world.request_power(),"restart cannot refill today's special slot")
	# Actual basic-support world replacement must preserve the new capability and jobs.
	world.request_search(&"cash")
	var caller: FieldActor=world.survivors.filter(func(a:FieldActor)->bool:return a.visible and a.health>0)[0]
	var before: Dictionary=world.support_world()
	var point: Vector2=Vector2.INF
	for offset: Vector2 in [Vector2.DOWN*40,Vector2.RIGHT*40,Vector2.LEFT*40,Vector2.UP*40]:
		if not world.support_plan_airstrike(caller.position+offset).is_empty():point=caller.position+offset;break
	_check(point.is_finite(),"actual visible caller has reachable airstrike point")
	if point.is_finite():
		_check(world.request_airstrike(point),"original airstrike transaction accepts during active power")
		_check(TransactionReceipt.same(world.powers,before.powers) and TransactionReceipt.same(world.search_assignments.snapshot(),before.jobs),"full support replacement retains exact power and jobs")
	# Normal cancellation releases only one worker; show actual boosted movement.
	if world.powers.equipped=="speed_boost_v1":world.command_move(world.layout.bus_door)
	recording=true
	if capture_caption!=null:capture_caption.text="自动输入 · 疾行/冻结实际效果 1× · 非物理输入或显示器FPS"
	var until: float=world.powers.accepted[0].until
	await _until(world,func()->bool:return world.elapsed>=until+0.1)
	_check(world.survivors.all(func(a:FieldActor)->bool:return a.effective_speed()==a.speed) and not world.power_frozen,"expiry restores exact underlying speed and enemy action")
	await _hold(45);recording=false
	_check(not world.request_power(),"effect expiry is today-used rather than cooldown recharge")
	await _collect(world);await _bank(world)
	var camp: Dictionary=app.camp_snapshot()
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	var oracle_file: FileAccess=FileAccess.open(output.path_join("oracle.json"),FileAccess.WRITE)
	oracle_file.store_string(RecordEncoding.stringify({"world":RecordEncoding.unpack(JSON.parse_string(prior.encoded)).payload,"receipt":_source_oracle().receipt,"camp":camp}));oracle_file.close()
	_check(camp.journey.build.powers.uses.size()==1,"one immutable daily use reaches original settlement")
	# At most one extra legal day if the next frozen offers have no equipment.
	while camp.journey.build.powers.owned.size()<2 and camp.journey.campaign.preparations<4:
		await _menu();world=await _start(_gear_slot())
		if world==null:return
		_check(world.powers.accepted.is_empty(),"only real next-day departure restores daily opportunity")
		await _collect(world);await _bank(world);camp=app.camp_snapshot()
	_check(camp.journey.build.powers.owned.size()==2,"later actual legal gear return grants the other unowned sample")
	if camp.journey.build.powers.owned.size()!=2:return
	var other: String="map_freeze_v1" if equipped=="speed_boost_v1" else "speed_boost_v1"
	await _equip(other);await _menu();world=await _start(_gear_slot())
	if world==null:return
	_check(world.powers.accepted.is_empty(),"switching on genuinely next day uses fresh day identity")
	await _until(world,func()->bool:return not world.enemies.is_empty())
	# Follow actual spawned enemies through original navigation until real damage.
	for tick: int in range(6000):
		if world.survivors.any(func(a:FieldActor)->bool:return a.damage_received>0) or world.phase==Expedition.Phase.FINISHED or world.is_paused:break
		if tick%30==0 and not world.enemies.is_empty():world.command_move(world.enemies[0].position)
		world.step(1.0/30.0)
		if tick%30==0:await _frame()
	_check(world.living_count()>0 and world.survivors.any(func(a:FieldActor)->bool:return a.health>0 and a.damage_received>0),"natural combat damages a living actor before second power")
	_check(not world.enemies.is_empty(),"second power fixture retains actual live enemies")
	if world.enemies.is_empty():return
	var nearest: FieldActor=world.enemies[0]
	world.camera.pan_by(nearest.position-world.camera.position);world.camera.force_update_scroll()
	recording=true
	await _hold(90)
	await _tap(world.power_panel.activation_button)
	_check(world.powers.accepted.size()==1,"actual ability button activates second equipped power")
	var powers_before_heal: Dictionary=world.powers.duplicate(true)
	_check(world.request_heal(),"actual Q-heal transaction accepts original enemy damage while power remains active")
	_check(TransactionReceipt.same(world.powers,powers_before_heal),"heal full-world replacement retains activation and exact interval")
	var frozen_positions: Dictionary={}
	for enemy: FieldActor in world.enemies:frozen_positions[enemy.actor_id]={"point":enemy.position,"cooldown":enemy.cooldown,"behavior":enemy.enemy_behavior.snapshot()}
	world.command_move(world.layout.bus_door+Vector2(180,0))
	for i: int in range(45):world.step(1.0/30.0);await _frame()
	await _shot("second-effect")
	if other=="map_freeze_v1":
		_check(world.enemies.all(func(a:FieldActor)->bool:return not frozen_positions.has(a.actor_id) or (a.position==frozen_positions[a.actor_id].point and a.cooldown==frozen_positions[a.actor_id].cooldown and TransactionReceipt.same(a.enemy_behavior.snapshot(),frozen_positions[a.actor_id].behavior))),"actual live enemies retain exact feet, cooldown and windup during global freeze")
	for i: int in range(90):world.step(1.0/30.0);await _frame()
	await _hold(90);recording=false
	_write("second.json",{"powers":world.powers,"elapsed":world.elapsed,"speeds":world.survivors.map(func(a:FieldActor)->Dictionary:return {"base":a.speed,"effective":a.effective_speed()})})
	app.open_pause_menu();app.suspend_sortie();await _hold(2)

func _key(code: Key) -> void:
	for down: bool in [true,false]:
		var event: InputEventKey=InputEventKey.new();event.keycode=code;event.pressed=down
		viewport.push_input(event,true);await _frame()

func _source_oracle() -> Dictionary:
	var value: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/oracle.json")))
	return RecordEncoding.unpack(value).payload if value.has("record_encoding") else value

func flow_input_description() -> String:
	return "viewport Enter/Q/E/3 + original search/move/bus intentions; recorded gameplay advances one 1/30s step per frame; omitted preparation may run faster; no OS input"
