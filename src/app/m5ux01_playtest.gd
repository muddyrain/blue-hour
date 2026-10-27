class_name M5UX01Playtest
extends M503Playtest
## Opt-in native UX proof. Uses existing viewport events and ordinary gameplay only.

var _ux_trace: Array[Dictionary] = []
var _gather_events: int = 0
var _last_boarding: Dictionary = {}
var _action_label: String = ""
var _layout_samples: Array[Dictionary] = []
var _layout_checked: Dictionary[String, bool] = {}


func _run() -> void:
	app.get_node("World").child_entered_tree.connect(_connect_ux)
	await super._run()


func _connect_ux(node: Node) -> void:
	if not node is Expedition:
		return
	var sortie: Expedition = node
	_last_boarding = {}
	sortie.bus_gather_ordered.connect(func(_state: Dictionary) -> void:
		_gather_events += 1
		_record_ux(sortie, "accepted_gather"))
	sortie.finished.connect(func(_report: Dictionary) -> void: _record_ux(sortie, "finished"))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(app.expedition) or app.expedition.layout == null:
		return
	var sortie: Expedition = app.expedition
	var state: Dictionary = sortie.boarding_status()
	state["phase"] = sortie.phase
	if state != _last_boarding:
		_last_boarding = state
		_record_ux(sortie, "boarding_changed")
		if sortie.phase == Expedition.Phase.BOARDING and state.arrived == 1:
			_capture.call_deferred("ux-arrival-one-of-two")


func _record_ux(sortie: Expedition, action: String) -> void:
	var actors: Array[Dictionary] = []
	for actor: FieldActor in sortie.survivors:
		actors.append({"id":actor.actor_id+1,"point":actor.position,"activity":actor.activity,"visible":actor.visible})
	_ux_trace.append({"action":action,"input_label":_action_label,"movie_frame":Engine.get_frames_drawn(),
		"sortie_id":sortie.sortie_id,"map":String(sortie.layout.id),"phase":sortie.phase,"paused":sortie.is_paused,
		"elapsed":sortie.elapsed,"goal":sortie.goal,"bus_door":sortie.layout.bus_door,"boarding":sortie.boarding_status(),
		"actors":actors,"gather_events":_gather_events,"engine_clock":sortie._engine_clock,
		"camera":sortie.camera.position,"zoom":sortie.camera.zoom,"bus_label":sortie._hud.view._bus_button.text,
		"bus_status":sortie._hud.view._bus_status.text})


func _check_audio_preferences() -> void:
	await super._check_audio_preferences()
	if _sequence == "scavenge" and DisplayServer.window_get_size().x <= 1024:
		await _rename(1,"蓝时归航观察员一号同行者")
		await _rename(2,"暮色归航观察员二号同行者")
		_before = app.camp_snapshot()


