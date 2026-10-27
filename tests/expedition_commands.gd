extends SceneTree
## Isolated command/state fixtures; playable proof uses the exported native window.

var _failures: int = 0
var _results: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for supply: MissionSupply in [preload("res://src/features/camp/scavenge.tres"), preload("res://src/features/camp/supermarket.tres")]:
		var sortie: Expedition = Expedition.new()
		sortie.supply = supply
		sortie.set_physics_process(false)
		root.add_child(sortie)
		var engines: Array[int] = []
		var gathers: Array[Dictionary] = []
		sortie.engine_started.connect(func() -> void: engines.append(1))
		sortie.bus_gather_ordered.connect(func(state: Dictionary) -> void: gathers.append(state))
		var other_goal: Vector2 = supply.layout.cash_door + Vector2(112,96)
		sortie.command_move(other_goal)
		sortie.request_bus_gather()
		_expect(sortie.goal == other_goal and gathers.is_empty(), "ACTIVE rejects gathering without changing the ground intention")
		sortie.step(20.0)
		sortie.request_extraction()
		sortie.request_bus_gather()
		_expect(sortie.phase == Expedition.Phase.ENGINE and sortie.goal == other_goal and engines.size() == 1 and gathers.is_empty(), "engine starts once and preserves the squad's existing goal")
		sortie.step(3.0)
		_expect(sortie.phase == Expedition.Phase.BOARDING and sortie.goal == other_goal, "waiting is reached without automatic recall")
		sortie.request_search()
		var worker: FieldActor = sortie.search_actor
		worker.activity = FieldActor.Activity.SEARCHING
		worker.hide()
		worker.position = supply.layout.cash_door
		var guard: FieldActor = sortie.survivors[1 - worker.actor_id]
		guard.position = supply.layout.bus_door
		var status: Dictionary = sortie.boarding_status()
		_expect(status.arrived == 1 and status.required == 2 and status.working == 1, "hidden worker remains required and is excluded from arrival")
		worker.position = supply.layout.bus_door
		_expect(sortie.boarding_status().arrived == 1, "searcher standing in the circle still waits for the original work contract")
		worker.position = supply.layout.cash_door
		sortie.toggle_pause()
		var clock: float = sortie.elapsed
		var engine_clock: float = sortie._engine_clock
		var progress: float = sortie.search_progress
		sortie.request_bus_gather()
		var path: PackedVector2Array = guard.path.duplicate()
		var position: Vector2 = guard.position
		sortie.request_bus_gather()
		sortie.step(30.0)
		_expect(sortie.goal == supply.layout.bus_door and gathers.size() == 2 and sortie.boarding_status().ordered, "accepted gather uses each selected map's actual bus door")
		_expect(sortie.elapsed == clock and sortie._engine_clock == engine_clock and sortie.search_progress == progress and guard.position == position and guard.path == path, "paused and repeated gather freezes simulation and preserves the same path")
		_expect(worker == sortie.search_actor and not worker.visible and worker.activity == FieldActor.Activity.SEARCHING and engines.size() == 1, "gather neither cancels hidden work nor restarts engine/audio")
		sortie._cash_site.progress = sortie.tuning.search_seconds - 0.01
		sortie.toggle_pause()
		sortie.step(0.02)
		_expect(sortie.searched and sortie.loot == 4 and worker.visible and sortie.search_actor == null and worker.path[-1].distance_to(supply.layout.bus_door) <= sortie.tuning.boarding_radius, "real search completion pays once and rejoins the latest bus goal")
		guard.activity = FieldActor.Activity.DOWN
		_expect(sortie.boarding_status().required == 1, "DOWN exclusion remains the original evacuation rule")
		worker.position = supply.layout.bus_door + Vector2(sortie.tuning.boarding_radius,0)
		_expect(sortie.boarding_status().arrived == 1, "original radius equality is inside the region")
		worker.position.x += 0.01
		_expect(sortie.boarding_status().arrived == 0, "outside the original radius is not counted")
		sortie.navigation.configure([FieldNavigation.BOUNDS])
		sortie.command_move(other_goal)
		var count: int = gathers.size()
		sortie.request_bus_gather()
		_expect(gathers.size() == count and sortie.goal == other_goal and not sortie.boarding_status().ordered, "unreachable formation never acknowledges a gather or changes the goal")
		sortie._finish(false)
		sortie.request_bus_action()
		sortie.request_bus_gather()
		_expect(sortie.phase == Expedition.Phase.FINISHED and gathers.size() == count and engines.size() == 1, "finished phase rejects all new bus actions")
		sortie.queue_free()
		await process_frame
	var path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			path = argument.trim_prefix("--bh-progress=").get_base_dir().path_join("expedition-commands.json")
	if not path.is_empty():
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"results":_results,"failures":_failures},"\t") + "\n")
	print("BH_EXPEDITION_COMMANDS checks=%d failures=%d" % [_results.size(),_failures])
	quit(0 if _failures == 0 else 1)


func _expect(passed: bool, label: String) -> void:
	_results.append({"passed":passed,"label":label})
	if not passed:
		_failures += 1
		push_error(label)
