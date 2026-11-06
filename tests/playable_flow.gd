extends SceneTree
## Isolated real interface/business flow. No OS input and no synthetic camp/world edits.
var _legacy_fixed: bool=false
var capture_caption: Label
var app: Node
var viewport: SubViewport
var output: String
var resume: bool = false
var movie: StreamPeerTCP
var rows: Array[Dictionary] = []
var events: Array[Dictionary] = []
var training_effects: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var frames: int = 0
var failures: int = 0
var legacy_hashes: Dictionary = {}
var focus_observations: Array[bool] = []

func _initialize() -> void:
	root.unfocusable = true
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	rows.append({"pass":value,"label":label})
	if not value:
		failures += 1
		printerr("PLAYABLE_FAIL "+label)

func _frame() -> void:
	await process_frame
	if DisplayServer.get_name() != "headless": focus_observations.append(root.has_focus())
	if movie != null:
		RenderingServer.force_draw()
		var image: Image = viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		var sent: Error = movie.put_data(image.get_data())
		if sent!=OK:
			_check(false,"video stream remains connected")
			quit(3)
		frames += 1

func _hold(count: int = 8) -> void:
	for index: int in range(count): await _frame()

func _tap(button: BaseButton) -> void:
	await _hold(3)
	_check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"available interface control: "+String(button.name))
	if button.disabled or not button.is_visible_in_tree(): return
	button.grab_focus()
	await _hold(2)
	for down: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = down
		viewport.push_input(event,true)
		await _frame()
	await _hold(5)

func _mark(label: String) -> void:
	stages.append({"stage":label,"video_seconds":float(frames)/30.0,"camp_day":app.day,"pid":OS.get_process_id()})
	print("PLAYABLE_STAGE "+label)
	if movie != null:
		await _hold(25)
		if label in ["title","training-confirm","mission-1","result-1","camp-3","continued"]:
			RenderingServer.force_draw()
			viewport.get_texture().get_image().save_png(output.path_join(label+".png"))

func _advance(world: Expedition, until: Callable, limit: int = 5400) -> void:
	for index: int in range(limit):
		if until.call(): return
		world.step(1.0/30.0)
		if index%6 == 0: await _frame()
	_check(until.call(),"bounded simulation reached requested business checkpoint")

