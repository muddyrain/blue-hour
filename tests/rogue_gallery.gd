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
	var groups: Dictionary={"straight":[],"fork":[],"ring":[]}
	for index: int in range(100):
		var base: Dictionary={"schema_version":111,"journey":{"seed":("fixed-seed-%03d"%index).md5_text()},"day":2,"settled_sorties":0,"profile_id":"a".repeat(32),"crew":[{"id":1,"health":200},{"id":2,"health":200}]}
		for offer: Dictionary in RogueActions.offers(base):
			var group: Array=groups[offer.layout.bone]
			if group.size()<2 and not group.any(func(value: Dictionary) -> bool:return RogueLayout.footprint_hash(value.layout)==RogueLayout.footprint_hash(offer.layout)):group.append(offer)
		if groups.values().all(func(v: Array) -> bool:return v.size()==2):break
	var reports: Array=[]
	for bone: String in RogueLayout.BONES:
		for index: int in range(2):
			var offer: Dictionary=groups[bone][index]
			var vp: SubViewport=SubViewport.new();vp.size=Vector2i(1280,720);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
			var world: Expedition=load("res://src/features/expedition/expedition.tscn").instantiate()
			world.supply=RogueActions.supply(offer)
			vp.add_child(world);world.set_physics_process(false);world.set_process_unhandled_input(false)
			world._hud.hide_screen();world.camera.set_process(false);world.camera.position=Vector2(960,720);world.camera.zoom=Vector2.ONE*0.46
			var layer: CanvasLayer=CanvasLayer.new();layer.layer=100;vp.add_child(layer)
			var label: Label=Label.new();label.position=Vector2(24,16);label.add_theme_font_size_override("font_size",22)
			label.text="布局预览 · %s %d · 未推进模拟\n种子%s · 地形指纹%s"%[RogueLayout.NAMES[RogueLayout.BONES.find(bone)],index+1,offer.seed.substr(0,10),RogueLayout.footprint_hash(offer.layout).substr(0,12)]
			label.add_theme_constant_override("outline_size",5);layer.add_child(label)
			for frame: int in range(8):await process_frame
			assert(OS.has_feature("windows") or not root.has_focus(),"background surface focus")
			RenderingServer.force_draw();vp.get_texture().get_image().save_png(output.path_join("%s-%d.png"%[bone,index+1]))
			reports.append({"seed":offer.seed,"day":offer.day,"task_id":offer.id,"generator":offer.layout.version,"bone":bone,"geometry":RogueLayout.geometry_hash(offer.layout),"footprint":RogueLayout.footprint_hash(offer.layout),"fallback":offer.layout.fallback,"layout":offer.layout})
			vp.queue_free();await process_frame
	var file: FileAccess=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"rows":reports,"scope":"real native scene overview, physics not advanced; source geometry is unchanged","focused":root.has_focus()},"\t"));file.close()
	print("ROGUE_GALLERY layouts=6 focused=",root.has_focus())
	quit()
