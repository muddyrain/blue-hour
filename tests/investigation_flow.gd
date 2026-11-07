extends "res://tests/campaign_flow.gd"
## Ordinary Windows-ready fixture. The original interface and simulation own every progression write.

const CLUES: Array[String] = ["dispatch_log", "checkpoint_pass"]
const CLUE_NAMES: Array[String] = ["线路调度记录", "封锁通行记录"]


func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	_check(CampaignRules.is_investigation(camp.journey.campaign) and _clue_ids(camp).is_empty(),
		"ordinary fresh entry starts an investigation with zero committed clues")
	if not CampaignRules.is_investigation(camp.journey.campaign):
		return
	await _camp_progress(0)
	await _menu(0)
	if "--investigation-no-clue" in OS.get_cmdline_user_args():
		await _leave_without_clue()
		return
	var original: Dictionary = app.mission_select.daily_offers[1].duplicate(true)
	await _tap(app.mission_select.cancel_button)
	await _menu(0)
	_check(TransactionReceipt.same(original, app.mission_select.daily_offers[1]),
		"same-day browsing reopens the exact signed investigation")

	# Earn enough food for two investigations and both finale outcomes by taking ordinary supply cards.
	for attempt: int in range(3):
		var supply: Expedition = await _start(0)
		if supply == null:
			return
		for id: String in supply.supply.generated.objective.site_ids:
			supply.request_search(StringName(id))
		var goals: Array = supply.supply.generated.objective.site_ids
		await _until(supply, func() -> bool:
			return goals.all(func(id: String) -> bool: return supply.search_site(StringName(id)).searched))
		await _return_to_bus(supply)
		_check(not reports.is_empty() and reports.back().food > 0, "real regular supply gathers and carries food")
		await _confirm(0)
		_check(_clue_ids(app.camp_snapshot()).is_empty(), "ordinary supply and its confirmed return do not earn a clue")
		await _menu(0)
		if app.food >= 8:
			break
	_check(app.food >= 8, "ordinary supply trips earn reserves for all four planned departures")
	_check(app.mission_select.daily_offers[1].investigation.clue_id == CLUES[0],
		"ordinary supply leaves the first investigation available on another day")

	var signed: Dictionary = app.mission_select.daily_offers[1]
	_validate_bindings(app.camp_snapshot(), signed)
	var field: Expedition = await _start(1)
	if field == null:
		return
	await _search_clue(field, 0)
	_check(_clue_ids(app.camp_snapshot()).is_empty(), "carried clue remains field-only before extraction")
	app.open_pause_menu()
	await _hold(2)
	var captured: Dictionary = SortieSnapshot.capture(field)
	var receipt: Dictionary = app.progress_session._transaction.recover().receipt
	var issue: String = SortieSnapshot.problem(captured, receipt)
	_check(issue.is_empty(), "original suspension validates actual completed investigation site: " + issue)
	_write("checkpoint.json", {
		"pid": OS.get_process_id(), "action_id": signed.id, "investigation": signed.investigation,
		"world_hash": RecordEncoding.fingerprint(captured),
		"camp_hash": RecordEncoding.fingerprint(app.camp_snapshot()),
	})
	app.suspend_sortie()
	await _hold(3)
	var saved: Dictionary = app.progress_session.inspect()
	_check(app.expedition == null and app._requires_continue and saved.error == OK
		and saved.get("receipt", {}).get("phase") == "SUSPEND_READY",
		"real carrying state reaches durable SUSPEND_READY through the normal entry")


func _leave_without_clue() -> void:
	var world: Expedition = await _start(1)
	if world == null:
		return
	await _return_to_bus(world)
	_check(not reports.back().site_facts.cash.searched and reports.back().evacuated,
		"original evacuation can leave the signed investigation site unsearched")
	await _confirm(0)
	await _camp_progress(0)
	await _menu(0)


func _resume() -> void:
	var checkpoint: String = output.get_base_dir().path_join("first/checkpoint.json")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(checkpoint))
	_check(int(expected.pid) != OS.get_process_id() and app._requires_continue,
		"normal title offers the acknowledged investigation to a fresh process")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var field: Expedition = app.expedition
	_check(field != null, "original Continue reconstructs the investigation world")
	if field == null:
		return
	field.set_physics_process(false)
	field.set_process(false)
	field.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	_check(RecordEncoding.fingerprint(SortieSnapshot.capture(field)) == expected.world_hash
		and RecordEncoding.fingerprint(app.camp_snapshot()) == expected.camp_hash
		and field.supply.generated.id == expected.action_id
		and TransactionReceipt.same(field.supply.generated.investigation, expected.investigation),
		"same frozen action, site facts and uncredited camp restore exactly")
	if app.pause_menu.visible:
		await _tap(app.pause_menu.buttons[0])
	if field.is_paused:
		field.toggle_pause()
	_check(field.search_site(&"cash").searched and _carrying_ui(field, 0),
		"completed target and carried-clue HUD reconstruct after Continue")
	if output.get_file() == "wipe":
		await _wipe(field)
		return

	await _return_to_bus(field)
	await _confirm(1, true)
	await _camp_progress(1)
	await _menu(1)
	var second: Expedition = await _start(1)
	if second == null:
		return
	await _search_clue(second, 1)
	_check(_clue_ids(app.camp_snapshot()) == [CLUES[0]], "second carried clue cannot advance the stored campaign yet")
	await _return_to_bus(second)
	await _confirm(2)
	await _camp_progress(2)
	await _menu(2)
	await _finales()


