extends "res://tests/campaign_flow.gd"
## Exact reviewed M10 Main bootstrap, minimal world12/camp representatives only.
func _journey() -> void:
	await _tap(app._home_button);await _tap(app._new_game_confirmation.get_ok_button())
	_check(not PowerState.enabled(app.camp_snapshot()),"reviewed M10 bootstrap creates old camp without powers")
	await _tap(app.camp_scene.hotspots[&"bus"])
	var world: Expedition=await _start(0)
	if world==null:return
	world.request_search(&"cash")
	for site: Expedition.SearchSite in world.sites:
		if site.id!=&"cash":world.request_search(site.id);break
	await _until(world,func()->bool:return world.elapsed>=8)
	app.open_pause_menu()
	var value: Dictionary=SortieSnapshot.capture(world)
	_check(value.version==12 and not value.has("powers"),"old world12 keeps exact reviewed fields")
	_write("checkpoint.json",{"fingerprint":RecordEncoding.fingerprint(value),"pid":OS.get_process_id()})
	app.suspend_sortie();await _hold(2)
	_check(app.expedition==null and app._requires_continue,"old original suspend commits unchanged world12")

func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	if output.get_file()=="readback":
		var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("resume/camp.json")))
		_check(TransactionReceipt.same(app.camp_snapshot(),prior.camp) and not PowerState.enabled(app.camp_snapshot()),"old confirmed camp crosses PID without powers or inventory changes")
		_check(DailyActions.offers(app.camp_snapshot()).all(func(v:Dictionary)->bool:return not v.has("powers")),"old camp next offers retain old mode")
		return
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	var world: Expedition=app.expedition
	_check(world!=null,"current candidate reconstructs old world12")
	if world==null:return
	world.set_process(false);world.set_physics_process(false)
	_check(prior.pid!=OS.get_process_id() and RecordEncoding.fingerprint(SortieSnapshot.capture(world))==prior.fingerprint,"world12 full actors/jobs/progress/camera/actions fingerprint remains exact across PID")
	await _tap(app.pause_menu.buttons[0]);if world.is_paused:world.toggle_pause()
	await _extract(world);await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(not app._progress_blocked and not PowerState.enabled(app.camp_snapshot()),"old world returns through original settlement without mode migration")
	_write("camp.json",{"camp":app.camp_snapshot()})