func _play_task() -> void:
	await _enter_task()
	var sortie: Expedition = app.expedition
	_tracing = true
	sortie.finished.connect(func(report: Dictionary) -> void: _sortie_reports.append(report.duplicate(true)))
	await _hud_inputs(sortie)
	var kinds: Array[StringName] = [&"cash"]
	if _has_food:
		kinds.assign([&"food", &"cash"])
	for kind: StringName in kinds:
		var site: Expedition.SearchSite = sortie.search_site(kind)
		var block: Rect2 = sortie.layout.food_block if kind == &"food" else sortie.layout.cash_block
		await _frame_at(sortie, site.door)
		sortie.command_move(site.door + Vector2(112,96))
		if kind == &"cash":
			await _ordinary_contact(sortie, site.door)
		await _click_world(sortie, Vector2(block.get_center().x,block.end.y-30))
		await _until_inside(sortie)
		await _capture("ux-01-" + String(kind) + "-searching")
		if kind == kinds[-1]:
			while sortie.elapsed < sortie.tuning.bus_ready_seconds:
				await _wait(0.1)
			var old_goal: Vector2 = sortie.goal
			_action_label = "mouse_engine"
			await _click_screen(sortie._hud.view._bus_button.get_global_rect().get_center())
			_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.goal == old_goal and sortie.search_actor != null, "explicit engine preserves both the ground goal and active search")
			await _capture("ux-02-engine-during-search")
			while sortie.phase == Expedition.Phase.ENGINE:
				await _wait(0.1)
			_expect(sortie.goal == old_goal and _gather_events == 0, "engine countdown reaches waiting without any automatic recall")
			await _gather_inputs(sortie)
		var limit: int = 0
		while not site.searched and limit < 450:
			await _wait(0.1)
			limit += 1
		_expect(site.searched and app.camp_snapshot() == _before, "ordinary search finishes with its original payout while camp remains unchanged")
		await _capture("ux-06-" + String(kind) + "-collected")
	_expect(sortie.loot == 4 and sortie.food_loot == (3 if _has_food else 0) and sortie.weapon_loot.size() == 1, "gather leaves exact cash/food/weapon loot rules intact")
	_expect(_feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("moving")) and sortie.kills > 0, "ordinary mission includes real moving fire and actual confirmed defeats")
	await _finish_ux_sortie(sortie)


func _ordinary_contact(sortie: Expedition, door: Vector2) -> void:
	# Let the original screen-safe enemies reach the actual squad. A short patrol
	# proves moving fire before we start the last search and issue an early recall.
	var limit: int = 0
	while _audio_accepted("fire") == 0 and limit < 800:
		await _wait(0.1)
		limit += 1
	if not _feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("moving")):
		sortie.command_move(door + Vector2(160,128))
	limit = 0
	while (sortie.kills == 0 or not _feedback.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("moving"))) and limit < 200:
		await _wait(0.1)
		limit += 1
	_expect(sortie.kills > 0 and _audio_accepted("fire") > 0, "ordinary enemies reach the squad and receive actual weapon damage")
	await _capture("ux-real-moving-combat")


