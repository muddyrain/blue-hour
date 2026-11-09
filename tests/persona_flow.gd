extends "res://tests/power_flow.gd"
## Fresh isolated normal owners. Recorded segments advance exactly one 1/30s step/frame.
var legacy_mode: bool=false
var original_persona: Dictionary={}

func _menu(_count: int=0) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible,"normal bus opens signed candidates")
	for offer: Dictionary in app.mission_select.daily_offers: _check(DailyActions.problem(offer).is_empty(),"explicit generated mode authenticates")

func _journey() -> void:
	legacy_mode="--flow-legacy-persona" in OS.get_cmdline_user_args()
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	var initial: Dictionary=app.camp_snapshot()
	_check(PersonaState.enabled(initial)!=legacy_mode and BuildState.problem(initial).is_empty(),"normal new root selects explicit old or new build")
	await _menu()
	var world: Expedition=await _start(_gear_slot())
	if world==null:return
	_check(world.setup_problem.is_empty(),"new actor construction has valid identity")
	if not legacy_mode:
		for actor: FieldActor in world.survivors:
			var item: Dictionary=WeaponInventory.for_member(world.field_departure,actor.member_id)
			var damage: float=WeaponModifiers.effective(item).damage*PersonaState.factor(world.supply.generated,actor.member_id,"ranged")
			_check(is_equal_approx(actor.weapon_definition.damage,damage),"actual starter gun uses owner's persona exactly once")
		world._hud.view.open_persona(2)
		if capture_caption!=null:capture_caption.text="正常出击 · 自动界面输入 · 关键片段1× · 非物理输入"
		recording=true
		await _hold(180)
		await _shot("field-persona")
		var goal_before: Vector2=world.goal
		var zoom_before: Vector2=world.camera.zoom
		var details: PersonaDetails=world._hud.view.persona_details
		for kind: int in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_WHEEL_DOWN]:
			var click: InputEventMouseButton=InputEventMouseButton.new();click.button_index=kind;click.pressed=true;click.position=details.get_global_rect().get_center()
			viewport.push_input(click,true)
			world.step(1.0/30.0);await _frame()
		_check(world.goal==goal_before and world.camera.zoom==zoom_before,"details mouse/wheel do not reach map")
		for key: Key in [KEY_Q,KEY_E,KEY_3]:await _key(key)
		_check(world.powers.accepted.is_empty() and not world.support_aiming,"detail focus blocks Q E 3")
		var elapsed_before: float=world.elapsed
		await _key(KEY_SPACE)
		_check(world.is_paused,"Space explicitly pauses from detail")
		await _key(KEY_SPACE)
		_check(not world.is_paused,"Space explicitly resumes from detail")
		await _key(KEY_ESCAPE)
		_check(not details.visible and not app.pause_menu.root.visible,"Esc closes details before menu")
		world.request_search(&"cash")
		for i: int in range(390):world.step(1.0/30.0);await _frame()
		recording=false
		_check(world.elapsed>elapsed_before,"open detail did not implicitly pause simulation")

	await _collect(world)
	world.command_move(world.layout.bus_door)
	await _until(world,func()->bool:return events.any(func(e:Dictionary)->bool:return e.get("kind")=="shot" and e.get("member_id")==2))
	await _bank(world)
	if app._progress_blocked:return
	if not legacy_mode:
		_check(TransactionReceipt.same(initial.journey.build.persona,app.camp_snapshot().journey.build.persona),"real return preserves all five fixed recipes")
		var shot: bool=false
		for event: Dictionary in events:
			if event.get("kind")=="shot" and event.get("member_id")==2:
				shot=true
				_check(is_equal_approx(event.damage,WeaponInventory.definition(event.weapon_id).damage*1.15),"natural field shot proves ranged owner damage")
				break
		_check(shot,"normal first sortie contains actual ranged-persona combat")
	app.open_loadout();await _hold(3)
	for index: int in range(app.loadout_panel.items.item_count):
		var identity: String=app.loadout_panel.items.get_item_metadata(index)
		if identity.contains(":weapon:"):
			app.loadout_panel.items.select(index);app.loadout_panel._select(index)
			if app.loadout_panel.repair_button.disabled==false:
				await _tap(app.loadout_panel.repair_button);await _tap(app.loadout_panel.confirmation.get_ok_button())
			await _tap(app.loadout_panel.equip_by_id[1])
			_check(WeaponInventory.for_member(app.camp_snapshot(),1).instance_id==identity,"legally acquired weapon equips through original inventory owner")
			break
	var owned: Array=app.camp_snapshot().journey.build.powers.owned
	_check(owned.size()==1,"first real gear return grants one original ability")
	if owned.is_empty():return
	await _tap(app.loadout_panel.power_panel.choices[owned[0]])
	equipped=owned[0]
	await _tap(app.loadout_panel.back_button)
	# Earn training food through the next real supply action. Initial rations fed
	# the first two people; no test grants food or accepts a starvation casualty.
	await _menu()
	var food_slot: int=0
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].food>app.mission_select.daily_offers[food_slot].food:food_slot=i
	world=await _start(food_slot)
	if world==null:return
	await _collect(world);await _bank(world)
	if app._progress_blocked:return
	if not legacy_mode:
		original_persona=app.camp_snapshot().journey.build.persona.duplicate(true)
		app.open_roster();await _hold(6)
		_check(app.roster_panel.persona_details.visible,"real roster presents unified detail")
		var rename_before: Dictionary=app.camp_snapshot().journey.build.persona.duplicate(true)
		var original_name: String=SurvivorRoster.member(app.crew,1).call_sign
		app.roster_panel.name_edit.text="夜行者"
		await _tap(app.roster_panel.save_button)
		_check(SurvivorRoster.member(app.crew,1).call_sign=="夜行者" and TransactionReceipt.same(rename_before,app.camp_snapshot().journey.build.persona),"original call-sign editor remains reachable without changing identity recipe")
		app.roster_panel.name_edit.text=original_name
		await _tap(app.roster_panel.save_button)
		recording=true
		if capture_caption!=null:capture_caption.text="正常新旅程 · 自动界面输入 · 关键片段1× · 非物理输入"
		await _hold(90)
		app.roster_panel.persona_details.scroll.ensure_control_visible(app.roster_panel.persona_details.weapon_label)
		await _hold(120);await _shot("camp-persona");recording=false
		_check(app.roster_panel.persona_details.scroll.size.y>=140.0,"real camp detail keeps a readable scroll area")
		# Detail's training action is only a route to the original food transaction.
		await _tap(app.roster_panel.persona_details.training_button)
	else:app.open_training();await _hold(3)
	_check(app.training_panel.visible,"original training panel is reachable")
	await _tap(app.training_panel.member_buttons[1])
	var before: Dictionary=app.camp_snapshot()
	await _tap(app.training_panel.train_button)
	await _tap(app.training_panel.confirmation.get_ok_button())
	_check(app.food==before.food-1 and SurvivorRoster.member(app.crew,1).growth.trait.progress==SurvivorRoster.member(before.crew,1).growth.trait.progress+1,"original one-food quote commits exactly one progress atomically")
	var trained: Dictionary=app.camp_snapshot()
	var rejected: Dictionary=app.progress_session.edit(trained,{"kind":"train_trait","member_id":99})
	_check(not rejected.get("ok",false) and TransactionReceipt.same(trained,app.camp_snapshot()),"invalid original training request has no visible side effects")
	await _tap(app.training_panel.back_button)

	await _menu()
	var checkpoint_slot: int=_gear_slot()
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].type=="rescue":checkpoint_slot=i
	world=await _start(checkpoint_slot)
	if world==null:return
	world.request_search(&"cash")
	for site: Expedition.SearchSite in world.sites:
		if site.id!=&"cash":world.request_search(site.id);break
	await _until(world,func()->bool:return world.elapsed>=8.0)
	_check(world.search_assignments.ordered().size()==2,"two real buildings own independent jobs")
	_check(world.request_power(),"original ability activation accepts with live jobs")
	_check(equipped=="speed_boost_v1" and SpecialPowers.remaining(world.powers,world.elapsed)>0,"cross-PID point has actual active speed boost")
	app.open_pause_menu();await _hold(2)
	var captured: Dictionary=SortieSnapshot.capture(world)
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	_check(captured.version==(13 if legacy_mode else 14) and SortieSnapshot.problem(captured,receipt).is_empty(),"explicit world version and source validate before suspend")
	_write("checkpoint.json",{"encoded":RecordEncoding.stringify(captured),"fingerprint":RecordEncoding.fingerprint(captured),"pid":OS.get_process_id(),"legacy":legacy_mode})
	var oracle_file: FileAccess=FileAccess.open(output.path_join("oracle.json"),FileAccess.WRITE)
	oracle_file.store_string(RecordEncoding.stringify({"world":captured,"receipt":receipt,"camp":app.camp_snapshot()}));oracle_file.close()
	app.suspend_sortie();await _hold(3)
	_check(app.expedition==null and app._requires_continue,"original durable suspend completed")

