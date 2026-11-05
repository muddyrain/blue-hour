extends "res://tests/build_flow.gd"
## One additional two-action branch for ACK retry and actual rescue inheritance.
func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _menu(0)
	var offers: Array=app.mission_select.daily_offers
	var slot: int=0
	for i: int in range(offers.size()):
		if offers[i].type=="equipment": slot=i
	var world: Expedition=await _start(slot)
	world.request_search(&"cash")
	await _until(world,func()->bool:return world.search_site(&"cash").searched)
	await _extract(world)
	var proposed: Array=app._pending_settlement.journey.build.owned.duplicate()
	_check(proposed.size()==2 and app.camp_snapshot().journey.build.owned.is_empty(),"real return preview holds two unbanked items")
	app.progress_session.fault_hook=func(point:String)->Error:return ERR_CANT_CREATE if point=="before_commit_receipt" else OK
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app._progress_blocked and app.camp_snapshot().journey.build.owned.is_empty(),"failed ACK cannot expose unconfirmed item inventory")
	app.open_mission_select()
	_check(not app.mission_select.visible,"failed ACK blocks next action")
	app.progress_session.fault_hook=Callable()
	app.return_to_title()
	_check(not app._progress_blocked and app.camp_snapshot().journey.build.owned==proposed,"same frozen retry confirms two items once")
	var exact: String=FileAccess.get_sha256(app.progress_path)
	app.return_to_title()
	_check(FileAccess.get_sha256(app.progress_path)==exact,"duplicate confirmation preserves exact camp bytes")
	app.open_loadout()
	app.equip_build_item(0,proposed[0]);app.equip_build_item(1,proposed[1])
	app.equip_build_item(0,"")
	_check(app.camp_snapshot().journey.build.slots==["",proposed[1]],"legal unload preserves inventory")
	app.equip_build_item(0,proposed[0])
	app.close_loadout()
	await _menu(1)
	offers=app.mission_select.daily_offers
	slot=-1
	for i: int in range(offers.size()):
		if offers[i].type=="rescue": slot=i
	_check(slot>=0,"fixed sample second action offers legal rescue")
	if slot<0:return
	world=await _start(slot)
	var target: RescueTarget=world.rescue_target
	target.request()
	await _until(world,func()->bool:return target.status=="IN_FIELD_JOINED")
	var joined: FieldActor=world.survivors.filter(func(a:FieldActor)->bool:return a.member_id==world.candidate_id())[0]
	var profile: Dictionary=SurvivorRoster.member(world._setup_crew,joined.member_id)
	var factors: Dictionary=BuildItems.factors(world.supply.generated.build.slots)
	_check(joined.speed==world.tuning.survivor_speed*TraitRules.factor(profile,"move")*factors.move,"real rescued actor inherits squad move exactly after Trait")
	_check(joined.magazine.reload_factor==factors.reload and joined.weapon_definition.damage==WeaponModifiers.effective(WeaponInventory.for_member(FieldJoinRules.context(app.progress_session._transaction.recover().receipt),joined.member_id)).damage*factors.damage,"actual rescued weapon and reload inherit frozen passives")
	world.toggle_pause()
	_check(app.progress_session.preview_suspend(SortieSnapshot.capture(world)).error==OK,"actual rescued inherited build remains authenticatable")
