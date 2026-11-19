extends SceneTree
## Consecutive food and hardware missions through ordinary controls and isolated durable progress.
const STEP: float = 1.0 / 30.0
const WALL_LIMIT_MS: int = 110000
var app: Node
var checks: Array[Dictionary] = []
var failures: int = 0
var started_ms: int = 0
var finished: bool = false
var search_completions: int = 0
var survivor_hits: int = 0


func _initialize() -> void:
	started_ms = Time.get_ticks_msec()
	root.gui_embed_subwindows = true
	create_timer(float(WALL_LIMIT_MS) / 1000.0).timeout.connect(_timeout)
	call_deferred("_run")


func _check(passed: bool, label: String) -> bool:
	checks.append({"label": label, "pass": passed})
	if not passed:
		failures += 1
		printerr("BH_SMOKE_LOOP_FAIL " + label)
	return passed


func _timeout() -> void:
	if finished:
		return
	_check(false, "full loop completes within 110 seconds")
	_finish()


func _wait(done: Callable, label: String, seconds: int = 20) -> bool:
	var deadline: int = mini(started_ms + WALL_LIMIT_MS, Time.get_ticks_msec() + seconds * 1000)
	# Headless frames can run much faster than the background mission worker.
	while not finished:
		if done.call():
			return _check(true, label)
		if Time.get_ticks_msec() >= deadline:
			break
		await process_frame
	return _check(false, label)


func _advance(world: Expedition, done: Callable, label: String, cap: int = 5400) -> bool:
	for tick: int in range(cap):
		if done.call():
			return _check(true, label)
		if Time.get_ticks_msec() - started_ms >= WALL_LIMIT_MS or world.is_paused:
			break
		# FINISHED still needs stepping while the real bus departure is running.
		if world.phase == Expedition.Phase.FINISHED and not world.bus_view.running():
			break
		world.step(STEP)
		if tick % 30 == 0:
			await process_frame
	if not done.call():
		printerr("BH_SMOKE_LOOP_STATE " + JSON.stringify({"checkpoint": label,
			"elapsed": world.elapsed, "phase": world.phase, "paused": world.is_paused,
			"living": world.living_count(), "notice": world._notice_text}))
	return _check(done.call(), label)


func _load_app() -> bool:
	app = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	return await _wait(func() -> bool:
		return (app.is_node_ready() and not app._startup_pending and app.mission_select != null
			and app.phase == app.Phase.TITLE and app._title.is_visible_in_tree()),
		"default main.tscn reaches title")


func _start_sortie(type: String) -> Expedition:
	var loading_started: int = Time.get_ticks_msec()
	app.open_mission_select()
	if not await _wait(func() -> bool:
		return (app.mission_select.visible and not app.mission_select.loading
			and not app.mission_select.daily_offers.is_empty()), "mission select finishes loading", 90):
		_mission_timing(loading_started)
		return null
	_mission_timing(loading_started)
	var menu: MissionSelect = app.mission_select
	var first: int = -1
	for index: int in range(menu.daily_offers.size()):
		if menu.daily_offers[index].type == type and menu.choices[index].is_visible_in_tree() and not menu.choices[index].disabled:
			first = index
			break
	if not _check(first >= 0, "requested mission is offered: " + type):
		return null
	var expected: Dictionary = menu.daily_offers[first].duplicate(true)
	menu._choose(first)
	if not _check(not menu.depart_button.disabled, "selected mission enables departure confirmation"):
		return null
	menu._confirm_departure()
	if not _check(is_instance_valid(app.expedition) and app.phase == app.Phase.EXPEDITION
		and not app._progress_blocked, "confirmed mission opens Expedition in EXPEDITION phase"):
		return null
	var world: Expedition = app.expedition
	world.set_physics_process(false)
	world.set_process(false)
	if not _check(TransactionReceipt.same(expected, world.supply.generated), "expedition uses selected mission"):
		return null
	if not await _advance(world, func() -> bool: return not world.bus_view.running(),
		"bus arrival completes through simulation", 1500):
		return null
	return world


func _mission_timing(started: int) -> void:
	print("BH_SMOKE_MISSIONS " + JSON.stringify({"day":app.day,
		"wait_ms":Time.get_ticks_msec() - started, "loading":app.mission_select.loading,
		"worker_alive":app._mission_worker != null and app._mission_worker.is_alive()}))


func _observe_hit(event: Dictionary) -> void:
	# Enemy attacks and visual shot traces do not count as survivor damage.
	if int(event.get("member_id", 0)) > 0 and float(event.get("applied_damage", 0.0)) > 0.0:
		survivor_hits += 1