func _write(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t"))

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--flow-output="): output = arg.trim_prefix("--flow-output=")
		if arg=="--flow-resume": resume = true
		if arg=="--flow-fixed": _legacy_fixed = true
	root.unfocusable = true
	root.gui_embed_subwindows = true
	if not output.is_absolute_path() or "/.local/" not in output or "/.local/" not in OS.get_user_data_dir().replace("\\","/") or FileAccess.file_exists(output.path_join("report.json")):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	_write("pid.json",{"pid":OS.get_process_id()})
	for legacy_path: String in ["user://saves/run.json","user://saves/run.enemy-v1.json","user://settings/audio.json"]:
		if not resume:
			assert(not FileAccess.file_exists(legacy_path),"fresh synthetic profile required")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(legacy_path).get_base_dir())
			var sentinel: FileAccess = FileAccess.open(legacy_path,FileAccess.WRITE)
			sentinel.store_string("M6 synthetic protected old file; must never be read as playable or migrated")
			sentinel.close()
		legacy_hashes[legacy_path] = FileAccess.get_sha256(legacy_path)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--flow-stream="):
			movie = StreamPeerTCP.new()
			var connected: Error = movie.connect_to_host("127.0.0.1",int(arg.trim_prefix("--flow-stream=")))
			_check(connected==OK,"local encoder connection requested")
			for retry: int in range(100):
				movie.poll()
				if movie.get_status()==StreamPeerTCP.STATUS_CONNECTED: break
				await process_frame
			assert(movie.get_status()==StreamPeerTCP.STATUS_CONNECTED,"local encoder ready")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	app = load("res://src/app/main.tscn").instantiate()
	if "--flow-bootstrap-m11" in OS.get_cmdline_user_args(): app.set_script(load("res://.local/m12-survivor-01/input/m11_main.gd"))
	if "--flow-bootstrap-m10" in OS.get_cmdline_user_args(): app.set_script(load("res://.local/m11-power-01/input/m10_main.gd"))
	if "--flow-bootstrap-m8" in OS.get_cmdline_user_args(): app.set_script(load("res://.local/m9_m8_main.gd"))
	viewport.add_child(app)
	if movie != null:
		var overlay: CanvasLayer = CanvasLayer.new()
		overlay.layer = 100
		viewport.add_child(overlay)
		var caption: Label = Label.new()
		capture_caption = caption
		caption.text = "自动流程演示 · 行动模拟6× · 非显示器FPS测试"
		caption.position = Vector2(700,697)
		caption.add_theme_font_size_override("font_size",16)
		caption.add_theme_color_override("font_color",Color.WHITE)
		caption.add_theme_color_override("font_shadow_color",Color.BLACK)
		caption.add_theme_constant_override("shadow_offset_x",2)
		caption.add_theme_constant_override("shadow_offset_y",2)
		overlay.add_child(caption)
	await _hold(10)
	_check((app.playable_entry or _legacy_fixed) and app.enemy_mode and app.camp_prototype and app.safe_suspend,"no gameplay parameters activates existing complete mode")
	var expected_path: String=PlayableEntry.progress_path()
	if _legacy_fixed:
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--bh-progress="):expected_path=argument.trim_prefix("--bh-progress=")
	_check(app.progress_path==expected_path,"canonical stable independent profile")
	await _mark("title")
	if resume:
		await _resume()
	else:
		await _journey()
	for path: String in legacy_hashes:
		_check(FileAccess.get_sha256(path)==legacy_hashes[path],"old entry file remains byte-identical: "+path)
	if DisplayServer.get_name() != "headless": _check(OS.has_feature("windows") or not focus_observations.has(true),"background renderer; Windows must use isolated desktop launcher")
	_write("report.json",{"checks":rows,"failures":failures,"stages":stages,"events":events,"training_effects":training_effects,"camp":app.camp_snapshot(),"pid":OS.get_process_id(),"path":app.progress_path,"legacy_hashes":legacy_hashes,"root_visible":root.visible,"root_focused":root.has_focus(),"native_focus_observations":focus_observations.size(),"video_frames":frames,"input":flow_input_description(),"physical_input":"NOT_TESTED","display_FPS":"NOT_MEASURED"})
	if movie != null: movie.disconnect_from_host()
	app.audio.shutdown()
	# Allow the native audio mixer to release stopped one-shot playback references.
	await create_timer(0.2).timeout
	app.queue_free()
	app = null
	await process_frame
	viewport.queue_free()
	viewport = null
	await process_frame
	quit(0 if failures==0 else 1)

func _resume() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/report.json")))
	_check(app._requires_continue and not app._camp_open,"restart offers continue without a new journey")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	_check(TransactionReceipt.same(app.camp_snapshot(),expected.camp),"new PID restores exact date/resources/crew/growth/training/weapon instances")
	_check(int(expected.pid)!=OS.get_process_id(),"different process actually resumed")
	_check(expected.legacy_hashes==legacy_hashes,"legacy sentinels unchanged across process restart")
	_check(app.camp_scene.is_visible_in_tree(),"continue returns to playable camp")
	await _mark("continued")

