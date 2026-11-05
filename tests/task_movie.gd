extends "res://tests/task_flow.gd"
## Continuous final renderer capture: one real simulation tick per encoded frame.
func _journey() -> void:
	capture_caption.text="Mac 离屏实机 · 原业务输入 · 行动模拟1× · 非显示器FPS"
	await _tap(app._home_button); await _tap(app._new_game_confirmation.get_ok_button())
	await _menu(); await _start("airdrop")
	var world: Expedition = app.expedition
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.search_site(&"cash").searched)
	await _shot("airdrop-complete")
	var event: Dictionary = world.task_event.duplicate(true)
	world.request_search(&"food")
	await _advance(world,func() -> bool:return world.search_site(&"food").searched)
	_check(TransactionReceipt.same(event,world.task_event) and world._searched_count()<world.sites.size(),"filmed optional search preserves once-only event and partial budget")
	await _finish(world,false)
	await _hold(90)
	_write("movie-facts.json",{"frames":frames,"simulation_rate":1,"task":_selected,"event":event,"freeze":task_freezes,"camp":app.camp_snapshot(),"physical_os":"NOT_VERIFIED"})

func _advance(world: Expedition, until: Callable, limit: int = 7200) -> void:
	for tick: int in range(limit):
		if until.call(): return
		if world.phase==Expedition.Phase.FINISHED and not world.bus_view.running(): break
		var was: int = world.phase
		var started: int = Time.get_ticks_usec()
		world.step(1.0/30.0)
		if was!=Expedition.Phase.FINISHED and world.phase==Expedition.Phase.FINISHED:
			task_freezes.append({"step_usec":Time.get_ticks_usec()-started,"size":_selected.layout["size"],"survivors":world.survivors.size(),"enemies":world.enemies.size(),"buildings":world._buildings.size(),"elapsed":world.elapsed})
		var point: Vector2 = world.search_actor.position if world.search_actor!=null else world.survivors[0].position
		if world.bus_view.running(): point=world._bus_sprite.position
		world.camera.position=point+Vector2(200,-120); world.camera._clamp_position(); world.camera.force_update_scroll()
		await _frame()
	_check(until.call(),"bounded 1x task checkpoint")

func _write(name: String, value: Dictionary) -> void:
	if name=="report.json": value.input="viewport Enter and original intentions; one 1/30s simulation tick per encoded frame, offscreen GL renderer"
	super._write(name,value)