func _run() -> void:
	var entry: Dictionary = PlayableEntry.resolve(OS.get_cmdline_user_args())
	var path: String = entry.progress
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			path = argument.trim_prefix("--bh-progress=")
	if not _check(path.is_absolute_path() and "/.local/" in path
		and path.get_file() == "run.enemy-v1.json"
		and "/.local/" in OS.get_user_data_dir().replace("\\", "/")
		and not FileAccess.file_exists(path), "fresh isolated run.enemy-v1.json profile"):
		_finish()
		return
	if await _load_app():
		await _loop(path)
	await _dispose_app()
	_check(Time.get_ticks_msec() - started_ms < WALL_LIMIT_MS, "full loop completes within 110 seconds")
	_finish()


func _loop(path: String) -> void:
	if not _check(not app._requires_continue and not app._progress_blocked,
		"empty title offers a new journey"):
		return
	app._enter_camp()
	if not _check(app._new_game_confirmation.visible and app._opening_confirm_pending,
		"new journey UI opens opening-plan confirmation"):
		return
	var plan: String = OpeningBuildPicker.PLAN_ORDER[0]
	app._opening_picker._select(plan)
	# ConfirmationDialog normally hides itself before dispatching confirmed.
	app._new_game_confirmation.hide()
	app._confirm_new_journey()
	if not _check(app._camp_open and app.camp_scene.is_visible_in_tree()
		and not app._progress_blocked and not app._progress_dirty
		and OpeningBuild.plan(app.camp_snapshot()) == plan and FileAccess.file_exists(path),
		"first opening plan creates and saves a new camp"):
		return
	var before: Dictionary = app.camp_snapshot().duplicate(true)
	if not _check(before.day == 2 and before.food == 4 and before.crew.size() == 2,
		"official day-two opening has four food and the original pair"):
		return
	var world: Expedition = await _start_sortie("supply")
	if world == null:
		return
	world.search_completed.connect(func(_reward: int) -> void: search_completions += 1)
	world.combat_feedback.connect(_observe_hit)
	var site: Expedition.SearchSite = world.search_site(&"food")
	if not _check(SeasideTown.is_layout(world.layout) and site != null
		and not site.searched and world.site_discovered(site), "day-two seaside food point is available"):
		return
	world.command_move(site.door)
	world.request_search(site.id)
	if not _check(world.search_assignments.member_for(String(site.id)) > 0,
		"real search intention assigns a survivor"):
		return
	if not await _advance(world, func() -> bool: return site.searched and search_completions > 0,
		"assigned survivor completes search and emits completion"):
		return
	if not _check(world.living_count() == 2 and world.food_loot > 0
		and world.tuning.daylight_seconds - world.elapsed >= 20.0,
		"first food search leaves both alive, carried food and at least twenty seconds of daylight"):
		return
	# Spawn through the existing director policy if natural search-time combat has not hit yet.
	# Never manufacture enemies, damage, ammunition, health, rewards, or clock values.
	if survivor_hits == 0:
		world._spawn_enemy()
	if not await _advance(world, func() -> bool: return survivor_hits > 0,
		"survivor combat applies positive damage to an enemy"):
		return
	if not await _return_from(world):
		return
	var preview_text: String = app.get_node("Interface/Screen/Result/Scroll/Body").text
	if not _check(world.elapsed < 105.0 and world.living_count() == 2 and world.food_loot > 0
		and preview_text.contains("归航 2 人") and preview_text.contains("场内阵亡：无")
		and preview_text.contains("顾予安") and preview_text.contains("夏之遥"),
		"daytime frozen preview names the returned pair and reports no field casualties"):
		return
	if not _check(TransactionReceipt.same(before, app.camp_snapshot()), "preview leaves camp and day unchanged"):
		return
	await app._confirm_result_ui()
	if not _check(app.phase == app.Phase.TITLE and app.camp_scene.is_visible_in_tree()
		and app.day == int(before.day) + 1 and app.settled_sorties == int(before.settled_sorties) + 1
		and not app._progress_blocked and not app._progress_dirty and FileAccess.file_exists(path),
		"result Continue advances day and saves camp"):
		return
	var saved: Dictionary = app.camp_snapshot().duplicate(true)
	if not _check(saved.last_day.food_shortage == 0 and saved.food >= 2
		and saved.last_day.food_consumed == 2, "confirmed return feeds original pair and retains next meal"):
		return
	var durable: Dictionary = app.progress_session.inspect()
	if not _check(durable.error == OK and durable.state == "CAMP"
		and TransactionReceipt.same(saved, durable.camp), "durable camp matches settled app state"):
		return
	await _dispose_app()
	if not await _load_app():
		return
	if not _check(app.progress_path == path and app._requires_continue and not app._progress_blocked,
		"fresh app offers Continue for same saved profile"):
		return
	app.continue_game()
	if app._hunger_confirmation.visible:
		app._hunger_confirmation.hide()
		app._hunger_confirmation.confirmed.emit()
	if not _check(not app._requires_continue and not app._progress_blocked
		and TransactionReceipt.same(saved, app.camp_snapshot()), "Continue restores exact saved camp"):
		return
	app._enter_camp()
	var second: Expedition = await _start_sortie("airdrop")
	if second == null: return
	var cabinet: Expedition.SearchSite = second.search_site(&"cash")
	if not _check(EconomyActions.hardware(second.supply.generated) and cabinet != null and second.site_discovered(cabinet),
		"day-three equipment card offers the real hardware cabinet"): return
	second.command_move(cabinet.door)
	second.request_search(cabinet.id)
	if not await _advance(second, func() -> bool: return cabinet.searched, "second outing recovers the hardware without searching for food"): return
	if not _check(second.food_loot == 0 and second._carried_tools() == 2, "two tools and no field rations carried"): return
	if not await _return_from(second): return
	await app._confirm_result_ui()
	var returned: Dictionary = app.camp_snapshot()
	if not _check(returned.settled_sorties == 2 and returned.day == 4 and RosterState.living_count(returned) == 2
		and returned.last_day.food_before == saved.food and returned.last_day.food_found == 0
		and returned.last_day.food_consumed == 2 and returned.food == saved.food - 2
		and EconomyBuildV1.tools(returned) == EconomyBuildV1.tools(saved) + 2,
		"banked food covers the equipment night and both recovered tools reach camp"): return
	var identity: String = returned.profile_id + ":edit:" + RunSave.new_profile_id()
	await app.confirm_economy_edit(EconomyBuildV1.request(returned, "build", "supply", "", identity))
	var built: Dictionary = app.camp_snapshot()
	_check(EconomyBuildV1.level(built, "supply") == 1 and built.cash == returned.cash - 12
		and EconomyBuildV1.tools(built) == EconomyBuildV1.tools(returned) - 1 and built.food == returned.food
		and TransactionReceipt.same(built.last_day, returned.last_day),
		"building supply spends the recovered tool and twelve coins without changing last night's meal")


