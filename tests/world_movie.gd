extends "res://tests/world_flow.gd"
## One continuous native 1x simulation film. No reward, HP, speed, clock or actor injection.
var simulation_samples: Array[int] = []
func _advance(world: Expedition, until: Callable, limit: int = 5400) -> void:
	for index: int in range(limit):
		if until.call(): return
		world.step(1.0/30.0)
		simulation_samples.append(world.last_simulation_usec)
		await _frame()
	_check(until.call(),"bounded 1x checkpoint")
func _journey() -> void:
	capture_caption.text="Windows 独立桌面 · 自动输入 · 行动模拟1× · 非显示器FPS"
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _menu()
	_before=app.camp_snapshot()
	var slot: int = 0
	for i: int in range(3):
		if app.mission_select.daily_offers[i].type=="supply": slot=i
	_selected=app.mission_select.daily_offers[slot].duplicate(true)
	await _tap(app.mission_select.choices[slot])
	var world: Expedition = app.expedition
	world.set_physics_process(false); world.set_process(false)
	world.camera.set_process(false)
	# Follow the real vehicle through the full world-coordinate route.
	while world.bus_view.running():
		world.camera.position=world._bus_sprite.position+Vector2(0,-180)
		world.camera._clamp_position(); world.camera.force_update_scroll()
		world.step(1.0/30.0); await _frame()
	await _shot("arrival")
	world.request_search(&"food")
	while not world._food_site.searched:
		if world.search_actor!=null:
			world.camera.position=world.search_actor.position+Vector2(0,-160)
			world.camera._clamp_position(); world.camera.force_update_scroll()
		world.step(1.0/30.0); simulation_samples.append(world.last_simulation_usec); await _frame()
	await _shot("searched-building")
	# A real navigable point behind a building exercises roof occlusion without moving actors directly.
	var building: Dictionary = world.layout.world_data.entities[1]
	var behind: Vector2 = Vector2(building.rect[0]+building.rect[2]/2,building.rect[1]-32)
	world.command_move(behind)
	for tick: int in range(150):
		world.camera.position=world.survivors[0].position+Vector2(0,-160)
		world.camera._clamp_position(); world.camera.force_update_scroll()
		world.step(1.0/30.0); simulation_samples.append(world.last_simulation_usec); await _frame()
	await _shot("street-depth")
	world.request_bus_action()
	await _advance(world,func() -> bool:return world.phase==Expedition.Phase.BOARDING)
	world.request_bus_gather()
	while world.phase!=Expedition.Phase.FINISHED:
		world.camera.position=world.survivors[0].position+Vector2(0,-160)
		world.camera._clamp_position(); world.camera.force_update_scroll()
		world.step(1.0/30.0); simulation_samples.append(world.last_simulation_usec); await _frame()
	_check(app.progress_session.inspect().receipt.phase=="RESULT_READY","original result frozen before filmed departure")
	while world.bus_view.running():
		world.camera.position=world._bus_sprite.position+Vector2(0,-180)
		world.camera._clamp_position(); world.camera.force_update_scroll()
		world.step(1.0/30.0); await _frame()
	await _shot("frozen-preview")
	await _hold(45)
	simulation_samples.sort()
	_write("performance.json",{"samples":simulation_samples.size(),"simulation_usec_median":simulation_samples[simulation_samples.size()/2],"simulation_usec_p95":simulation_samples[int(simulation_samples.size()*0.95)],"simulation_usec_max":simulation_samples[-1],"enemies":world.enemies.size(),"survivors":world.survivors.size(),"viewport":[1280,720],"display_fps":"NOT_MEASURED","video_simulation_rate":1})
