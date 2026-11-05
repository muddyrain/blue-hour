extends "res://tests/task_flow.gd"
## R1 real work/combat regression. Only the named contact fixture is diagnostic.
var combat: Array[Dictionary] = []
var track: FieldActor
var work_shots: int = 0

func _journey() -> void:
	if movie!=null: capture_caption.text="Mac 离屏实机 · 隔离接敌夹具 · 原AI/伤害写者 · 行动1×"
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _menu()
	await _start("supply" if scenario=="indoor" else "airdrop")
	var world: Expedition = app.expedition
	world.combat_feedback.connect(func(event: Dictionary) -> void:
		combat.append(event.duplicate(true))
		if track!=null and event.kind=="shot" and event.actor==track.actor_id and track.activity==FieldActor.Activity.RECOVERING: work_shots+=1)
	if scenario=="normal":
		await _complete_task(world)
		await _finish(world,false)
		return
	if scenario=="indoor":
		await _indoor(world)
		return
	if scenario=="death":
		await _death(world)
		return
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.search_site(&"cash").progress>=1.0)
	track=world.search_actor
	_check(track!=null and track.visible,"outdoor worker remains visible at real crate")
	if track==null:return
	_check(world._nearest_target(world.enemies[0],[track],INF)==track,"original enemy selection includes outdoor worker")
	_check(world._combatant(track).available,"outdoor worker passes original attack qualification")
	if scenario=="probe":return
	var position_before: Vector2=track.position
	world.command_move(world.layout.bus_door)
	world.step(1.0/30.0)
	_check(track.position==position_before and track.activity==FieldActor.Activity.RECOVERING,"group move leaves outdoor worker at crate")
	if scenario=="legacy":
		# Synthetic old work meaning, solely for the pre-claim rejection contract.
		app.open_pause_menu()
		var old: Dictionary=SortieSnapshot.capture(world)
		old.version=6;old.build=old.build.replace(SortieSnapshot.OUTDOOR_BUILD,SortieSnapshot.TASK_BUILD)
		var state: Dictionary=SortieSnapshot._member(old.survivors,int(old.worker)).state
		state.activity=2;state.visible=false
		for enemy: Dictionary in old.enemies:
			if enemy.behavior.target_id==old.worker: enemy.behavior.target_id=0
		var saved: Dictionary=app.progress_session.suspend_world(old)
		_check(saved.error==OK,"original writer publishes synthetic old V6 indoor-style airdrop contract: "+str(saved.get("reason","")))
		if saved.error!=OK:return
		var current: Dictionary=app.progress_session.inspect()
		_check(SortieSnapshot.problem(old,current.receipt).is_empty(),"historical V6 authentication stays available")
		_write("legacy.json",{"files":_files(),"head":current.hash,"world_hash":current.receipt.envelope.world_hash})
		return
	var event: Dictionary=world.task_event.duplicate(true)
	var progress: float=world.search_site(&"cash").progress
	var former: FieldActor=track
	world.request_search(&"cash")
	_check(world.search_actor==null and former.visible and former.activity!=FieldActor.Activity.RECOVERING and world.search_site(&"cash").progress==progress,"cancel releases visible worker and retains partial progress")
	var replacement: FieldActor=world.survivors[1] if former==world.survivors[0] else world.survivors[0]
	former.command_path(world.navigation.path_between(former.position,world.layout.bus_door))
	replacement.command_path(world.navigation.path_between(replacement.position,world.search_site(&"cash").door))
	await _advance(world,func() -> bool:return replacement.position.distance_to(world.search_site(&"cash").door)<8.0 and former.position.distance_to(world.search_site(&"cash").door)>64.0)
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.search_site(&"cash").progress>progress+0.3)
	track=world.search_actor
	var work_frame: int=frames
	_check(track==replacement and world.work_state_matches(track,world.search_site(&"cash")),"different stable member actually takes over at crate")
	_check(TransactionReceipt.same(event,world.task_event),"worker change retains exactly one two-resolution event")
	await _contact(world,track)
	var hp: float=track.health
	await _advance(world,func() -> bool:return track.health<hp)
	var attacker: FieldActor=world.enemies.filter(func(enemy: FieldActor) -> bool:return enemy.actor_id==10000+track.member_id)[0]
	_check(attacker.enemy_behavior.target_id==track.member_id and attacker.enemy_behavior.legal(world,attacker,track,EnemyRules.POLICY.melee_range),"original AI target and LOS remain legal at actual injury")
	_check(track.visible and track.health>0 and track.activity==FieldActor.Activity.RECOVERING and work_shots==0,"real AI injury retains visible stationary work and no worker gunfire")
	_check(world.search_site(&"cash").progress<12 and not world.searched and world.weapon_loot.is_empty(),"partial injured work cannot invent completion or weapon")
	var injury_frame: int=frames
	await _advance(world,func() -> bool:return world.search_site(&"cash").progress>=4.0)
	await _shot("visible-worker-injured")
	_write("movie-facts.json",{"work_frame":work_frame,"first_injury_frame":injury_frame,"end_frame":frames,"fps":30,"simulation_ticks_per_frame":1 if movie!=null else 6,"fixture":"existing explicit 36px ordinary enemy","hp_injected":false,"physical_input":"NOT_TESTED"})
	_write("combat.json",{"events":combat,"worker":track.member_id,"before_hp":hp,"after_hp":track.health,"work_shots":work_shots,"event":event,"method":"explicit existing 36px ordinary enemy fixture; no HP, position, damage or completion injection"})
	app.open_pause_menu();await _hold(3)
	var exact: Dictionary=SortieSnapshot.capture(world)
	_check(app.progress_session.preview_suspend(exact).error==OK,"original preview authenticates injured world with projected checkpoint")
	_write("world-exact.json",{"encoded":RecordEncoding.stringify(exact),"hash":SurvivalContracts.fingerprint(exact),"selected":_selected,"camp":_before,"event":event})
	await _tap(app.pause_menu.buttons[4])
	_check(app.expedition==null and app._requires_continue,"original suspend ACK stores outdoor partial without banking")
	var receipt: Dictionary=app.progress_session.inspect().receipt
	_check(exact.version==7 and SortieSnapshot.problem(exact,receipt).is_empty(),"V7 authenticates outdoor state against published injury checkpoint")
	_negatives(exact,receipt)

