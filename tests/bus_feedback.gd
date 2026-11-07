extends "res://tests/level_flow.gd"
## Ordinary equipment sortie on a fresh isolated profile, using original work and movement intents.

var observations: Dictionary = {}


func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	await _menu()
	var slot: int = -1
	for index: int in range(app.mission_select.daily_offers.size()):
		var offer: Dictionary = app.mission_select.daily_offers[index]
		if offer.type == "equipment" and offer.layout["size"] == "medium":
			slot = index
	_check(slot >= 0, "ordinary cards contain the medium equipment sample")
	if slot < 0:
		return
	var world: Expedition = await _start(slot)
	if world == null:
		return
	var action_id: String = world.supply.generated.id
	var skip_departure: bool = "--bus-skip" in OS.get_cmdline_user_args()
	if skip_departure:
		viewport.size = Vector2i(1024, 576)
	var hud: C1ExpeditionHud = world._hud.view
	var site: Expedition.SearchSite = world.search_site(&"cash")
	world.request_search(site.id)
	var worker_id: int = world.search_assignments.member_for(String(site.id))
	var worker: FieldActor = world.search_member(worker_id)
	_check(worker != null and world.living_count() == 2, "actual search intent assigns one of two live members")
	if worker == null:
		return
	world.command_move(world.layout.bus_door + Vector2(0, 8))
	world.camera.pan_by(world.layout.bus_door - Vector2(0, 125) - world.camera.position)
	world.camera.force_update_scroll()
	await _until(world, func() -> bool:
		return world.elapsed >= world.tuning.bus_ready_seconds and site.progress > 0.0 and world.boarding_status().arrived == 1)
	await _click_button(hud._bus_button)
	world.step(1.0 / 30.0)
	_check(world.phase == Expedition.Phase.ENGINE and hud._bus_status.text.begins_with("发动引擎")
		and hud._bus_waiting.text == "请前往巴士旁集合", "engine retains countdown and guides players to the bus")
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	_check(not world.boarding_status().ordered, "starting the engine leaves recall separate")
	var waiting_name: String = "等待%s · " % SearchWorkView.short_call_sign(worker.call_sign)
	_expect_waiter(world, worker_id, "searching", waiting_name + "搜集中", "before-recall")
	await _click_button(hud._bus_button)
	_check(world.boarding_status().ordered and world.has_search_job(worker_id), "real recall preserves assigned work and sets the valid bus goal")
	_expect_waiter(world, worker_id, "searching", waiting_name + "搜集中", "after-recall")
	await _shot("1-of-2-searching")
	await _until(world, func() -> bool: return site.searched)
	_expect_waiter(world, worker_id, "gathering", waiting_name + "前往巴士", "worker-returning")
	await _shot("1-of-2-returning")
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	var bus: BusJourney = world.bus_view
	var durable: Dictionary = app.progress_session._transaction.recover()
	_check(durable.error == OK and durable.receipt.phase == "RESULT_READY" and durable.acknowledged and not app._screen.visible,
		"durable result exists while the original boarding presentation hides the result screen")
	_check(bus.stage == "embarking" and bus._boarding_label.is_visible_in_tree()
		and bus._boarding_label.text == "已集合 2/2 · 正在登车", "actual final count stays readable after the expedition HUD hides")
	observations["boarding"] = {"time":world.elapsed, "text":bus._boarding_label.text, "stage":bus.stage,
		"receipt_phase":durable.receipt.phase}
	await _shot("2-of-2-boarding")
	if skip_departure:
		await _click_button(bus.skip_button)
	else:
		while bus.stage == "embarking":
			world.step(1.0 / 30.0)
		_check(bus.stage == "departing" and bus._boarding_label.is_visible_in_tree()
			and bus._boarding_label.text == "已集合 2/2 · 巴士驶离", "departure keeps the final count and changes its status")
		await _shot("2-of-2-departing")
		while bus.running():
			world.step(1.0 / 30.0)
	_check(bus.stage == "done" and not bus._boarding_label.is_visible_in_tree()
		and app._screen.visible and app.phase == app.Phase.RESULT, "natural departure or real skip exposes the same result screen")
	_check(reports.size() == 1 and reports[0].evacuated and reports[0].weapons.size() == 1, "one real return carries one earned weapon")
	if reports.size() != 1 or reports[0].weapons.size() != 1:
		return
	var weapon_id: String = reports[0].weapons[0].instance_id
	var token: Dictionary = app.progress_session.token.duplicate(true)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var saved: Dictionary = app.camp_snapshot()
	_check(not app._progress_blocked and saved.day == _before.day + 1
		and saved.weapons.filter(func(item: Dictionary) -> bool: return item.instance_id == weapon_id).size() == 1,
		"original camp confirmation banks the actual weapon exactly once")
	var committed: Dictionary = app.progress_session._transaction.recover()
	var duplicate: Dictionary = app.progress_session._transaction.commit(token)
	_check(duplicate.error == OK and duplicate.state == "ALREADY_COMMITTED" and duplicate.hash == committed.hash
		and TransactionReceipt.same(TransactionReceipt.camp(duplicate.receipt), saved),
		"repeating the original result token retains the same committed camp")
	_write("boarding.json", {"sample":action_id,
		"size":str(viewport.size), "skip":skip_departure, "observations":observations,
		"weapon":weapon_id, "day":saved.day, "report":reports[0]})


func _expect_waiter(world: Expedition, worker_id: int, activity: String, wording: String, stage: String) -> void:
	var status: Dictionary = world.boarding_status(true)
	var hud: C1ExpeditionHud = world._hud.view
	_check(status.arrived == 1 and status.required == 2 and status.waiting.size() == 1
		and status.waiting[0].id == worker_id and status.waiting[0].activity == activity
		and hud._bus_status.text == "已集合 1/2" and hud._bus_waiting.text == wording,
		"actual 1/2 waiting state follows the same identified worker at " + stage)
	observations[stage] = {"time":world.elapsed, "state":status, "count":hud._bus_status.text, "waiting":hud._bus_waiting.text}


func _click_button(button: Button) -> void:
	await _hold(2)
	var rect: Rect2 = button.get_global_rect()
	_check(button.is_visible_in_tree() and not button.disabled and viewport.get_visible_rect().encloses(rect),
		"bus input control is visible and within the viewport")
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = rect.get_center()
		event.pressed = down
		viewport.push_input(event, true)
		await _frame()
