extends SceneTree
## Three-size native smoke; only presentation changes, no edited progress or actor state.
var output: String


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view-output="):
			output = arg.trim_prefix("--view-output=")
	assert(output.is_absolute_path() and "/.local/" in output)
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	for i: int in range(3):
		var size: String = NeighborhoodLayout.SIZES[i]
		var topology: String = NeighborhoodLayout.TOPOLOGIES[i]
		var data: Dictionary = NeighborhoodActions._make("world02-fixed-0".md5_text(),2,0,"supply",topology,size,0)
		var vp: SubViewport = SubViewport.new()
		vp.size = Vector2i(1280,720)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var world: Expedition = load("res://src/features/expedition/expedition.tscn").instantiate()
		world.supply = DailyActions.supply(data)
		vp.add_child(world)
		world.set_physics_process(false)
		world.set_process(false)
		world.bus_view.skip()
		var first: Array[Dictionary] = NeighborhoodDecor.placements(world.layout)
		var second: Array[Dictionary] = NeighborhoodDecor.placements(world.layout)
		assert(first == second, "decor is a stable pure derivative of the same saved layout")
		var lamps: int = 0
		var planters: int = 0
		for detail: Dictionary in first:
			assert(NeighborhoodDecor._clear(world.layout, detail.position))
			if detail.kind == "lamp":
				lamps += 1
			else:
				planters += 1
		assert(lamps <= 6 and planters <= data.layout.entities.size()/4 and lamps+planters < data.layout.entities.size()*2)
		world.camera.set_process(false)
		world.camera.zoom = Vector2.ONE*0.82
		world.camera.position = world.layout.camera_start
		world.camera._clamp_position()
		world.camera.force_update_scroll()
		for f: int in range(5):
			await process_frame
		var bus: Rect2 = world._bus_sprite.get_global_transform_with_canvas()*world._bus_sprite.get_rect()
		assert(not bus.intersects(world._hud.view._help_button.get_global_rect()))
		if world.rescue_target != null:
			assert(not bus.intersects(world.rescue_target.button.get_global_rect()))
		rows.append({"size":size,"topology":topology,"bounds":data.layout.bounds,"buildings":data.layout.entities.size(),"lamps":lamps,"planters":planters,"zoom":0.82,"bus_hint_overlap":false})
		if DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			vp.get_texture().get_image().save_png(output.path_join(size+".png"))
		vp.queue_free()
		await process_frame
	var file: FileAccess = FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"scope":"read-only actual scene, same zoom; no simulated rewards"},"\t"))
	print("CLOSEOUT_VIEW sizes=3 deterministic_decor=PASS bus_cues=PASS")
	quit()
