extends "res://tests/level_flow.gd"
## Normal isolated M15 equipment action. The test steps the real simulation and sends viewport clicks.

const NEAR_FIRST: StringName = &"cash_2"
const NEAR_SECOND: StringName = &"optional_b14"


func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _menu()
	var slot: int = -1
	for index: int in range(app.mission_select.daily_offers.size()):
		var offer: Dictionary = app.mission_select.daily_offers[index]
		if offer.type == "equipment" and offer.layout["size"] == "medium":
			slot = index
	_check(slot >= 0, "ordinary cards include the medium equipment fixture")
	if slot < 0:
		return
	var world: Expedition = await _start(slot)
	if world == null:
		return
	var small: bool = "--loot-small" in OS.get_cmdline_user_args()
	if small:
		viewport.size = Vector2i(1024, 576)
		world.camera.force_update_scroll()
	await _hold(4)
	acceptance = {
		"departure":_before.duplicate(true), "action":world.supply.generated.id,
		"seed":world.supply.generated.seed, "layout_seed":world.supply.generated.layout.seed,
		"camera":[world.camera.position.x, world.camera.position.y],
		"zoom":world.camera.zoom.x, "viewport":[viewport.size.x, viewport.size.y],
		"arrival_elapsed":world.elapsed,
	}
	_check(world.living_count() == 2 and is_equal_approx(world.camera.zoom.x, 0.82), "ordinary arrival has two live members and default zoom")
	var first: Expedition.SearchSite = world.search_site(NEAR_FIRST)
	var second: Expedition.SearchSite = world.search_site(NEAR_SECOND)
	var car: Expedition.SearchSite = world.search_site(&"vehicle_01")
	var primary: Expedition.SearchSite = world.search_site(&"cash")
	_check(first != null and second != null and car != null and primary != null, "frozen equipment action includes both near buildings, a vehicle and its real main site")
	if first == null or second == null or car == null or primary == null:
		return
	var actual_primary: Array = world.supply.generated.objective.site_ids
	var trees: int = 0
	for site: Expedition.SearchSite in world.sites:
		_expect_available(site, actual_primary.has(String(site.id)))
		if site.prop.loot_category == "果树":
			trees += 1
	_check(trees > 0 and car.prop.loot_category == "车辆", "original fruit and vehicle sites use their own category text")
	var on_screen: Array[Rect2] = []
	var opening: Array[Dictionary] = []
	for site: Expedition.SearchSite in [first, second, car]:
		var rect: Rect2 = _screen_badge(site)
		if viewport.get_visible_rect().encloses(rect):
			on_screen.append(rect)
			_check(site.prop._work.get_line_count() == site.prop._work.get_visible_line_count(),
				"near badge text is not clipped for " + String(site.id))
		opening.append(_describe_site(world, site))
	_check(on_screen.size() >= 2, "normal arrival shows at least two full near badges inside the viewport")
	for left: int in range(on_screen.size()):
		for right: int in range(left + 1, on_screen.size()):
			_check(not on_screen[left].intersects(on_screen[right]), "near badges have distinct screen bounds")
	acceptance["arrival"] = opening
	await _shot("arrival")
	world.locate_objective("primary")
	_check(world._locate_ring != null and world._locate_ring.global_position.is_equal_approx(primary.door),
		"objective locator ring is centered on the actual entrance")
	await _shot("main-site")
	_check(viewport.get_visible_rect().encloses(_screen_badge(primary)) and primary.prop._work.text.contains("主目标"),
		"the actual equipment site has a readable main-objective badge")
	if small:
		_write("acceptance.json", acceptance)
		return
	var arrival_camera: Array = acceptance.camera
	world.camera.pan_by(Vector2(arrival_camera[0], arrival_camera[1]) - world.camera.position)
	await _click_site(world, first)
	await _click_site(world, second)
	var first_member: int = _assigned(world, first)
	var second_member: int = _assigned(world, second)
	_check(first_member > 0 and second_member > 0 and first_member != second_member, "two actual map clicks independently assign different members")
	if first_member <= 0 or second_member <= 0 or first_member == second_member:
		return
	_expect_worker(world, first, "前往")
	_expect_worker(world, second, "前往")
	await _shot("two-assigned")
	await _until(world, func() -> bool: return first.progress > 0.5 and second.progress > 0.5 and not first.searched and not second.searched)
	_expect_worker(world, first, "搜集中")
	_expect_worker(world, second, "搜集中")
	await _shot("two-working")
	var retained: float = first.progress
	var other_progress: float = second.progress
	await _click_site(world, first)
	_expect_available(first, false)
	_check(_assigned(world, first) == 0 and _assigned(world, second) == second_member
		and first.progress == retained and first.prop._bar.visible, "cancelling the first job restores its badge and retains progress and the second worker")
	await _until(world, func() -> bool: return second.progress > other_progress + 0.3)
	_expect_worker(world, second, "搜集中")
	await _shot("one-cancelled")
	await _click_site(world, first)
	await _until(world, func() -> bool: return first.progress > retained + 0.1)
	_expect_worker(world, first, "搜集中")
	_expect_worker(world, second, "搜集中")
	acceptance["in_progress"] = [_describe_site(world, first), _describe_site(world, second)]
	if "--loot-suspend" in OS.get_cmdline_user_args():
		await _suspend(world)
		return
	await _complete_and_return(world, first, second)