func _gather_inputs(sortie: Expedition) -> void:
	var hud: C1ExpeditionHud = sortie._hud.view
	await _click_screen(hud._pause_button.get_global_rect().get_center())
	_expect(sortie.is_paused, "mouse pauses the real waiting simulation")
	# Reproduce the baseline framing, then keep it fixed for every gather input.
	sortie.camera.zoom_at(get_viewport().get_visible_rect().size*0.5, 0.70/sortie.camera.zoom.x)
	sortie.camera.pan_by(sortie.layout.bus_door-Vector2(0,100)-sortie.camera.position)
	await _wait(0.1)
	var camera_before: Vector2 = sortie.camera.position
	var zoom_before: Vector2 = sortie.camera.zoom
	var ground: Vector2 = sortie.get_global_transform_with_canvas()*sortie.layout.bus_door
	var covered: bool = hud.get_node("ActionsPanel").get_global_rect().has_point(ground)
	var old_goal: Vector2 = sortie.goal
	if sortie.layout.id == &"market_loop":
		_expect(covered, "market reproduces the actual opaque HUD over the bus ground target")
	if covered:
		_action_label = "blocked_bus_ground"
		await _click_screen(ground)
		_expect(sortie.goal == old_goal and _gather_events == 0, "opaque HUD keeps absorbing the covered bus ground click")
	var blank: Vector2 = hud.get_node("ActionsPanel").get_global_rect().position+Vector2(8,8)
	await _click_screen(blank)
	await _wheel(blank)
	_expect(sortie.goal == old_goal and sortie.camera.zoom == zoom_before, "opaque panel still blocks both world movement and zoom")
	await _capture("ux-03-waiting-before-command")
	var worker: FieldActor = sortie.search_actor
	_expect(worker != null and not worker.visible, "the gather input is exercised during real hidden work")
	var frozen: Dictionary = _frozen_simulation(sortie)
	var before: int = _gather_events
	_action_label = "mouse_gather_paused"
	await _click_screen(hud._bus_button.get_global_rect().get_center())
	_expect(_gather_events == before+1 and sortie.goal == sortie.layout.bus_door and sortie.is_paused, "mouse gather accepts exactly one real bus goal without resuming")
	var paths: Array[PackedVector2Array] = [sortie.survivors[0].path.duplicate(),sortie.survivors[1].path.duplicate()]
	_action_label = "repeat_mouse_gather"
	await _click_screen(hud._bus_button.get_global_rect().get_center())
	await _wait(0.8)
	_expect(_frozen_simulation(sortie) == frozen and worker == sortie.search_actor and not worker.visible, "paused gather freezes clocks/threat/spawns/positions/cooldowns/search/engine without cancelling work")
	_expect(sortie.survivors[0].path == paths[0] and sortie.survivors[1].path == paths[1] and _audio_count("bus_start") == 1, "repeated same intention preserves paths and never restarts engine audio")
	await _capture("ux-04-mouse-gather-paused")
	_action_label = "space_resume_after_mouse"
	await _key(KEY_SPACE)
	_expect(not sortie.is_paused and _gather_events == before+2, "Space after mouse gather resumes once without a second gather")
	await _wait(0.3)
	await _click_screen(hud._pause_button.get_global_rect().get_center())
	await _focus_via_tab(hud._bus_button)
	before = _gather_events
	frozen = _frozen_simulation(sortie)
	_action_label = "tab_space_gather"
	await _key(KEY_SPACE)
	_expect(_gather_events == before+1 and sortie.is_paused and hud._bus_button.has_focus(), "Tab-focused gather consumes Space once and retains keyboard focus")
	_action_label = "tab_enter_gather"
	await _key(KEY_ENTER)
	_expect(_gather_events == before+2 and sortie.is_paused and _frozen_simulation(sortie) == frozen, "focused Enter accepts once without global pause or simulation advance")
	await _capture("ux-05-keyboard-gather-paused")
	await _focus_via_tab(hud._pause_button)
	_action_label = "keyboard_resume"
	await _key(KEY_ENTER)
	_expect(not sortie.is_paused and _audio_count("bus_start") == 1 and sortie.phase == Expedition.Phase.BOARDING, "keyboard Continue resumes the same boarding phase without another engine action")
	_expect(sortie.camera.position == camera_before and sortie.camera.zoom == zoom_before, "all new gather inputs work with the exact same camera and zoom")
	get_viewport().gui_release_focus()


func _frozen_simulation(sortie: Expedition) -> Dictionary:
	var state: Dictionary = _pressure_state(sortie)
	# Registering a path changes a survivor's intention from idle to moving;
	# physical position and every simulation value must still stay frozen.
	for actor: Dictionary in state.actors:
		if not actor.enemy:
			actor.erase("activity")
	return state


func _leave_under_pressure(sortie: Expedition) -> void:
	var old_goal: Vector2 = sortie.goal
	await _click_screen(sortie._hud.view._bus_button.get_global_rect().get_center())
	_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.goal == old_goal, "night engine also preserves the previous squad goal")
	while sortie.phase == Expedition.Phase.ENGINE:
		await _wait(0.1)
	var camera_before: Vector2 = sortie.camera.position
	var zoom_before: Vector2 = sortie.camera.zoom
	_action_label = "night_mouse_gather"
	await _click_screen(sortie._hud.view._bus_button.get_global_rect().get_center())
	_expect(sortie.goal == sortie.layout.bus_door and sortie.camera.position == camera_before and sortie.camera.zoom == zoom_before, "night gather reaches the actual door without reframing")
	await _capture("ux-night-gathering")
	await _finish_ux_sortie(sortie)