func _resume() -> void:
	if scenario=="legacy":
		var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/legacy.json")))
		var offer: Dictionary=app.progress_session.resume_offer()
		_check(offer.error!=OK and offer.reason=="WORLD_OUTDOOR_BUILD_MISMATCH","old airdrop is explicitly refused before claim")
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
		var current: Dictionary=app.progress_session.inspect()
		_check(app.expedition==null and current.state=="SUSPENDED" and current.hash==old.head,"UI refusal keeps original generation unconsumed")
		_check(TransactionReceipt.same(old.files,_files()),"old camp/backup/binding/receipt bytes remain unchanged")
		_check(app._progress_message.contains("旧回收规则"),"player receives explicit old outdoor rule explanation")
		_write("legacy-refusal.json",{"reason":offer.reason,"state":current.state,"files":_files(),"message":app._progress_message})
		return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/world-exact.json")))
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/report.json")))
	# Fixture is enabled only for reconstruction; ordinary default entry stays unchanged.
	app.survival_pilot=false
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	app.survival_pilot=true
	var world: Expedition=app.expedition
	_check(world!=null and prior.pid!=OS.get_process_id(),"new PID reconstructs diagnostic outdoor partial")
	if world==null:return
	world.set_process(false);world.set_physics_process(false)
	var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload
	_check(TransactionReceipt.same(SortieSnapshot.capture(world),exact),"exact worker ID/position/HP/work/visibility/event/enemies restored")
	_selected=expected.selected;_before=expected.camp
	track=world.search_actor
	var hp: float=track.health
	world.combat_feedback.connect(func(event: Dictionary) -> void:combat.append(event.duplicate(true)))
	await _tap(app.pause_menu.buttons[0]);if world.is_paused:world.toggle_pause()
	await _advance(world,func() -> bool:return track.health<hp)
	_check(track.visible and track.activity==FieldActor.Activity.RECOVERING and world._combatant(track).available,"restored worker is legally attacked again through original writer")
	await _shot("restored-worker-injured")
	await _advance(world,func() -> bool:return world.search_site(&"cash").searched)
	_check(TransactionReceipt.same(world.task_event,expected.event) and world.weapon_loot.size()==1,"same crate completes exactly one weapon without new pressure")
	var loot: int=world.loot
	world.request_search(&"cash");world.step(1.0/30.0)
	_check(world.loot==loot and world.weapon_loot.size()==1,"completed crate cannot duplicate drop")
	_write("restored-combat.json",{"events":combat,"before_hp":hp,"after_hp":track.health,"event":world.task_event,"weapons":world.weapon_loot})

func _contact(world: Expedition, actor: FieldActor) -> void:
	if not world.battle_drill:
		world.drill_panel.queue_free()
		world.battle_drill=true
		world.drill_panel=BattleDrillPanel.new()
		world.drill_panel.expedition=world
		world._hud.view.add_child(world.drill_panel)
		await _hold(2)
	for button: Button in world.drill_panel.buttons:
		if int(button.get_meta("member_id"))==actor.member_id:await _tap(button)
	_check(world.drill_panel._deployed.has(actor.member_id),"existing explicit contact button deploys original ordinary AI")

