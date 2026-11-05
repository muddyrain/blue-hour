extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if "/.local/" not in OS.get_user_data_dir().replace("\\","/"):
		printerr("WORLD_BUS_REQUIRES_ISOLATED_PROFILE")
		quit(2)
		return
	var app: Node = load("res://src/app/main.tscn").instantiate(); root.add_child(app)
	await process_frame
	app.playable_entry=false # Explicit historical fixture; normal new journeys use short V1.
	app._new_game()
	for offer: Dictionary in WorldActions.offers(app.camp_snapshot()):
		if offer.type=="rescue": app._select_mission(WorldActions.supply(offer)); break
	var world: Expedition = app.expedition
	assert(world!=null and world.rescue_target!=null)
	world.set_physics_process(false); world.set_process(false)
	world.step(2.5); world.step(0.25)
	assert(world.bus_view.stage=="disembarking" and world.survivors[0].visible)
	world.rescue_target.refresh()
	world.rescue_target.request()
	assert(world.rescue_target.worker==0 and world.rescue_target.status=="AVAILABLE" and world.rescue_target.button.disabled)
	world.toggle_pause(); var at: Vector2=world._bus_sprite.position; world.step(1)
	assert(world._bus_sprite.position==at and world.elapsed==0)
	world.toggle_pause(); world.bus_view.skip(); world.bus_view.skip()
	assert(world.bus_view.stage=="exploring" and world.survivors.size()==2 and world.elapsed==0)
	world.rescue_target.request()
	assert(world.rescue_target.status=="IN_PROGRESS")
	print("WORLD_BUS_PASS checks=6")
	await create_timer(0.5).timeout; app.audio.shutdown(); await create_timer(0.2).timeout; app.queue_free(); await process_frame; await process_frame; quit()
