extends SceneTree
var output: String
func _initialize() -> void: root.unfocusable=true;call_deferred("run")
func run() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--local-output="):output=a.trim_prefix("--local-output=")
	assert(output.is_absolute_path() and "/.local/" in output);DirAccess.make_dir_recursive_absolute(output)
	for version: int in [2,3]:
		var data: Dictionary=WorldActions._make("rogue-sample-008".md5_text(),2,0,"supply","lanes",0) if version==2 else NeighborhoodActions._make("rogue-sample-008".md5_text(),2,0,"supply","commercial","medium",0)
		var vp: SubViewport=SubViewport.new();vp.size=Vector2i(1280,720);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
		var world: Expedition=load("res://src/features/expedition/expedition.tscn").instantiate();world.supply=DailyActions.supply(data);vp.add_child(world);world.set_physics_process(false);world.set_process(false);world.bus_view.skip()
		world._hud.hide_screen();world.camera.set_process(false);world.camera.position=Vector2(1080,1460);world.camera.zoom=Vector2.ONE*0.70;world.camera.force_update_scroll()
		for f: int in range(6): await process_frame
		RenderingServer.force_draw();vp.get_texture().get_image().save_png(output.path_join("local-before.png" if version==2 else "local-after.png"))
		vp.queue_free();await process_frame
	quit()
