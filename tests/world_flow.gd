extends "res://tests/playable_flow.gd"
## Real default daily journey, stored map suspend/new PID, four-body HUD and banking.
var journey_reports: Array[Dictionary]=[]
var menu_history: Array[Dictionary]=[]
var _before: Dictionary={}
var _selected: Dictionary={}

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree(),"normal default creates existing durable camp")
	var offers: Array[Dictionary]=await _menu()
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"training"])
	await _tap(app.training_panel.member_buttons[1])
	await _tap(app.training_panel.train_button)
	await _tap(app.training_panel.confirmation.get_ok_button())
	await _tap(app.training_panel.back_button)
	_check(TransactionReceipt.same({"v":offers},{"v":await _menu()}),"real training and menu reopen do not reroll")
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var original: String=WeaponInventory.for_member(app.camp_snapshot(),1).instance_id
	var other: String=WeaponInventory.for_member(app.camp_snapshot(),2).instance_id
	app.equip_weapon(1,other)
	_check(WeaponInventory.for_member(app.camp_snapshot(),1).instance_id==other,"real equip transaction applied")
	app.equip_weapon(1,original)
	app.close_loadout()
	_check(TransactionReceipt.same({"v":offers},{"v":await _menu()}),"real equip/swap back preserves daily candidates")
	await _start("supply")
	var world: Expedition=app.expedition
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.searched)
	world.request_search(&"food")
	await _advance(world,func() -> bool:return world._food_site.searched)
	world.request_search(&"cash_2")
	await _advance(world,func() -> bool:return world.search_actor!=null and world.search_site(&"cash_2").progress>=3)
	app.open_pause_menu()
	await _hold(3)
	var captured: Dictionary=SortieSnapshot.capture(world)
	_check(not captured.is_empty(),"real generated action paused for original suspend")
	_write("world-exact.json",{"encoded":RecordEncoding.stringify(captured),"hash":SurvivalContracts.fingerprint(captured),"selected":_selected,"camp":_before})
	await _tap(app.pause_menu.buttons[4])
	_check(app.expedition==null and app._requires_continue,"original suspend ACK leaves field without rewards")
	_write("daily-state.json",{"menu_history":menu_history,"selected":_selected})