func _resume() -> void:
	var first_output: String = output.get_base_dir().path_join("first")
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first_output.path_join("checkpoint.json")))
	acceptance = JSON.parse_string(FileAccess.get_file_as_string(first_output.path_join("acceptance.json")))
	_before = acceptance.departure
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_check(world != null, "ordinary Continue opens the acknowledged isolated checkpoint")
	if world == null:
		return
	world.set_process(false)
	world.set_physics_process(false)
	_check(OS.get_process_id() != prior.pid and RecordEncoding.fingerprint(SortieSnapshot.capture(world)) == prior.fingerprint,
		"new PID restores the exact existing site, job, path and world data")
	if app.pause_menu.visible:
		await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()
	await _hold(3)
	var first: Expedition.SearchSite = world.search_site(NEAR_FIRST)
	var second: Expedition.SearchSite = world.search_site(NEAR_SECOND)
	_expect_worker(world, first, "搜集中")
	_expect_worker(world, second, "搜集中")
	var recovered: Array[Dictionary] = [_describe_site(world, first), _describe_site(world, second)]
	for index: int in range(recovered.size()):
		var saved: Dictionary = acceptance.in_progress[index]
		_check(recovered[index].member == int(saved.member) and recovered[index].phase == saved.phase
			and recovered[index].text == saved.text and is_equal_approx(recovered[index].progress, float(saved.progress))
			and is_equal_approx(recovered[index].bar, float(saved.bar)), "restored badge reflects the same member, actual phase and progress")
	acceptance["restored"] = {"pid":OS.get_process_id(), "old_pid":prior.pid, "sites":recovered}
	await _shot("restored-working")
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	await _complete_and_return(world, first, second)


func _complete_and_return(world: Expedition, first: Expedition.SearchSite, second: Expedition.SearchSite) -> void:
	await _until(world, func() -> bool: return first.searched and second.searched)
	for site: Expedition.SearchSite in [first, second]:
		_check(site.prop._work.visible and site.prop._work.text.contains("已搜") and not site.prop._work.text.contains("可搜")
			and not site.prop._bar.visible and _assigned(world, site) == 0, "completed building removes the available prompt and work bar")
	acceptance["completed_near"] = [_describe_site(world, first), _describe_site(world, second)]
	await _shot("near-completed")
	var primary: Expedition.SearchSite = world.search_site(&"cash")
	world.locate_objective("primary")
	await _hold(2)
	await _click_world_point(world, world._locate_ring.global_position)
	_check(_assigned(world, primary) > 0, "clicking the locator ring center starts the original main job")
	await _until(world, func() -> bool: return primary.searched)
	_check(not primary.prop._work.text.contains("可搜") and world.weapon_loot.size() == 1,
		"completing the main job removes its available text and grants one real weapon")
	await _shot("main-completed")
	await _finish_level(world)


func _expect_available(site: Expedition.SearchSite, primary: bool) -> void:
	var label: Label = site.prop._work
	_check(label.visible and label.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and not site.prop.loot_category.is_empty() and label.text.contains("可搜")
		and label.text.contains(site.prop.loot_category) and label.text.contains(site.prop.reward_hint)
		and label.text.contains("主目标") == primary, "available " + String(site.id) + " shows its real category, reward and objective role")


func _expect_worker(world: Expedition, site: Expedition.SearchSite, action: String) -> void:
	var worker: FieldActor = world.search_member(_assigned(world, site))
	var label: Label = site.prop._work
	_check(worker != null and label.text.contains(SearchWorkView.short_call_sign(worker.call_sign))
		and label.text.contains(action) and label.text.contains("再点取消") and not label.text.contains("可搜"),
		"assigned " + String(site.id) + " shows real worker, stage and cancellation")
	if action == "搜集中":
		_check(site.prop._bar.visible and site.prop._bar.value > 0.0, "the original work bar displays ongoing progress")


func _assigned(world: Expedition, site: Expedition.SearchSite) -> int:
	return world.search_assignments.member_for(String(site.id))


func _screen_badge(site: Expedition.SearchSite) -> Rect2:
	var label: Label = site.prop._work
	return label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, label.size)


func _describe_site(world: Expedition, site: Expedition.SearchSite) -> Dictionary:
	var label: Label = site.prop._work
	var rect: Rect2 = _screen_badge(site)
	var member: int = _assigned(world, site)
	return {
		"id":String(site.id), "member":member, "phase":world.search_assignments.phase_for(member),
		"progress":site.progress, "bar":site.prop._bar.value, "searched":site.searched,
		"text":label.text, "screen_rect":[rect.position.x, rect.position.y, rect.size.x, rect.size.y],
	}


func _click_site(world: Expedition, site: Expedition.SearchSite) -> void:
	await _hold(2)
	var point: Vector2 = site.prop._work.get_global_rect().get_center()
	var badge_over_hit: bool = site.hit.has_point(point) and site.prop.scaled_hit_contains(point)
	_check(badge_over_hit, "building badge center shares its original entrance hit")
	if not badge_over_hit:
		point = site.door
	await _click_world_point(world, point)


func _click_world_point(world: Expedition, point: Vector2) -> void:
	var screen: Vector2 = world.get_global_transform_with_canvas() * point
	_check(viewport.get_visible_rect().has_point(screen), "original target click is inside the viewport")
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = screen
		event.global_position = screen
		event.pressed = down
		viewport.push_input(event, true)
		await _frame()
