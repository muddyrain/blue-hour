extends "res://tests/world_flow.gd"
## Normal UI V3 sizes; exact suspended medium and large partial unique banking.
var _working: StringName
var runtime_usec: Array[int]=[]
var freeze_usec: Array[int]=[]
func _advance(world: Expedition, until: Callable, limit: int=5400) -> void:
	for index: int in range(limit):
		if until.call():return
		var was: int=world.phase
		var began: int=Time.get_ticks_usec()
		world.step(1.0/30.0)
		var took: int=Time.get_ticks_usec()-began
		if was!=Expedition.Phase.FINISHED and world.phase==Expedition.Phase.FINISHED:freeze_usec.append(took)
		elif was!=Expedition.Phase.FINISHED:runtime_usec.append(took)
		if index%6==0:await _frame()
	_check(until.call(),"bounded V3 checkpoint")
func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	var offers: Array[Dictionary]=await _menu()
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var original: String=WeaponInventory.for_member(app.camp_snapshot(),1).instance_id
	var other: String=WeaponInventory.for_member(app.camp_snapshot(),2).instance_id
	app.equip_weapon(1,other)
	_check(WeaponInventory.for_member(app.camp_snapshot(),1).instance_id==other,"existing equip transaction applied")
	app.equip_weapon(1,original);app.close_loadout()
	_check(TransactionReceipt.same({"v":offers},{"v":await _menu()}),"same day browsing/equip preserves all candidates")
	await _start("medium")
	var world: Expedition=app.expedition
	var first: StringName=&"food" if world.supply.food_reward>0 else &"cash"
	world.request_search(first)
	await _advance(world,func() -> bool:return world.search_site(first).searched)
	for site: Expedition.SearchSite in world.sites:
		if site.id!=first:_working=site.id;break
	world.request_search(_working)
	await _advance(world,func() -> bool:return world.search_site(_working).progress>=3)
	app.open_pause_menu();await _hold(3)
	var exact: Dictionary=SortieSnapshot.capture(world)
	_check(not exact.is_empty() and exact.version==5,"medium has one complete/another working under explicit V5 world")
	_write("world-exact.json",{"encoded":RecordEncoding.stringify(exact),"hash":SurvivalContracts.fingerprint(exact),"selected":_selected,"camp":_before,"working":String(_working)})
	await _tap(app.pause_menu.buttons[4])
	_check(app.expedition==null and app._requires_continue,"existing suspend ACK leaves no banked reward")
	_write("daily-state.json",{"menu_history":menu_history})
func _resume() -> void:
	var phase_name: String=output.get_file()
	var previous: String={"restore":"first","large":"restore","small":"large","final":"small"}[phase_name]
	var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(previous+"/report.json")))
	_check(int(old.pid)!=OS.get_process_id(),"new process identity")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	if phase_name=="restore":
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/world-exact.json")))
		var world: Expedition=app.expedition
		_check(world!=null,"medium restored without a new map")
		if world==null:return
		world.set_physics_process(false);world.set_process(false)
		var actual: Dictionary=SortieSnapshot.capture(world)
		var exact: Dictionary=RecordEncoding.unpack(JSON.parse_string(expected.encoded)).payload
		_check(TransactionReceipt.same(actual,exact) and SurvivalContracts.fingerprint(actual)==expected.hash,"exact layout/sites/workers/actors/enemies/carry/clock restored")
		_check(world.bus_view.stage=="exploring" and world.is_paused,"continue does not replay arrival")
		_selected=expected.selected;_before=expected.camp
		await _shot("restored-medium")
		await _tap(app.pause_menu.buttons[0])
		if world.is_paused:world.toggle_pause()
		world.request_search(StringName(expected.working)) # Cancel unfinished work via original intention.
		await _finish(world,false)
	else:
		_check(TransactionReceipt.same(old.camp,app.camp_snapshot()),"restart preserves camp resources/date/crew/weapons")
		var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(previous+"/daily-state.json")))
		var current: Array[Dictionary]=await _menu()
		_check(TransactionReceipt.same({"v":current},{"v":prior.menu_history[-1].offers}),"normal restart preserves same-day candidates")
		if phase_name=="final":
			await _shot("final-camp-candidates");return
		await _start(phase_name)
		var world: Expedition=app.expedition
		var first: StringName=&"food" if world.supply.food_reward>0 else &"cash"
		world.request_search(first)
		await _advance(world,func() -> bool:return world.search_site(first).searched)
		_check(world._searched_count()<world.sites.size(),"large/small actual partial search leaves unclaimed sites")
		await _finish(world,false)
	await _menu()
	runtime_usec.sort()
	_write("performance.json",{"samples":runtime_usec.size(),"step_usec_median":runtime_usec[runtime_usec.size()/2],"step_usec_p95":runtime_usec[int(runtime_usec.size()*0.95)],"step_usec_max":runtime_usec[-1],"freeze_step_usec":freeze_usec,"freeze_includes":"existing freeze/receipt validation/serialization/durable preview","display_fps":"NOT_MEASURED","survivors":app.crew.size()})
	_write("daily-state.json",{"menu_history":menu_history,"selected":_selected,"reports":journey_reports})
func _start(size: String) -> void:
	_before=app.camp_snapshot()
	var offers: Array[Dictionary]=app.mission_select.daily_offers
	var slot: int=-1
	for i: int in range(offers.size()):
		if offers[i].layout["size"]==size:slot=i;_selected=offers[i].duplicate(true);break
	_check(slot>=0,"requested map size available: "+size)
	if slot<0:return
	await _mark("select-"+size)
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
	_check(receipt.rules.data_version==4 and TransactionReceipt.same(receipt.rules.mission.generated,_selected),"versioned authority binds selected task before gameplay")
	for actor: FieldActor in world.survivors:
		_check(actor.trait_shot_factor==TraitRules.factor(SurvivorRoster.member(_before.crew,actor.member_id),"shot"),"original personal trait applies to stable identity")
	await _hud_sample(world)
	await _shot("map-day-%d"%app.day)

func _finish(world: Expedition, fault: bool) -> void:
	var expected: Dictionary = WorldSites.carry(_selected.sites,WorldSites.facts(world),world.sortie_id,true,_selected)
	_check(world._searched_count()>=1 and world.loot==expected.loot and world.food_loot==expected.food and world.weapon_loot.size()==expected.weapons.size(),"multiple real independent sites agree with partial task budget")
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