func _return_from(world: Expedition) -> bool:
	world.command_move(world.layout.bus_door)
	if not await _advance(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds,
		"bus becomes ready through simulation"):
		return false
	world.request_bus_action()
	if not _check(world.phase == Expedition.Phase.ENGINE, "real bus action starts engine"):
		return false
	if not await _advance(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING,
		"engine reaches boarding phase"):
		return false
	world.request_bus_gather()
	if not await _advance(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED,
		"real gather finishes sortie"):
		return false
	if not await _advance(world, func() -> bool: return (app.phase == app.Phase.RESULT
		and not world.bus_view.running()), "bus departs and result preview opens", 1500):
		return false
	var gathered: Vector2i = world.bus_view.final_boarding
	if not _check(world.living_count() > 0 and gathered.x == gathered.y
		and gathered.y == world.living_count() and app._result.is_visible_in_tree()
		and not app._pending_settlement.is_empty(), "living survivors extracted into visible frozen preview"):
		return false
	return true


func _dispose_app() -> void:
	if is_instance_valid(app):
		var playbacks: Array[WeakRef] = []
		if is_instance_valid(app.audio):
			for player: AudioStreamPlayer in app.audio._ui_players + app.audio._world_players:
				if player.has_stream_playback():
					playbacks.append(weakref(player.get_stream_playback()))
			app.audio.shutdown()
		app.queue_free()
		app = null
		await process_frame
		# The audio mixer retires stopped streams on its own clock.
		var deadline: int = Time.get_ticks_usec() + 200_000
		while playbacks.any(func(ref: WeakRef) -> bool: return ref.get_ref() != null) \
				and Time.get_ticks_usec() < deadline:
			await process_frame
		await process_frame


func _finish() -> void:
	if finished:
		return
	finished = true
	print("BH_SMOKE_LOOP " + JSON.stringify({"failures": failures, "checks": checks}, "", false))
	quit(0 if failures == 0 else 1)
