extends "res://tests/campaign_flow.gd"
## Baseline-owned synthetic short_v1 fixtures. Never migrate or inject an existing profile.
func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(CampaignState.is_short(app.camp_snapshot()) and not app.camp_snapshot().journey.has("build"),"reviewed baseline creates actual old short mode")
	await _menu(0)
	var world: Expedition=await _start(0)
	if output.get_file()=="old-underway":
		world.command_move(world.search_site(&"cash").door)
		await _until(world,func()->bool:return world.elapsed>=12)
		app.open_pause_menu()
		var value: Dictionary=SortieSnapshot.capture(world)
		_write("oracle.json",{"world":RecordEncoding.stringify(value),"fingerprint":RecordEncoding.fingerprint(value),"pid":OS.get_process_id()})
		app.suspend_sortie()
		_check(app._requires_continue and app.expedition==null,"old original owner publishes active world")
	else:
		await _extract(world)
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(not app._progress_blocked and app.settled_sorties==1,"old original return owner confirms camp")
		_write("oracle.json",{"camp":app.camp_snapshot(),"pid":OS.get_process_id()})

func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	var source: String="old-underway" if "underway" in output else "old-complete"
	var oracle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(source+"/oracle.json")))
	_check(oracle.pid!=OS.get_process_id(),"old mode actually crosses PID and candidate")
	if source=="old-underway":
		var world: Expedition=app.expedition
		_check(world!=null,"new candidate resumes old short underway")
		if world==null:return
		world.set_physics_process(false);world.set_process(false)
		_check(RecordEncoding.fingerprint(SortieSnapshot.capture(world))==oracle.fingerprint,"old snapshot identity/HP/ammo/boss remains exact")
		_check(world.supply.generated.version==6 and world.basic_support.snapshot().is_empty(),"old underway receives no support or items")
	else:
		_check(TransactionReceipt.same(app.camp_snapshot(),oracle.camp),"old confirmed camp exact across new candidate")
		_check(not BuildState.enabled(app.camp_snapshot()),"old camp never silently gains build")
		_check(DailyActions.offers(app.camp_snapshot())[0].version==6,"next old action remains V6 short mode")
