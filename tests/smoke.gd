extends SceneTree
## Tests scene ownership and re-entry: duplicate transitions must not leak worlds.

const MainScene: PackedScene = preload("res://src/app/main.tscn")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	_expect(main.phase == main.Phase.TITLE, "starts at title")
	_expect(InputMap.has_action("place_probe"), "probe action is configured")
	for iteration: int in range(3):
		main.open_validation()
		main.open_validation()
		_expect(main.phase == main.Phase.VALIDATION, "enters validation")
		_expect(main.get_node("World").get_child_count() == 1, "duplicate entry is idempotent")
		var marker: Sprite2D = main.get_node("World/Validation/Marker") as Sprite2D
		_expect(marker.texture != null and marker.texture.get_width() == 128, "PNG imported")
		main.return_to_title()
		main.return_to_title()
		await process_frame
		_expect(main.get_node("World").get_child_count() == 0, "exit releases scene")
		_expect(main.phase == main.Phase.TITLE, "returns to title")
	main.open_validation()
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_expect(escape.is_action_pressed("return_to_title"), "semantic Escape matches without scan code")
	Input.parse_input_event(escape)
	await process_frame
	_expect(main.phase == main.Phase.TITLE, "Escape follows the input pipeline")
	await _check_p03(main)
	await _check_sortie(main)
	main.queue_free()
	await process_frame
	# The Dummy mixer releases playback references asynchronously after node exit.
	await create_timer(0.15).timeout
	print("BH_SMOKE failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_p03(main: Node) -> void:
	main.open_practice()
	var practice: Expedition = main.expedition
	practice.set_physics_process(false)
	practice.step(1.4)
	_expect(practice.survivors[0].health == 196.0, "practice contact applies one ordinary enemy attack")
	var actor: FieldActor = practice.survivors[0]
	actor.aim = Vector2.ZERO
	actor.command_path(PackedVector2Array([actor.position + Vector2(100, 0)]))
	actor.visual.show_hit()
	actor.visual.show_fire(Vector2.RIGHT)
	var before: Vector2 = actor.position
	var health: float = actor.health
	actor.advance(0.1)
	_expect(is_equal_approx(actor.position.x - before.x, actor.speed * 0.1), "hit and fire visuals do not lock movement")
	_expect(actor.health == health, "visual advancement cannot apply repeated damage")
	practice.step(0.65)
	_expect(practice.kills == 1 and practice.enemies.is_empty(), "defeated enemy leaves combat immediately")
	_expect(practice._corpses.size() == 1 and practice._corpses[0].visual.motion_state == &"defeated", "defeated enemy remains briefly as a presentation only corpse")
	var corpse: FieldActor = practice._corpses[0]
	var corpse_before: Dictionary = corpse.visual.presentation_state()
	practice.request_extraction()
	_expect(not practice._readouts.visible, "result transition hides member readouts immediately without another step")
	practice.command_move(Vector2(1500, 1000))
	practice.request_search()
	practice.step(10.0)
	_expect(corpse.visual.presentation_state() == corpse_before, "finished scene freezes corpse animation and ignores battlefield commands")
	_expect(main.day == 2 and main.cash == 53 and main.settled_sorties == 0 and main.crew_health[0] == 200.0, "practice result cannot alter camp state")
	main.return_to_title()
	await process_frame
	print("BH_P03_TEST movement/damage/corpse/freeze/practice checked")


func _check_sortie(main: Node) -> void:
	main.open_expedition()
	main.open_expedition()
	var sortie: Expedition = main.expedition
	var expected_cash: int = main.cash + sortie.tuning.search_reward
	sortie.set_physics_process(false)
	sortie.tuning.enemy_damage = 0.0
	_check_camera(sortie)
	_check_block_routes(sortie.navigation)
	_expect(main.get_node("World").get_child_count() == 1, "sortie entry is idempotent")
	sortie.toggle_pause()
	var before: Vector2 = sortie.survivors[0].position
	sortie.command_move(Vector2(1180, 400))
	sortie.step(60.0)
	_expect(sortie.elapsed == 0.0 and sortie.survivors[0].position == before, "pause freezes time and movement but accepts order")
	sortie.toggle_pause()
	sortie.step(0.2)
	_expect(sortie.survivors[0].position != before, "unpause executes pending order")
	var replacement: Vector2 = sortie.layout.bus_door + Vector2(-344, -200)
	sortie.command_move(replacement)
	for tick: int in range(240):
		sortie.step(0.025)
		for actor: FieldActor in sortie.survivors:
			_expect(not sortie.layout.bus_block.grow(8.0).has_point(actor.position), "moving footprint stays outside bus")
	for actor: FieldActor in sortie.survivors:
		var target: Vector2 = replacement + Vector2.ONE * ((float(actor.actor_id) - 0.5) * sortie.tuning.squad_spacing)
		_expect(actor.position.distance_to(target) <= FieldNavigation.CELL, "both units obey replacement target with formation spacing and grid snapping")
	sortie.request_extraction()
	_expect(sortie.phase == Expedition.Phase.ACTIVE, "bus cannot start before ready")
	sortie.request_search()
	var assigned: FieldActor = sortie.search_actor
	sortie.command_move(Vector2(1180, 520))
	_expect(sortie.search_actor == assigned, "ground order does not cancel assigned search")
	sortie.toggle_pause()
	sortie.request_search()
	_expect(sortie.search_actor == null and assigned.visible and assigned.activity == FieldActor.Activity.MOVING, "left target again cancels before entry and restores group intent while paused")
	_expect(sortie.loot == 0, "cancel before entry pays nothing")
	sortie.request_search()
	sortie.toggle_pause()
	for tick: int in range(1600):
		sortie.step(0.025)
		if sortie.search_actor != null and sortie.search_actor.activity == FieldActor.Activity.SEARCHING:
			break
	_expect(sortie.search_actor != null, "search assigned")
	if sortie.search_actor != null:
		_expect(not sortie.search_actor.visible, "searcher enters building")
	var progress: float = sortie.search_progress
	var inside: FieldActor = sortie.search_actor
	sortie.toggle_pause()
	sortie.command_move(Vector2(1180, 520))
	sortie.step(60.0)
	_expect(sortie.search_progress == progress and sortie.loot == 0, "paused search cannot complete or reward")
	_expect(inside != null and not inside.visible, "ground order leaves indoor searcher working")
	sortie.request_search()
	_expect(inside.visible and inside.activity == FieldActor.Activity.MOVING and sortie.search_actor == null, "cancel indoors immediately reveals and restores latest group target")
	_expect(sortie.search_progress == progress and sortie.loot == 0, "cancel preserves partial work without reward")
	sortie.request_search()
	# Arrange a ready bus while the new search assignment is still active.
	sortie.elapsed = sortie.tuning.bus_ready_seconds
	sortie.request_extraction()
	sortie.request_extraction()
	_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.search_actor != null, "engine starts without cancelling search")
	sortie.toggle_pause()
	for tick: int in range(1600):
		sortie.step(0.025)
	_expect(sortie.searched and sortie.loot == sortie.tuning.search_reward, "search rewards once at completion")
	sortie.request_search()
	sortie.step(1.0)
	_expect(sortie.loot == sortie.tuning.search_reward, "searched building cannot pay twice")
	_expect(sortie.kills > 0, "nearby enemies trigger automatic fire")
	_expect(sortie.phase == Expedition.Phase.BOARDING and main.settled_sorties == 0, "engine starts remotely but waits for survivors")
	sortie.command_move(sortie.layout.bus_door)
	for tick: int in range(800):
		sortie.step(0.025)
	_expect(main.phase == main.Phase.RESULT, "extraction reaches result")
	_expect(main._pending_settlement.cash == expected_cash and main.settled_sorties == 0, "result previews reward without banking it")
	sortie.step(100.0)
	_expect(main._pending_settlement.cash == expected_cash and main.settled_sorties == 0, "finished sortie cannot duplicate preview")
	main.return_to_title()
	await process_frame
	_expect(main.cash == expected_cash and main.settled_sorties == 1 and main.food == 0, "camp commits one reward and one daily ration")
	_expect(main.get_node("World").get_child_count() == 0, "completed sortie is freed")
	main.open_expedition()
	var next: Expedition = main.expedition
	next.set_physics_process(false)
	_expect(not next.searched and next.loot == 0 and next.day == 3, "new sortie resets local state and receives camp day")
	for actor: FieldActor in next.survivors:
		actor.take_damage(10000.0)
	next.step(0.025)
	_expect(main.phase == main.Phase.RESULT and main.cash == expected_cash, "prototype defeat exits without invented loot")
	main.return_to_title()
	await process_frame
	main.reset_demo()
	_expect(main._new_game_confirmation.visible, "restart requires explicit confirmation and preserves saved progress")
	main._new_game_confirmation.confirmed.emit()
	main._new_game_confirmation.hide()
	_expect(main.day == 2 and main.cash == 53 and main.crew_health[0] == 200.0, "explicit demo restart restores only session state")
	print("BH_SORTIE_TEST navigation/pause/search/combat/extraction/settlement/reentry passed=%s" % (_failures == 0))


