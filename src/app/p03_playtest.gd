class_name P03Playtest
extends Node
## Opt-in native-renderer verification. Calls gameplay intents, never alters health or clocks.

var app: Node
var output_dir: String
var _failures: Array[String] = []
var _captures: Array[Dictionary] = []
var _feedback: Array[Dictionary] = []
var _captured_events: Dictionary[String, bool] = {}
var _checks: int = 0
var _crossing: bool = false
var _closest_crossing: float = INF
var _badges_overlapped: bool = false


func _physics_process(_delta: float) -> void:
	if _crossing:
		var sortie: Expedition = app.expedition
		_closest_crossing = minf(_closest_crossing, sortie.survivors[0].position.distance_to(sortie.survivors[1].position))
		if sortie._readouts.entries.size() == 2:
			_badges_overlapped = _badges_overlapped or sortie._readouts.entries[0]["rect"].intersects(sortie._readouts.entries[1]["rect"])


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("P03 playtest requires a native rendering window.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	app.get_node("World").child_entered_tree.connect(_connect_feedback)
	print("BH_P03_VERIFY build=%s display=%s renderer=%s input=engine_mouse_events_and_gameplay_intents" % [Expedition.BUILD_ID, DisplayServer.get_name(), RenderingServer.get_current_rendering_method()])
	await _capture("p032-001-camp")
	await _click_control("Interface/Screen/Title/Practice")
	var practice: Expedition = app.expedition
	_expect(practice != null and practice.is_practice, "practice entered through viewport mouse event")
	await _capture("p032-002-before-hit-200")
	_expect(practice.survivors[0].health == 200.0, "same practice scene begins visibly at 200 health")
	await _wait(2.8)
	_expect(practice.survivors[0].health == 196.0, "ordinary enemy attack reduces visible 200 to 196")
	await _capture("p032-003-after-hit-196")
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var labels: Array[String] = ["east", "west", "north", "south"]
	var captions: Array[String] = ["向东", "向西", "向北", "向南"]
	var views: Array[WeaponPresentation] = [ActorVisual.CarbineView, ActorVisual.LongRifleView]
	for view: WeaponPresentation in views:
		practice.practice_weapon(view)
		for index: int in range(directions.size()):
			var direction: Vector2 = directions[index]
			var incoming: Vector2 = Vector2(1.0, -0.20) if index == 0 else direction
			var first_event: int = _feedback.size()
			practice.practice_incoming(incoming)
			practice._show_notice("%s · %s站立开火" % [view.display_name, captions[index]])
			await _wait(0.8)
			practice.practice_incoming(incoming)
			practice._show_notice("%s · %s站立开火" % [view.display_name, captions[index]])
			await _capture("p032-" + String(view.id) + "-" + labels[index] + "-standing")
			await _wait(1.2)
			var centre: Vector2 = (practice.survivors[0].position + practice.survivors[1].position) * 0.5
			practice.command_move(centre + direction * 112.0)
			practice.practice_incoming(direction)
			practice._show_notice("%s · %s移动开火" % [view.display_name, captions[index]])
			await _wait(0.35)
			await _capture("p032-" + String(view.id) + "-" + labels[index] + "-moving")
			await _wait(1.65)
			var standing: bool = false
			var moving: bool = false
			for event: Dictionary in _feedback.slice(first_event):
				if event["kind"] == "shot" and event["actor"] == 0 and event["weapon"] == String(view.id):
					var facing: Vector2 = event["facing"]
					if facing.dot(direction) > 0.75:
						standing = standing or not event["moving"]
						moving = moving or event["moving"]
			_expect(standing and moving, "%s %s has actual standing and moving combat events" % [view.id, labels[index]])
	_crossing = true
	practice.practice_cross()
	await _wait(0.25)
	await _capture("p032-crossing")
	await _wait(0.75)
	_crossing = false
	_expect(_closest_crossing < 16.0 and not _badges_overlapped, "actual crossing keeps separate readouts without adding avoidance")
	practice.request_extraction()
	await _capture("p032-practice-result")
	await _check_finished(practice)
	await _capture("p032-practice-frozen")
	await _click_control("Interface/Screen/Result/Continue")
	_expect(app.day == 2 and app.cash == 53 and app.crew_health[0] == 200.0 and app.settled_sorties == 0, "practice never mutates campaign")
	if "--presentation-only" not in OS.get_cmdline_user_args():
		await _sortie_regression()
	var report: Dictionary = {"build": Expedition.BUILD_ID, "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "input": "engine viewport mouse events and gameplay/practice intents; desktop input verified separately",
		"checks": _checks, "behavior_checks": _checks - _captures.size(), "capture_checks": _captures.size(),
		"failures": _failures, "captures": _captures, "combat_events": _feedback,
		"cash": app.cash, "day": app.day, "settled_sorties": app.settled_sorties,
		"crossing": {"closest_logical_distance": _closest_crossing, "badges_overlapped": _badges_overlapped}}
	var file: FileAccess = FileAccess.open(output_dir.path_join("run-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("BH_P03_VERIFY behavior_checks=%d capture_checks=%d failures=%d" % [_checks - _captures.size(), _captures.size(), _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _sortie_regression() -> void:
	await _click_control("Interface/Screen/Title/Start")
	await _click_screen(app.mission_select.choices[1].get_global_rect().get_center())
	var sortie: Expedition = app.expedition
	await _capture("p03-013-sortie-default")
	sortie.command_move(Vector2(928, 650))
	sortie.request_search()
	await _until_inside(sortie)
	await _wait(3.0)
	sortie.toggle_pause()
	var progress: float = sortie.search_progress
	var worker: FieldActor = sortie.search_actor
	sortie.command_move(Vector2(900, 650))
	_expect(sortie.search_actor == worker, "ground intent does not cancel work")
	sortie.request_search()
	_expect(worker.visible and sortie.loot == 0 and sortie.search_actor == null, "indoor cancel reveals worker without reward")
	await _capture("p03-014-cancel")
	sortie.request_search()
	_expect(sortie.search_progress == progress, "TMP-107 remains explicit partial progress behavior")
	sortie.toggle_pause()
	await _until_inside(sortie)
	while sortie.elapsed < sortie.tuning.bus_ready_seconds:
		await _wait(0.1)
	sortie.request_extraction()
	_expect(sortie.search_actor != null and not sortie.searched, "engine begins while search remains active")
	await _capture("p03-015-engine-during-search")
	await _wait(3.2)
	_expect(sortie.phase == Expedition.Phase.BOARDING, "engine reaches waiting")
	sortie.command_move(Vector2(928, 650))
	await _capture("p03-016-waiting-work")
	var search_limit: int = 0
	while not sortie.searched and search_limit < 400:
		await _wait(0.1)
		search_limit += 1
	_expect(sortie.searched and sortie.loot == 4, "search completes and pays once")
	sortie.request_search()
	_expect(sortie.loot == 4, "completed target cannot pay twice")
	await _wait(3.0)
	await _capture("p03-017-completed-rejoined")
	# Test actual actor paths around the same buildings and bus as ordinary commands.
	sortie.command_move(Vector2(632, 320))
	await _wait(7.0)
	await _capture("p03-018-building-back")
	sortie.command_move(Vector2(264, 720))
	await _wait(7.0)
	await _capture("p03-019-bus-back")
	sortie.command_move(Vector2(96, 808))
	await _wait(3.0)
	sortie.camera.zoom_at(Vector2(640, 360), 0.70 / sortie.camera.zoom.x)
	await _capture("p03-020-bus-left")
	sortie.command_move(sortie.layout.bus_door)
	var result_limit: int = 0
	while app.phase != app.Phase.RESULT and result_limit < 200:
		await _wait(0.1)
		result_limit += 1
	_expect(app.phase == app.Phase.RESULT and app._pending_settlement.cash == 57 and app.settled_sorties == 0, "evacuation prepares one settlement; camp commits it")
	await _capture("p03-021-result")
	await _check_finished(sortie)
	await _capture("p03-022-result-frozen")
	await _click_control("Interface/Screen/Result/Continue")
	await _capture("p03-023-camp-after")
	await _click_control("Interface/Screen/Title/Start")
	await _click_screen(app.mission_select.choices[1].get_global_rect().get_center())
	var next: Expedition = app.expedition
	_expect(next.day == 3 and next.loot == 0 and not next.searched and next.kills == 0 and next.phase == Expedition.Phase.ACTIVE, "actual second sortie has no local state residue")
	await _capture("p03-024-second-sortie")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _click_control(path: NodePath) -> void:
	var control: Control = app.get_node(path) as Control
	await _click_screen(control.get_global_rect().get_center())


func _click_world(sortie: Expedition, point: Vector2) -> void:
	await _click_screen(sortie.get_global_transform_with_canvas() * point)


func _click_screen(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _until_inside(sortie: Expedition) -> void:
	var limit: int = 0
	while sortie.search_actor != null and sortie.search_actor.activity != FieldActor.Activity.SEARCHING and limit < 150:
		await _wait(0.1)
		limit += 1
	_expect(sortie.search_actor != null and sortie.search_actor.activity == FieldActor.Activity.SEARCHING, "worker actually reaches indoor search")


func _check_finished(sortie: Expedition) -> void:
	var before: Dictionary = _world_state(sortie)
	sortie.command_move(Vector2(1200, 800))
	sortie.request_search()
	sortie.request_extraction()
	sortie.step(5.0)
	await _wait(1.5)
	_expect(before == _world_state(sortie), "finished battlefield, animations and resources stay frozen despite commands")


func _world_state(sortie: Expedition) -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor: FieldActor in sortie.survivors + sortie.enemies + sortie._corpses:
		actors.append({"id": actor.actor_id, "enemy": actor.is_enemy, "position": [actor.position.x, actor.position.y],
			"health": actor.health, "activity": actor.activity, "visual": actor.visual.presentation_state()})
	var readouts: Array[Dictionary] = []
	for entry: Dictionary in sortie._readouts.entries:
		var rect: Rect2 = entry["rect"]
		readouts.append({"id": entry["id"], "health": entry["health"], "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	var effects: Array[Dictionary] = []
	for effect: CanvasItem in sortie._effects.get_children():
		var point: Vector2 = (effect as Node2D).position if effect is Node2D else (effect as Control).position
		effects.append({"position": point, "modulate": effect.modulate})
	return {"phase": sortie.phase, "elapsed": sortie.elapsed, "progress": sortie.search_progress,
		"loot": sortie.loot, "kills": sortie.kills, "goal": sortie.goal, "actors": actors, "effects": effects,
		"camera": sortie.camera.position, "zoom": sortie.camera.zoom, "readouts": readouts}


func _connect_feedback(child: Node) -> void:
	if child is Expedition:
		(child as Expedition).combat_feedback.connect(_on_feedback)


func _on_feedback(event: Dictionary) -> void:
	_feedback.append(event.duplicate())
	var kind: String = event["kind"]
	if kind == "shot" and event["moving"]:
		kind = "move_fire"
	if kind in ["hit", "defeat", "move_fire"] and not _captured_events.has(kind):
		_captured_events[kind] = true
		_capture.call_deferred("p03-event-" + kind)


func _capture(label: String) -> void:
	# Let the normal physics/UI refresh consume just-issued intents before saving pixels.
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	var result: Error = picture.save_png(output_dir.path_join(label + ".png"))
	_expect(result == OK, "native viewport capture saved: " + label)
	var capture: Dictionary = {"file": label + ".png", "app_phase": app.phase, "cash": app.cash, "day": app.day,
		"movie_frame": Engine.get_frames_drawn()}
	if app.expedition != null:
		capture["world"] = _world_state(app.expedition)
	_captures.append(capture)
	print("BH_P03_FRAME %s" % label)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("BH_P03_VERIFY " + label)