func _menu(count: int) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array = app.mission_select.daily_offers
	var heading: String = app.mission_select._heading.text
	_check(app.mission_select.visible and heading.contains("调查线索 %d/2" % count),
		"ordinary action interface shows the confirmed investigation count")
	if count == CLUES.size():
		_check(offers.size() == 3 and offers[0].version == 8 and offers[0].campaign.is_finale
			and offers[1].type == "supply"
			and offers.all(func(offer: Dictionary) -> bool: return not offer.has("investigation"))
			and app.mission_select._titles[0].text.contains("突破封锁"),
			"two distinct confirmed clues expose the original finale alongside regular supplies")
		var camp: Dictionary = app.camp_snapshot()
		_check(offers.size() == 3 and not offers[1].campaign.is_finale
			and offers[1].id != offers[0].id and offers[1].id != offers[2].id
			and offers.all(func(offer: Dictionary) -> bool: return DailyActions.matches(camp, offer)),
			"unlocked finale and ordinary actions retain separate authenticated identities")
		return
	_check(offers.size() == 3 and offers[0].type == "supply"
		and offers[1].get("investigation", {}).get("clue_id") == CLUES[count]
		and offers.filter(func(offer: Dictionary) -> bool: return offer.has("investigation")).size() == 1,
		"three ordinary cards include supply and exactly one pending investigation")
	_check(app.mission_select._titles[1].text.contains("调查")
		and app.mission_select._descriptions[1].text.contains(CLUE_NAMES[count]),
		"actual investigation card identifies the precise clue")


func _camp_progress(count: int) -> void:
	var progress: Label = app.camp_scene.eligibility_text
	_check(progress.is_visible_in_tree() and progress.text.contains("调查线索 %d/2" % count),
		"ordinary camp presents the confirmed clue count")
	await _shot("campaign-%d" % count)


func _validate_bindings(camp: Dictionary, signed: Dictionary) -> void:
	_check(DailyActions.matches(camp, signed) and signed.investigation.site_id == "cash"
		and signed.investigation.site_id in signed.objective.site_ids, "genuine clue authenticates on the actual main site")
	var invalid: Dictionary = signed.duplicate(true)
	invalid.investigation.site_id = "cash_2"
	_check(not DailyActions.matches(camp, invalid) and not DailyActions.problem(invalid).is_empty(),
		"warm verification rejects reassigned clue site")
	invalid = signed.duplicate(true)
	invalid.investigation.clue_id = CLUES[1]
	_check(not DailyActions.matches(camp, invalid), "genuine site cannot yield a later clue early")
	invalid = signed.duplicate(true)
	invalid.erase("investigation")
	_check(not DailyActions.matches(camp, invalid), "removing signed clue metadata does not produce a legal action")


func _search_clue(world: Expedition, index: int) -> void:
	var site: Expedition.SearchSite = world.search_site(&"cash")
	_check(site != null and site.prop.primary_target and not site.searched and not _carrying_ui(world, index)
		and world._hud.view._exploration_objectives.labels[0].text.contains(CLUE_NAMES[index]),
		"unsearched actual primary building does not present a carried clue")
	if site == null:
		return
	world.locate_objective("primary")
	await _hold(2)
	_check(world._locate_ring.global_position.is_equal_approx(site.door),
		"real objective locator points to the signed investigation entrance")
	var point: Vector2 = world.get_global_transform_with_canvas() * site.door
	_check(viewport.get_visible_rect().has_point(point), "real investigation entrance is on screen")
	for down: bool in [true, false]:
		var mouse: InputEventMouseButton = InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		mouse.position = point
		mouse.global_position = point
		mouse.pressed = down
		viewport.push_input(mouse, true)
		await _frame()
	_check(world.search_assignments.member_for(String(site.id)) > 0, "ordinary map click assigns the actual clue site")
	await _until(world, func() -> bool: return site.searched)
	_check(_carrying_ui(world, index), "actual completed work presents the exact carried clue")
	if index == 0:
		await _shot("carried-clue")


func _carrying_ui(world: Expedition, index: int) -> bool:
	var label: Label = world._hud.view._exploration_objectives.labels[0]
	return label.is_visible_in_tree() and label.text.contains("已携带") and label.text.contains(CLUE_NAMES[index])