func _resume() -> void:
	var phase_name: String=output.get_file()
	var previous: String={"restore":"first","second":"restore","third":"second","fourth":"third","final":"fourth"}[phase_name]
	var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(previous+"/report.json")))
	_check(int(old.pid)!=OS.get_process_id(),"actual new process")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	if phase_name=="restore":
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/world-exact.json")))
		var world: Expedition=app.expedition
		_check(world!=null,"same generated battlefield reconstructed")
		if world==null:return
		world.set_physics_process(false);world.set_process(false)
		var actual: Dictionary=SortieSnapshot.capture(world)
		var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload
		_check(SurvivalContracts.fingerprint(actual)==expected.hash and TransactionReceipt.same(actual,exact),"layout/actors/search/carry/enemies/clock restore exactly before movement")
		_selected=expected.selected;_before=expected.camp
		_check(world.is_paused,"restored original field remains paused")
		await _shot("restored-map")
		await _tap(app.pause_menu.buttons[0])
		await _shot("restored-field")
		if world.is_paused:world.toggle_pause()
		await _advance(world,func() -> bool:return world.search_site(&"cash_2").searched)
		await _finish(world,false)
		await _menu()
		_write("daily-state.json",{"menu_history":menu_history,"selected":_selected,"reports":journey_reports})
		return
	_check(TransactionReceipt.same(old.camp,app.camp_snapshot()),"camp date/economy/crew/weapons restored exactly")
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(previous+"/daily-state.json")))
	var current: Array[Dictionary]=await _menu()
	_check(TransactionReceipt.same({"v":current},{"v":prior.menu_history[-1].offers}),"same-day candidate contents survive new PID")
	if phase_name=="final":
		_check(app.crew.size()==4 and current.all(func(v: Dictionary) -> bool:return v.type!="rescue"),"real four-living roster replaces unavailable rescue with valid options")
		await _shot("final-daily")
		_write("daily-state.json",{"menu_history":menu_history})
		return
	var type: String="equipment" if phase_name=="second" else "rescue"
	await _start(type)
	var world: Expedition=app.expedition
	if movie!=null:
		world.request_search(&"cash")
		await _mark("normal-speed-before")
		capture_caption.text="自动输入 · 此段行动模拟1× · 非显示器FPS"
		var normal_start: int=frames
		for tick: int in range(120):
			world.step(1.0/30.0)
			await _frame()
		capture_caption.text="自动输入 · 后续行动模拟6× · 非显示器FPS"
		stages.append({"stage":"normal-speed-segment","video_start":float(normal_start)/30.0,"video_end":float(frames)/30.0,"simulation_ticks":120,"simulation_rate":1})
		await _mark("normal-speed-after")
	if type=="rescue":
		await _tap(world.rescue_target.button)
		await _advance(world,func() -> bool:return not world.field_joins.is_empty())
		_check(world.field_joins.size()==1,"real allowed candidate joins same generated map")
		await _hud_sample(world)
	if world.search_actor==null and not world.searched:world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.searched)
	if world.supply.supports(&"food"):
		world.request_search(&"food")
		await _advance(world,func() -> bool:return world._food_site.searched)
	if type=="rescue":
		for site: Expedition.SearchSite in world.sites:
			if site.kind==&"food" and not site.searched:
				world.request_search(site.id)
				await _advance(world,func() -> bool:return site.searched)
	await _finish(world,phase_name=="second")
	var next: Array[Dictionary]=await _menu()
	_check(not TransactionReceipt.same({"v":current},{"v":next}),"confirmation advances to different next-day candidates")
	_write("daily-state.json",{"menu_history":menu_history,"selected":_selected,"reports":journey_reports})

func _menu() -> Array[Dictionary]:
	if not app.mission_select.visible:await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array[Dictionary]=app.mission_select.daily_offers.duplicate(true)
	_check(offers.size()==3 and offers.any(func(v: Dictionary) -> bool:return v.food>0),"three actual daily cards include food")
	_check(viewport.get_visible_rect().encloses(app.mission_select.cancel_button.get_global_rect()),"daily cancel within normal viewport")
	menu_history.append({"day":app.day,"offers":offers})
	if movie!=null:await _mark("daily-candidates-%d"%app.day)
	await _shot("daily-%d"%app.day)
	return offers

func _start(type: String) -> void:
	_before=app.camp_snapshot()
	var offers: Array[Dictionary]=app.mission_select.daily_offers
	var slot: int=-1
	for i: int in range(offers.size()):
		if offers[i].type==type:slot=i;_selected=offers[i].duplicate(true);break
	_check(slot>=0,"requested real task available: "+type)
	if slot<0:return
	await _mark("select-"+type)
	await _tap(app.mission_select.choices[slot])
	var world: Expedition=app.expedition
	_check(world!=null,"signed daily task enters real generated map")
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	await _advance(world,func() -> bool:return not world.bus_view.running())
	_check(world.elapsed==0,"entry and disembark do not advance battle clock")
	world.finished.connect(func(report: Dictionary) -> void:journey_reports.append(report.duplicate(true)))
	_check(String(world.layout.id)==_selected.layout.id and TransactionReceipt.same(world.supply.generated,_selected),"UI, frozen STARTED rules and actual world share one descriptor")
	var receipt: Dictionary=app.progress_session._transaction.recover().receipt
	_check(receipt.rules.data_version==3 and TransactionReceipt.same(receipt.rules.mission.generated,_selected),"versioned authority binds selected task before gameplay")
	for actor: FieldActor in world.survivors:
		_check(actor.trait_shot_factor==TraitRules.factor(SurvivorRoster.member(_before.crew,actor.member_id),"shot"),"original personal trait applies to stable identity")
	await _hud_sample(world)
	await _shot("map-day-%d"%app.day)

