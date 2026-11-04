extends "res://tests/rogue_compat.gd"
func _journey() -> void:
	mode=output.get_file()
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	app.progress_session.daily_actions=false # Explicit synthetic old-version fixture; no normal profile.
	for offer: Dictionary in WorldActions.offers(app.camp_snapshot()):
		if offer.type=="supply":app._select_mission(WorldActions.supply(offer));break
	var world: Expedition=app.expedition;world.set_physics_process(false);world.set_process(false);world.bus_view.skip()
	if mode=="old-suspend":
		world.request_search(&"cash")
		await _advance(world,func() -> bool:return world.search_progress>=3)
		app.open_pause_menu()
		var snapshot: Dictionary=SortieSnapshot.capture(world)
		_check(snapshot.version==4 and snapshot.generated.version==2,"synthetic previous WORLD-01 V2 action / V4 snapshot")
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
	_write("oracle.json",{"state":current.state,"camp":app.camp_snapshot(),"receipt":current.receipt,"head":current.hash,"originals":_files()})
