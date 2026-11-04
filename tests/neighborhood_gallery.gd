extends SceneTree
## Native read-only layout overview. Not a completed-gameplay or player-progress fixture.
var output: String
func _initialize() -> void:
	root.unfocusable=true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--gallery-output="):output=argument.trim_prefix("--gallery-output=")
	call_deferred("run")
func run() -> void:
	assert(output.is_absolute_path() and "/.local/" in output and not DirAccess.dir_exists_absolute(output))
	DirAccess.make_dir_recursive_absolute(output)
	var reports: Array=[]
	for bone: String in NeighborhoodLayout.TOPOLOGIES:
		for index: int in range(3):
			var offer: Dictionary=NeighborhoodActions._make("world02-fixed-0".md5_text(),2,0,"supply",bone,NeighborhoodLayout.SIZES[index],0)
			var vp: SubViewport=SubViewport.new();vp.size=Vector2i(1280,720);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
			var world: Expedition=load("res://src/features/expedition/expedition.tscn").instantiate()
			world.supply=NeighborhoodActions.supply(offer)
			vp.add_child(world);world.set_physics_process(false);world.set_process_unhandled_input(false)
			if world.bus_view!=null: world.bus_view.skip()
			world._hud.hide_screen();world.camera.set_process(false);world.camera.position=world.layout.world_bounds.get_center();world.camera.zoom=Vector2.ONE*(minf(1180.0/world.layout.world_bounds.size.x,610.0/world.layout.world_bounds.size.y))
			var layer: CanvasLayer=CanvasLayer.new();layer.layer=100;vp.add_child(layer)
			var label: Label=Label.new();label.position=Vector2(24,16);label.add_theme_font_size_override("font_size",22)
			label.text="布局预览 · %s %s · 未推进模拟\n种子%s · 地形指纹%s"%[["商业主街","住宅巷","仓储院落"][NeighborhoodLayout.TOPOLOGIES.find(bone)],["小型","中型","大型"][index],offer.seed.substr(0,10),String(offer.layout.id).substr(0,12)]
			label.add_theme_constant_override("outline_size",5);layer.add_child(label)
			for frame: int in range(8):await process_frame
			assert(OS.has_feature("windows") or not root.has_focus(),"background surface focus")
			RenderingServer.force_draw();vp.get_texture().get_image().save_png(output.path_join("%s-%d.png"%[bone,index+1]))
			reports.append({"seed":offer.seed,"day":offer.day,"task_id":offer.id,"generator":offer.layout.version,"topology":bone,"size":offer.layout["size"],"geometry":String(offer.layout.id),"footprint":String(offer.layout.id),"fallback":false,"layout":offer.layout})
			vp.queue_free();await process_frame
	var file: FileAccess=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"rows":reports,"scope":"real native scene overview, physics not advanced; source geometry is unchanged","focused":root.has_focus()},"\t"));file.close()
	print("NEIGHBORHOOD_GALLERY layouts=9 focused=",root.has_focus())
	quit()