func _check_camera(sortie: Expedition) -> void:
	var camera: FieldCamera = sortie.camera
	camera.set_process(false)
	var before_tap: Vector2 = camera.position
	var tap: InputEventKey = InputEventKey.new()
	tap.keycode = KEY_W
	tap.pressed = true
	_expect(tap.is_action_pressed("camera_up"), "semantic W matches camera input")
	camera._unhandled_input(tap)
	tap.pressed = false
	camera._unhandled_input(tap)
	camera._process(1.0 / 60.0)
	_expect(camera.position.y < before_tap.y, "press/release within one frame still pans camera")
	var screen_point: Vector2 = Vector2(700, 400)
	var original: Vector2 = camera.screen_to_world(screen_point)
	camera.zoom_at(screen_point, 1.1)
	_expect(camera.screen_to_world(screen_point).distance_to(original) < 0.1, "zoom preserves pointer's world anchor away from boundary")
	var engine_point: Vector2 = sortie.get_global_transform_with_canvas().affine_inverse() * screen_point
	_expect(engine_point.distance_to(camera.screen_to_world(screen_point)) < 0.1, "camera math agrees with engine click transform")
	camera.pan_by(Vector2(100000, 100000))
	var clamped: Vector2 = camera.position
	camera.pan_by(Vector2(1000, 1000))
	_expect(camera.position == clamped, "camera stops at map edge")
	camera.zoom_at(screen_point, 100.0)
	_expect(is_equal_approx(camera.zoom.x, camera.max_zoom), "zoom-in is bounded")
	camera.zoom_at(screen_point, 0.001)
	_expect(is_equal_approx(camera.zoom.x, camera.min_zoom), "zoom-out is bounded")
	# Camera controls do not advance the expedition's gameplay clock.
	_expect(sortie.elapsed == 0.0, "camera leaves simulation state unchanged")
	print("BH_CAMERA_TEST anchor/transform/bounds/independence checked")


func _check_block_routes(navigation: FieldNavigation) -> void:
	var stops: Array[Vector2] = [Vector2(488, 760), Vector2(632, 280),
		Vector2(900, 620), Vector2(1200, 980), Vector2(632, 1320),
		Vector2(80, 808), Vector2(440, 864)]
	for index: int in range(stops.size() - 1):
		var path: PackedVector2Array = navigation.path_between(stops[index], stops[index + 1])
		_expect(path.size() > 1, "street route is reachable")
		for segment: int in range(path.size() - 1):
			var samples: int = ceili(path[segment].distance_to(path[segment + 1]) / 4.0)
			for sample: int in range(samples + 1):
				var point: Vector2 = path[segment].lerp(path[segment + 1], float(sample) / maxi(1, samples))
				for block: Rect2 in navigation.obstacles:
					_expect(not block.grow(8.0).has_point(point), "street route preserves building and bus footprint clearance")
	print("BH_STREET_TEST six routes / continuous clearance checked")


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("BH_SMOKE: " + label)