func _return_to_bus(world: Expedition) -> void:
	world.command_move(world.layout.bus_door)
	await _extract(world)


func _confirm(expected_count: int, exercise_retry: bool = false) -> void:
	var before: Dictionary = app.camp_snapshot()
	var pending: Dictionary = app._pending_settlement.duplicate(true)
	var button: Button = app.get_node("Interface/Screen/Result/Continue")
	var ready: Dictionary = app.progress_session.inspect()
	_check(not pending.is_empty() and _clue_ids(pending) == CLUES.slice(0, expected_count)
		and ready.get("receipt", {}).get("phase") == "RESULT_READY",
		"one frozen durable preview proposes exactly the valid returned clues")
	if expected_count > _clue_ids(before).size() and not pending.is_empty():
		var clue: Dictionary = pending.journey.campaign.clues.back()
		var receipt: Dictionary = ready.get("receipt", {})
		var generated: Dictionary = receipt.get("rules", {}).get("mission", {}).get("generated", {})
		_check(clue.transaction_id == receipt.get("transaction_id")
			and clue.action_id == generated.get("id") and clue.site_id == "cash",
			"credit preserves the real return transaction, frozen action and primary site identity")
	var token: Dictionary = app.progress_session.token.duplicate(true)
	if exercise_retry:
		_check(_clue_ids(before).size() == expected_count - 1, "ready receipt cannot unlock the next clue before commit")
		app.progress_session.fault_hook = func(point: String) -> Error:
			return ERR_CANT_CREATE if point == "before_commit_receipt" else OK
		await _tap(button)
		_check(app._progress_blocked and TransactionReceipt.same(before, app.camp_snapshot())
			and TransactionReceipt.same(pending, app._pending_settlement),
			"failed confirmation publishes no new clues and retains the same frozen result")
		app.progress_session.fault_hook = Callable()
	await _tap(button)
	var saved: Dictionary = app.camp_snapshot()
	_check(not app._progress_blocked and _clue_ids(saved) == CLUES.slice(0, expected_count)
		and TransactionReceipt.same(saved, pending), "original confirmation publishes exactly the frozen progress")
	if exercise_retry:
		var committed: Dictionary = app.progress_session._transaction.recover()
		var repeated: Dictionary = app.progress_session._transaction.commit(token)
		_check(repeated.error == OK and repeated.state == "ALREADY_COMMITTED"
			and repeated.hash == committed.hash and TransactionReceipt.same(saved, app.camp_snapshot()),
			"repeat confirmation preserves the committed receipt and gives no duplicate clue")


func _wipe(world: Expedition) -> void:
	# Controlled negative: disable survivor fire; only original enemy damage can kill.
	for actor: FieldActor in world.survivors:
		actor.cooldown = 1000000.0
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED, 18000)
	var camp: Dictionary = app.camp_snapshot()
	_check(world.living_count() == 0 and _clue_ids(camp).is_empty()
		and camp.journey.campaign.outcome == "DEFEAT" and app.progress_session.inspect().state == "ENDED",
		"enemy full wipe loses the real carried clue and ends the journey through original failure commit")
	_write("wipe.json", {"reports": reports, "camp": camp})


func _finales() -> void:
	var early: Expedition = await _start(0)
	if early == null:
		return
	_check(early.encounter != null and is_instance_valid(early.encounter.actor), "original finale spawns the existing boss")
	var first_boss: String = early.encounter.definition.boss_id
	await _return_to_bus(early)
	await _confirm(2)
	_check(app.camp_snapshot().journey.campaign.outcome == "ACTIVE"
		and reports.back().encounter.defeat.is_empty(), "early finale evacuation leaves both clues and permits a retry")
	await _menu(2)
	var world: Expedition = await _start(0)
	if world == null:
		return
	_check(world.encounter.definition.boss_id != first_boss
		and world.encounter.health() == BossDefinition.POLICY.health, "retry starts a fresh original boss and battlefield")
	world.command_move(world.encounter.actor.position + Vector2(90, 50))
	await _fight(world, true)
	_check(not world.encounter.defeat.is_empty() and world.living_count() > 0, "real combat defeats the boss with survivors")
	await _shot("boss-defeated")
	await _return_to_bus(world)
	_check(app._pending_settlement.get("journey", {}).get("campaign", {}).get("outcome") == "VICTORY"
		and app.camp_snapshot().journey.campaign.outcome == "ACTIVE", "successful boss evacuation is a victory preview before saving")
	await _confirm(2)
	var camp: Dictionary = app.camp_snapshot()
	_check(camp.journey.campaign.outcome == "VICTORY" and app.progress_session.inspect().state == "ENDED",
		"victory is durable only after the original settlement button")
	await _shot("confirmed-victory")
	_write("journey-results.json", {"reports": reports, "camp": camp})


func _clue_ids(camp: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for clue: Dictionary in camp.get("journey", {}).get("campaign", {}).get("clues", []):
		ids.append(clue.id)
	return ids