func _resume() -> void:
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	legacy_mode=prior.legacy
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition=app.expedition
	_check(world!=null,"new PID restores original world: "+app._progress_message)
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	_check(prior.pid!=OS.get_process_id() and RecordEncoding.fingerprint(SortieSnapshot.capture(world))==prior.fingerprint,"new PID exactly restores persona/source jobs weapons work and temporary clocks")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:world.toggle_pause()
	var damage_before: Array=[]
	for actor: FieldActor in world.survivors:damage_before.append([actor.weapon_definition.damage,actor.speed,actor.magazine.reload_factor if actor.magazine!=null else 0.0])
	# Release one worker only, then publish original full-world support replacement.
	var one: Dictionary=world.search_assignments.ordered()[0]
	world.request_search(StringName(one.site_id))
	var caller: FieldActor=world.survivors.filter(func(a:FieldActor)->bool:return a.visible and a.health>0)[0]
	var point: Vector2=Vector2.INF
	for offset: Vector2 in [Vector2.DOWN*40,Vector2.RIGHT*40,Vector2.LEFT*40,Vector2.UP*40]:
		if not world.support_plan_airstrike(caller.position+offset).is_empty():point=caller.position+offset;break
	var before: Dictionary=world.support_world()
	_check(point.is_finite() and world.request_airstrike(point),"original support transaction replaces full world")
	var damage_after: Array=[]
	for actor: FieldActor in world.survivors:damage_after.append([actor.weapon_definition.damage,actor.speed,actor.magazine.reload_factor if actor.magazine!=null else 0.0])
	_check(TransactionReceipt.same({"v":damage_before},{"v":damage_after}) and TransactionReceipt.same(world.powers,before.powers) and TransactionReceipt.same(world.search_assignments.snapshot(),before.jobs),"support reconstruction never stacks damage speed reload or loses jobs/ability")
	if not legacy_mode:
		world._hud.view.open_persona(caller.member_id)
		recording=true
		if capture_caption!=null:capture_caption.text="新进程恢复与原支援事务 · 自动输入 · 1×"
		await _hold(210);recording=false
		world._hud.view.persona_details.close()
	var rescued_id: int=world.candidate_id() if world.rescue_target!=null else 0
	if not legacy_mode and rescued_id>0:
		await _rescue(world)
	await _collect(world);await _bank(world)
	if not legacy_mode and rescued_id>0:
		_check(not SurvivorRoster.member(app.crew,rescued_id).is_empty(),"actual rescued stable member returns to camp")
		return
	if legacy_mode:
		_check(not PersonaState.enabled(app.camp_snapshot()) and not app.camp_snapshot().journey.build.has("persona"),"old world13 returns to original camp without migration")
		return
	original_persona=app.camp_snapshot().journey.build.persona.duplicate(true)
	await _menu()
	var rescue_slot: int=-1
	for index: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[index].type=="rescue":rescue_slot=index
	_check(rescue_slot>=0,"normal frozen offers expose actual rescue")
	if rescue_slot<0:return
	world=await _start(rescue_slot)
	var candidate: int=world.candidate_id()
	var recipe: Dictionary=PersonaState.recipe(world.supply.generated,candidate)
	_check(not world.rescue_target.revealed() and not world.rescue_target.npc.visual.visible and not recipe.is_empty(),
		"pending rescue keeps the original fixed recipe and conceals the actor")
	world.rescue_target.request()
	await _until(world,func()->bool:return world.rescue_target.progress>=RescueTarget.SECONDS)
	world.rescue_target.request()
	await _until(world,func()->bool:return world.field_joins.size()==1)
	var joined: FieldActor=world.search_member(candidate)
	_check(joined!=null and world.rescue_target.revealed() and joined.visual.visible and PersonaState.recipe(world.supply.generated,candidate)==recipe,
		"actual rescue reveals the actor with the same stable identity recipe")
	await _collect(world);await _bank(world)
	_check(not SurvivorRoster.member(app.crew,candidate).is_empty() and TransactionReceipt.same(original_persona,app.camp_snapshot().journey.build.persona),"real rescue returns unchanged recipe through original admission and settlement")