func _death(world: Expedition) -> void:
	track=world.survivors[0]
	world.command_move(world.layout.bus_door)
	track.command_path(world.navigation.path_between(track.position,world.search_site(&"cash").door))
	track.cooldown=999.0 # Existing designated-subject fixture, no health or damage changes.
	await _advance(world,func() -> bool:return track.position.distance_to(world.search_site(&"cash").door)<8.0)
	await _contact(world,track)
	await _advance(world,func() -> bool:return track.health<=8.0,12000)
	_check(track.health>0 and track.health<=8,"original AI and persisted writer produce low HP before work")
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.search_site(&"cash").progress>0.0)
	_check(world.search_actor==track and track.visible,"injured member starts actual outdoor work")
	var event: Dictionary=world.task_event.duplicate(true)
	await _advance(world,func() -> bool:return track.permanent_death)
	_check(track.health==0 and world.search_actor==null and world._active_site==null and world.search_site(&"cash").progress==0,"original permanent death immediately unbinds and resets unfinished work")
	_check(not world.searched and world.weapon_loot.is_empty() and TransactionReceipt.same(event,world.task_event),"worker death cannot complete, drop or reset event")
	app.open_pause_menu()
	_check(SortieSnapshot.problem(SortieSnapshot.capture(world),app.progress_session._transaction.recover().receipt).is_empty(),"immediate post-death world authenticates without stale binding")
	await _tap(app.pause_menu.buttons[0]);if world.is_paused:world.toggle_pause()
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.search_site(&"cash").progress>0.2)
	_check(world.search_actor!=track and TransactionReceipt.same(event,world.task_event),"surviving member can restart unfinished crate with same event")
	_write("death.json",{"events":combat,"member":track.member_id,"health":track.health,"permanent_death":track.permanent_death,"event":world.task_event,"work_shots":work_shots})

func _indoor(world: Expedition) -> void:
	world.request_search(&"food")
	await _advance(world,func() -> bool:return world.search_site(&"food").progress>=1.0)
	var actor: FieldActor=world.search_actor
	var hp: float=actor.health
	_check(actor.activity==FieldActor.Activity.SEARCHING and not actor.visible and not actor.take_damage(2,Vector2.RIGHT) and actor.health==hp,"indoor searching retains original hidden damage protection")
	_check(not world._combatant(actor).available and world._nearest_target(world.enemies[0],[actor],INF)==null,"indoor work remains excluded from original combat")
	app.open_pause_menu()
	var exact: Dictionary=SortieSnapshot.capture(world)
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	_check(exact.version==6 and SortieSnapshot.problem(exact,receipt).is_empty(),"indoor work retains authenticatable V6 and old build")
	var bad: Dictionary=exact.duplicate(true);SortieSnapshot._member(bad.survivors,actor.member_id).state.activity=4
	_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"indoor snapshot rejects outdoor activity")
	bad=exact.duplicate(true);SortieSnapshot._member(bad.survivors,actor.member_id).state.visible=true
	_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"indoor snapshot rejects visible protected worker")
	await _tap(app.pause_menu.buttons[0]);if world.is_paused:world.toggle_pause()
	await _advance(world,func() -> bool:return world.search_site(&"food").searched)
	for id: String in _selected.objective.site_ids:
		if not world.search_site(StringName(id)).searched:
			world.request_search(StringName(id));await _advance(world,func() -> bool:return world.search_site(StringName(id)).searched)
	await _finish(world,false)

func _negatives(exact: Dictionary, receipt: Dictionary) -> void:
	var mutations: Array[String]=["hidden","protected","unbound","foreign_site","far","activity","event","site_type"]
	for kind: String in mutations:
		var bad: Dictionary=exact.duplicate(true)
		var worker: Dictionary=SortieSnapshot._member(bad.survivors,int(bad.worker)).state
		match kind:
			"hidden":worker.visible=false
			"protected":worker.activity=2;worker.visible=false
			"unbound":bad.worker=0;bad.active_site=""
			"foreign_site":bad.active_site="food"
			"far":worker.position=[world_far(exact),0]
			"activity":worker.activity=5
			"event":bad.task_event.started=false
			"site_type":bad.active_site=false
		_check(not SortieSnapshot.problem(bad,receipt).is_empty(),"reject outdoor snapshot mutation: "+kind)

func world_far(exact: Dictionary) -> float:
	return float(exact.generated.layout.bounds[2])+1000.0

func _advance(world: Expedition, until: Callable, limit: int=7200) -> void:
	if movie==null:
		await super._advance(world,until,limit)
		return
	for tick: int in range(limit):
		if until.call():return
		world.step(1.0/30.0)
		var actor: FieldActor=world.search_actor if world.search_actor!=null else track if track!=null else world.survivors[0]
		world.camera.position=actor.position+Vector2(200,-120);world.camera._clamp_position();world.camera.force_update_scroll()
		await _frame()
	_check(until.call(),"bounded 1x outdoor checkpoint")

func _files() -> Dictionary:
	var values: Dictionary={}
	for suffix: String in ["",".bak",".txn/binding.json"]:
		var path: String=app.progress_path+suffix
		values[suffix]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	var path: String=app.progress_path+".txn/journal"
	for folder: String in DirAccess.get_directories_at(path):
		if folder.begins_with(".stage"):continue
		values[folder]=FileAccess.get_sha256(path.path_join(folder+"/record.json"))
	return values
