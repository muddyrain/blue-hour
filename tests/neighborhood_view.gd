extends SceneTree
## Targeted presentation check; synthetic HUD rows, no edits to camp/progress.
var output: String
func _initialize() -> void: root.unfocusable=true;call_deferred("run")
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view-output="):output=arg.trim_prefix("--view-output=")
	assert(output.is_absolute_path() and "/.local/" in output);DirAccess.make_dir_recursive_absolute(output)
	var vp: SubViewport=SubViewport.new();vp.size=Vector2i(1280,720);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var world: Expedition=load("res://src/features/expedition/expedition.tscn").instantiate()
	world.supply=NeighborhoodActions.supply(NeighborhoodActions._make("world02-fixed-0".md5_text(),2,0,"supply","residential","medium",0));vp.add_child(world)
	world.set_physics_process(false);world.set_process(false);world.bus_view.skip()
	for f: int in range(4):await process_frame
	world.camera.pan_by(Vector2(-99999,-99999));var half: Vector2=vp.size/2.0/world.camera.zoom
	assert(world.camera.position==world.layout.world_bounds.position+half)
	world.camera.pan_by(Vector2(99999,99999));assert(world.camera.position==world.layout.world_bounds.end-half)
	world.camera.zoom_at(Vector2(640,360),0.01);assert(is_equal_approx(world.camera.zoom.x,0.70))
	world.camera.zoom_at(Vector2(640,360),100);assert(is_equal_approx(world.camera.zoom.x,1.25))
	world.toggle_pause();var elapsed: float=world.elapsed;world.step(1);assert(world.elapsed==elapsed);world.toggle_pause()
	var tested: int=0
	for child: Node in world._sort.get_children():
		if child is FieldProp:
			var p: FieldProp=child
			assert(p.calibrated and not p.obscures(p.global_position+Vector2(0,30)))
			var hit: bool=false
			for y: int in range(100,p.roof_cut,40):
				if p._alpha.get_pixel(256,y).a>0.2:
					hit=p.obscures(p.global_position+Vector2(0,(y-608)*(p.front_width/448.0)+45))
					assert(p.obscures(p.global_position+Vector2(0,(y+1-608)*(p.front_width/448.0))),"legs-only silhouette overlap must also fade")
					break
			assert(hit);p.show_behind_roof(true);assert(is_equal_approx(p._roof.modulate.a,0.4));p.show_behind_roof(false);tested+=1
	world.camera.zoom=Vector2.ONE*0.82;world.camera.position=world.layout.camera_start;world.camera._clamp_position();world.camera.force_update_scroll()
	var hud: C1ExpeditionHud=world._hud.view
	for count: int in [3,4]:
		var members: Array=[]
		for i: int in range(count):members.append({"id":i+1,"call_sign":"夏之遥","label":"夏之遥 · 搜集中","hp":205,"max_hp":210,"level":3,"status":"搜集中"})
		hud.refresh({"mission_title":"中型住宅街区","day_text":"第3天","currency_text":"57","currency_delta_text":"+2携带 · 食物2（携带+1）· 武器+1","survivors":members})
		for f: int in range(4):await process_frame
		assert(hud.get_node("MissionPanel").size.y<=144)
		for row: Dictionary in hud._members:
			if row.box.visible:assert(row.title.get_line_count()==1 and row.health.get_line_count()==1 and row.status.get_line_count()==1)
		if DisplayServer.get_name()!="headless":
			RenderingServer.force_draw();vp.get_texture().get_image().save_png(output.path_join("hud-%d.png"%count))
	print("NEIGHBORHOOD_VIEW camera_pause_zoom=PASS silhouettes=",tested," hud3_4=PASS synthetic HUD rows")
	vp.queue_free();await process_frame;quit()