func _finish_ux_sortie(sortie: Expedition) -> void:
	var limit: int = 0
	while app.phase != app.Phase.RESULT and limit < 500:
		await _wait(0.1)
		limit += 1
	_tracing = false
	_expect(app.phase == app.Phase.RESULT and _sortie_reports.size() == 1 and _sortie_reports[0].evacuated, "real navigation and actual arrival produce one successful FINISHED result")
	_expect(sortie.boarding_status().arrived == sortie.boarding_status().required and sortie.boarding_status().required == 2, "both surviving members actually reached the original region")
	_expect(_map_trace.all(func(sample: Dictionary) -> bool: return sample.clear), "sampled actual actor feet remain outside buildings and fences")
	_expect(_audio_count("bus_start") == 1 and _audio_accepted("collect_complete") == (2 if _has_food else 1), "one engine and one completion cue per actual searched source")
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	var callback: Callable = app._finish_callback
	callback.call({})
	sortie.request_bus_action()
	_expect(app.camp_snapshot() == _before and app._pending_settlement == proposal, "finished actions and duplicate callbacks cannot bank or change the pending transaction")
	await _capture("ux-07-result")
	await _check_finished(sortie)
	await _click_control("Interface/Screen/Result/Continue")
	callback.call({})
	_expect(app.camp_snapshot() == proposal and app.run_save.load_save() == OK and app.run_save.snapshot == proposal, "return commits exactly one original v5 transaction")
	_expect(app.cash == int(_before.cash)+4 and app.weapons.size() == _before.weapons.size()+1 and app.day == int(_before.day)+1 and app.loadout == _before.loadout, "existing resources/instances/date/equipment settlement stays unchanged")
	await _capture("ux-08-saved-camp")


func _click_screen(point: Vector2) -> void:
	if is_instance_valid(app.expedition):
		_record_ux(app.expedition, "before_click")
	await super._click_screen(point)
	if is_instance_valid(app.expedition):
		_record_ux(app.expedition, "after_click")


func _capture(file_name: String) -> void:
	await super._capture(file_name)
	if not is_instance_valid(app.expedition) or app.phase != app.Phase.EXPEDITION:
		return
	var hud: C1ExpeditionHud = app.expedition._hud.view
	var screen: Rect2 = get_viewport().get_visible_rect()
	var key: String = "%s:%d:%s:%s" % [app.expedition.layout.id,app.expedition.phase,app.expedition.is_paused,hud._help.visible]
	if _layout_checked.has(key):
		return
	_layout_checked[key] = true
	var failures: Array[String] = []
	var geometry: Array[Dictionary] = []
	for node: Node in hud.find_children("*","Control",true,false):
		var control: Control = node as Control
		if not control.is_visible_in_tree():
			continue
		geometry.append({"name":String(control.name),"rect":control.get_global_rect()})
		if not screen.grow(1).encloses(control.get_global_rect()):
			failures.append(String(control.name)+":outside")
		if control is Label:
			var label: Label = control as Label
			if label.get_line_count()*label.get_line_height() > label.size.y+2:
				failures.append(String(label.name)+":text_clipped")
	_expect(failures.is_empty(), "actual HUD geometry and text fit " + key + ": " + ",".join(failures))
	_expect(not hud.get_node("MissionPanel").get_global_rect().intersects(hud.get_node("ActionsPanel").get_global_rect()), "actual opaque panels do not overlap")
	_layout_samples.append({"state":key,"capture":file_name,"viewport":screen,"controls":geometry,"failures":failures})


func _finish_proof() -> void:
	_write_json("command-chain.json",{"pid":OS.get_process_id(),"events":_ux_trace,"gather_events":_gather_events,
		"layouts":_layout_samples,
		"window_size":DisplayServer.window_get_size(),"viewport_size":get_viewport().get_visible_rect().size,
		"scope":"Native viewport events and existing gameplay/camera intentions. No health/time/reward injection. Same exported EXE/PCK. Software desktop input is separately recorded."})
	await super._finish_proof()