func _finish(world: Expedition, fault: bool) -> void:
	var expected: Dictionary = WorldSites.carry(_selected.sites,WorldSites.facts(world),world.sortie_id,true)
	_check(world._searched_count()>=2 and world.loot==expected.loot and world.food_loot==expected.food and world.weapon_loot.size()==expected.weapons.size(),"multiple real independent sites agree with partial task budget")
	var carry: Dictionary = {"loot":world.loot,"food":world.food_loot,"weapons":world.weapon_loot.duplicate(true)}
	for site: Expedition.SearchSite in world.sites:
		if site.searched: world.request_search(site.id)
	_check(TransactionReceipt.same(carry,{"loot":world.loot,"food":world.food_loot,"weapons":world.weapon_loot}),"completed site reclick never pays twice")
	await _advance(world,func() -> bool:return world.elapsed>=world.tuning.bus_ready_seconds)
	await _tap(world._hud.view._bus_button)
	await _advance(world,func() -> bool:return world.phase==Expedition.Phase.BOARDING)
	await _tap(world._hud.view._bus_button)
	await _advance(world,func() -> bool:return world.phase==Expedition.Phase.FINISHED)
	_check(app.phase==app.Phase.RESULT and world.boarding_status().arrived==world.living_count(),"all actual living members boarded generated bus")
	_check(TransactionReceipt.same(_before,app.camp_snapshot()),"preview does not bank")
	var frozen: Dictionary=app.progress_session.inspect().receipt
	_check(TransactionReceipt.same(frozen.rules.mission.generated,_selected) and frozen.envelope.result.battle.loot==expected.loot and frozen.envelope.result.battle.food==expected.food,"frozen preview uses same task and actual carry")
	_check(world.bus_view.running(),"result frozen before boarding/departure presentation")
	await _advance(world,func() -> bool:return not world.bus_view.running())
	await _mark("result-day-%d"%app.day)
	await _shot("result-day-%d"%app.day)
	if fault:app.progress_session.fault_hook=func(point: String) -> Error:return ERR_CANT_CREATE if point=="before_commit_receipt" else OK
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	if fault:
		_check(app._progress_blocked and TransactionReceipt.same(_before,app.camp_snapshot()),"failed original ACK cannot apply rewards")
		app.open_mission_select()
		_check(app.expedition==null and not app.mission_select.visible,"save failure cannot bypass into another day")
		app.progress_session.fault_hook=Callable()
		await _tap(app._retry_button)
	var camp: Dictionary=app.camp_snapshot()
	_check(camp.day==_before.day+1 and camp.cash==_before.cash+expected.loot and camp.last_day.food_found==expected.food,"unique confirmed camp agrees with selected task and food ledger")
	var hash: String=FileAccess.get_sha256(app.progress_path)
	app.return_to_title()
	_check(hash==FileAccess.get_sha256(app.progress_path) and TransactionReceipt.same(camp,app.camp_snapshot()),"duplicate confirmation cannot claim twice")
	_write("selected.json",_selected)

func _hud_sample(world: Expedition) -> void:
	await _hold(3)
	var hud: C1ExpeditionHud=world._hud.view
	var count: int=world.survivors.size()
	_check(hud.get_node("MissionPanel").size.y<=144,"real %d-person HUD height bounded"%count)
	for row: Dictionary in hud._members:
		if row.box.visible:_check(row.title.get_line_count()==1 and row.health.get_line_count()==1 and row.status.get_line_count()==1,"identity HP status do not wrap")
	_check(viewport.get_visible_rect().encloses(hud._bus_button.get_global_rect()) and viewport.get_visible_rect().encloses(hud._pause_button.get_global_rect()),"core controls remain on screen")
	await _shot("hud-%d"%count)

func _shot(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _hold(2)
	RenderingServer.force_draw()
	viewport.get_texture().get_image().save_png(output.path_join(name+".png"))
