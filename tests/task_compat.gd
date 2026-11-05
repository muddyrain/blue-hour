extends "res://tests/rogue_compat.gd"
func _journey() -> void:
	mode=output.get_file()
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	app.progress_session.daily_actions=false # Explicit synthetic old-version fixture; no normal profile.
	for offer: Dictionary in NeighborhoodActions.offers(app.camp_snapshot()):
		if offer.type=="supply":app._select_mission(NeighborhoodActions.supply(offer));break
	var world: Expedition=app.expedition;world.set_physics_process(false);world.set_process(false);world.bus_view.skip()
	if mode=="old-suspend":
		world.request_search(&"cash")
		await _advance(world,func() -> bool:return world.search_progress>=3)
		app.open_pause_menu()
		var snapshot: Dictionary=SortieSnapshot.capture(world)
		_check(snapshot.version==5 and snapshot.generated.version==3,"synthetic previous WORLD-02 V3 action / V5 snapshot")
		await _tap(app.pause_menu.buttons[4])
		_check(app.progress_session.inspect().state=="SUSPENDED","legacy fixed-world original suspend saved")
	else:
		world.request_search(&"cash");await _advance(world,func() -> bool:return world.searched)
		world.request_search(&"food");await _advance(world,func() -> bool:return world._food_site.searched)
		await _advance(world,func() -> bool:return world.elapsed>=world.tuning.bus_ready_seconds)
		world.request_bus_action();await _advance(world,func() -> bool:return world.phase==Expedition.Phase.BOARDING)
		world.request_bus_gather();await _advance(world,func() -> bool:return world.phase==Expedition.Phase.FINISHED)
		await _advance(world,func() -> bool:return not world.bus_view.running())
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(app.settled_sorties==1 and app.day==3,"synthetic legacy actual completed camp")
	var current: Dictionary=app.progress_session.inspect()
	if mode=="old-complete":
		var changed: Dictionary=current.receipt.duplicate(true)
		changed.envelope.result.camp.last_day.task={"version":1,"task_id":"f".repeat(64),"type":"supply","completed":1,"total":1,"status":"COMPLETED"}
		changed.envelope.result_hash=SurvivalContracts.fingerprint(changed.envelope.result)
		_check(TransactionReceipt.problem(changed).contains("TASK_RESULT_VERSION"),"old rules cannot authenticate an injected new task summary")
	_write("oracle.json",{"state":current.state,"camp":app.camp_snapshot(),"receipt":current.receipt,"head":current.hash,"originals":_files(),"exact_world":RecordEncoding.stringify(current.receipt.envelope.world) if mode=="old-suspend" else ""})

func _resume() -> void:
	mode=output.get_file()
	if mode!="new-continue":
		await super._resume()
		return
	var before: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("old-suspend/oracle.json")))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition=app.expedition
	_check(world!=null,"previous V3 underway continues through original claim")
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	_check(world.is_paused and TransactionReceipt.same(SortieSnapshot.capture(world),RecordEncoding.unpack(JSON.parse_string(before.exact_world)).payload),"previous layout/carry/progress/actors preserved exactly")
	_check(app.progress_session._transaction.recover().receipt.phase=="RESUME_CLAIMED","old underway receives exactly one ordinary claim")