func _journey() -> void:
	_check(not app._requires_continue and not FileAccess.file_exists(app.progress_path),"fresh profile is empty, old legacy file ignored")
	await _tap(app._home_button)
	_check(app._new_game_confirmation.visible,"start requires existing explicit new-root confirmation")
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked,"initial camp durably created")
	var original: Dictionary = app.camp_snapshot()
	await _tap(app.camp_scene.hotspots[&"training"])
	await _tap(app.training_panel.member_buttons[1])
	if not _legacy_fixed: _check("PROJECT_TEMP" not in app.training_panel.detail.text and "PROJECT_TEMP" not in app.training_panel.preview_text.text,"player training preview omits internal prototype marker")
	await _tap(app.training_panel.train_button)
	await _mark("training-confirm")
	await _tap(app.training_panel.confirmation.get_ok_button())
	var trained: Dictionary = app.camp_snapshot()
	_check(trained.food==original.food-1 and SurvivorRoster.member(trained.crew,1).growth.trait.level==2,"real one-food training raises original trait to level2")
	await _tap(app.training_panel.back_button)
	for choice: int in [1,2,0]:
		var round_number: int = app.settled_sorties+1
		var before: Dictionary = app.camp_snapshot()
		await _tap(app.camp_scene.hotspots[&"bus"])
		_check(viewport.get_visible_rect().encloses(app.mission_select.cancel_button.get_global_rect()),"mission cancel stays inside normal 1280x720 viewport")
		await _mark("mission-%d" % round_number)
		await _tap(app.mission_select.choices[choice])
		var world: Expedition = app.expedition
		_check(world != null and app.phase==app.Phase.EXPEDITION,"selected original mission starts signed real outing")
		if world==null: return
		world.set_physics_process(false)
		world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
		var untrained_factor: float = TraitRules.factor(SurvivorRoster.member(original.crew,1),"shot")
		var expected_factor: float = TraitRules.factor(SurvivorRoster.member(before.crew,1),"shot")
		var actual_factor: float = world.survivors[0].trait_shot_factor
		training_effects.append({"sortie":round_number,"member_id":1,"untrained":untrained_factor,"expected":expected_factor,"actual":actual_factor})
		_check(actual_factor<untrained_factor and is_equal_approx(actual_factor,expected_factor),"purchased training changes actual next-sortie shooting factor compared with original untrained member")
		if choice==2:
			await _tap(world.rescue_target.button)
			await _advance(world,func() -> bool: return not world.field_joins.is_empty())
			_check(world.field_joins.size()==1 and world.survivors.size()==3,"real rescue completes and same actor joins combat")
		world.request_search(&"cash")
		await _advance(world,func() -> bool: return world.searched)
		_check(world.searched and world.loot==world.supply.cash_reward,"real currency search pays only completed original site")
		if world.supply.supports(&"food"):
			world.request_search(&"food")
			await _advance(world,func() -> bool: return world._food_site.searched)
			_check(world.food_loot==world.supply.food_reward,"original food search actually completes")
		await _mark("search-%d" % round_number)
		await _advance(world,func() -> bool: return world.elapsed>=world.tuning.bus_ready_seconds)
		await _tap(world._hud.view._bus_button)
		await _advance(world,func() -> bool: return world.phase==Expedition.Phase.BOARDING)
		await _tap(world._hud.view._bus_button)
		await _advance(world,func() -> bool: return world.phase==Expedition.Phase.FINISHED)
		_check(app.phase==app.Phase.RESULT and world.boarding_status().arrived==world.living_count(),"all actual living actors gathered before frozen preview")
		_check(TransactionReceipt.same(before,app.camp_snapshot()),"preview never banks rewards or advances date")
		if not _legacy_fixed: _check(("带回：货币%d" % app._pending_settlement.last_day.cash_gained) in app.get_node("Interface/Screen/Result/Scroll/Body").text,"player reward text reads authoritative frozen camp ledger")
		await _mark("result-%d" % round_number)
		if round_number==2:
			app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point=="before_commit_receipt" else OK
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		if round_number==2:
			_check(app._progress_blocked and TransactionReceipt.same(before,app.camp_snapshot()),"failed save cannot apply rewards or expose playable camp")
			app.open_mission_select()
			_check(app.expedition==null and not app.mission_select.visible,"failure cannot bypass into next outing")
			app.progress_session.fault_hook = Callable()
			await _tap(app._retry_button)
		var saved: Dictionary = app.camp_snapshot()
		_check(saved.settled_sorties==round_number and saved.day==before.day+1 and app.camp_scene.is_visible_in_tree(),"one confirmation durably returns to next-day camp")
		var digest: String = FileAccess.get_sha256(app.progress_path)
		app.return_to_title()
		_check(digest==FileAccess.get_sha256(app.progress_path) and TransactionReceipt.same(saved,app.camp_snapshot()),"repeated settlement confirmation cannot claim twice")
		await _mark("camp-%d" % round_number)
	_check(app.settled_sorties==3 and app.day==5 and app.crew.size()==3,"three consecutive real outings, both maps, rescue and training")

func flow_input_description() -> String:
	return "viewport Enter + existing search/rescue/bus intentions; 6 simulation ticks per captured frame"
