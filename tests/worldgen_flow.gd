extends "res://tests/exploration_flow.gd"
## Normal entry and original intentions; old15 representative uses an exact reviewed Main.

func _journey() -> void:
	if "--flow-preview" in OS.get_cmdline_user_args():
		await _tap(app._home_button);await _tap(app._new_game_confirmation.get_ok_button())
		await _menu()
		var requested: String="medium"
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--flow-size="): requested=arg.trim_prefix("--flow-size=")
		var slot: int=0
		for i: int in range(app.mission_select.daily_offers.size()):
			if app.mission_select.daily_offers[i].layout["size"]==requested:slot=i
		var world: Expedition=await _start(slot)
		if world==null:return
		var graph: Dictionary=world.layout.world_data.graph
		var target: Vector2=world.layout.bus_door
		var distance: float=INF
		for node_index: int in range(graph.nodes.size()):
			var degree: int=0
			for edge: Array in graph.edges:
				if int(edge[0])==node_index or int(edge[1])==node_index:degree+=1
			var point: Vector2=WorldLayout.point(graph.nodes[node_index])
			if degree>=3 and point.distance_to(world.layout.bus_door)<distance:
				distance=point.distance_to(world.layout.bus_door);target=point
		world.command_move(target)
		await _until(world,func()->bool:return world.survivors.all(func(actor:FieldActor)->bool:return actor.position.distance_to(target)<100.0))
		world.camera.pan_by(target-Vector2(0,180)-world.camera.position)
		await _shot("street-sample")
		_write("acceptance.json",{"representative_load":requested,"camera_zoom":world.camera.zoom.x,"initialization_only":true})
		return
	if "--flow-legacy-worldgen" not in OS.get_cmdline_user_args():
		await super._journey()
		return
	await _tap(app._home_button);await _tap(app._new_game_confirmation.get_ok_button())
	_check(not WorldgenState.enabled(app.camp_snapshot()) and ExplorationState.enabled(app.camp_snapshot()),"reviewed old main creates an actual build5 world15 journey")
	await _menu()
	var slot: int=0
	for i: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[i].layout["size"]=="medium": slot=i
	var world: Expedition=await _start(slot)
	if world==null:return
	_check(world.layout.world_data.version==4 and not world.supply.generated.has("worldgen"),"old fifteen retains exact layout4 and original reward policy")
	world.request_search(&"cash")
	await _until(world,func()->bool:return world.elapsed>=8.0)
	await _shot("legacy-world15")
	await _suspend(world)

func _start(slot: int) -> Expedition:
	var world: Expedition=await super._start(slot)
	if world!=null:
		_write("frozen-layout.json",world.layout.world_data)
		_write("runtime-scale.json",{"camera_zoom":[world.camera.zoom.x,world.camera.zoom.y],"base_speed":world.survivors[0].speed,"character_visual_scale":[world.survivors[0].visual.scale.x,world.survivors[0].visual.scale.y],"layout_version":world.layout.world_data.version,"generated":world.supply.generated})
		if "--flow-legacy-worldgen" not in OS.get_cmdline_user_args():
			_check(WorldgenState.enabled(app.camp_snapshot()) and world.layout.world_data.version==5,"normal new journey binds new road-parcel layout")
			var hud: C1ExpeditionHud=world._hud.view
			_check(not hud.persona_details.visible,"normal entry keeps full character details closed")
			var paused_before: bool=world.is_paused
			await _tap(hud._persona_cards[0].info_button)
			_check(hud.persona_details.visible and not hud.persona_details.weapon_label.text.is_empty() and world.is_paused==paused_before,"actual character detail reveals original weapon without adding a pause rule")
			await _tap(hud.persona_details.close_button)
			_check(not hud.persona_details.visible and hud._persona_id==0,"actual keyboard close returns to compact field HUD")
	return world

func _resume() -> void:
	if "--flow-legacy-worldgen" not in OS.get_cmdline_user_args():
		await super._resume()
		return
	var prior: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition=app.expedition
	_check(world!=null,"new PID restores actual old15 through normal Continue")
	if world==null:return
	world.set_physics_process(false);world.set_process(false)
	_check(prior.pid!=OS.get_process_id() and RecordEncoding.fingerprint(SortieSnapshot.capture(world))==prior.fingerprint,"old15 exact geometry objects work budget traits clocks and fingerprint survive new PID")
	_check(world.layout.world_data.version==4 and not world.supply.generated.has("worldgen"),"continue never regenerates old world using new geometry")
	await _shot("legacy-world15-restored")
	_write("acceptance.json",{"legacy_world15":true,"restored":true,"camera_zoom":world.camera.zoom.x})

func _extract(world: Expedition) -> void:
	# The long approach is outside the short reel; every recorded frame is still 1/30s.
	await _until(world,func()->bool:return world.survivors.all(func(actor:FieldActor)->bool:return actor.health<=0 or actor.position.distance_to(world.layout.bus_door)<120.0))
	world.camera.pan_by(world.layout.bus_door-Vector2(0,200)-world.camera.position)
	segment_frames=0;segment_limit=210;recording=true
	if capture_caption!=null:capture_caption.text="部分目标归航 · 自动输入 · 1× · 剪接"
	await super._extract(world)
	await _hold(maxi(0,210-segment_frames))
	recording=false