func _bank(world: Expedition) -> void:
	await _extract(world)
	if app._progress_blocked:
		_write("failure-owner.json",{"reason":app.progress_session._problem,"state":app.progress_session.inspect(),"active_base":app.progress_session._active_base,"active_rules":app.progress_session._active_rules,"reports":reports})
		_check(false,"real finish: "+app.progress_session._problem)
		return
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(not app._progress_blocked and BuildState.problem(app.camp_snapshot()).is_empty(),"real original confirmation banks full immutable build")

func _rescue(world: Expedition) -> void:
	var candidate: int=world.candidate_id()
	var recipe: Dictionary=PersonaState.recipe(world.supply.generated,candidate)
	var original: Dictionary=world.field_departure.journey.build.persona.duplicate(true)
	_check(not world.rescue_target.revealed() and not world.rescue_target.npc.visual.visible and not recipe.is_empty(),
		"continued pending rescue retains a fixed identity behind the anonymous marker")
	# Cancel jobs through original intentions to free a real rescuer.
	for job: Dictionary in world.search_assignments.ordered():world.request_search(StringName(job.site_id))
	world.rescue_target.request()
	await _until(world,func()->bool:return world.rescue_target.progress>=RescueTarget.SECONDS)
	world.rescue_target.request()
	await _until(world,func()->bool:return world.field_joins.size()==1)
	_check(world.search_member(candidate)!=null and world.rescue_target.revealed()
		and world.rescue_target.npc.visual.visible and PersonaState.recipe(world.supply.generated,candidate)==recipe
		and TransactionReceipt.same(original,world.field_departure.journey.build.persona),
		"real ten-second assistance reveals the stable recipe after confirmation")

func _key(code: Key) -> void:
	for down: bool in [true,false]:
		var event: InputEventKey=InputEventKey.new();event.keycode=code;event.pressed=down
		viewport.push_input(event,true)
		if recording and is_instance_valid(app.expedition):app.expedition.step(1.0/30.0)
		await _frame()
