extends "res://tests/campaign_flow.gd"
## Ordinary title, camp, mission and extraction flow in an isolated profile.
## Run before, admitted (--flow-resume), then returned (--flow-resume --flow-rescue-post)
## with sibling output directories and the same profile. Compare and fault use fresh profiles.


func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked and app.day == 2,
		"normal opening is committed")
	await _tap(app.camp_scene.hotspots[&"bus"])
	var slot: int = _slot("supply")
	_check(slot >= 0, "opening offers normal supplies")
	if slot < 0:
		return
	var supply_world: Expedition = await _start(slot)
	if supply_world == null:
		return
	await _forage(supply_world)
	await _extract(supply_world)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app.day == 3 and app.food >= 2 and not app._progress_blocked, "normal supply return funds the rescue")
	await _tap(app.camp_scene.hotspots[&"bus"])
	slot = _slot("rescue")
	_check(slot >= 0, "day three offers normal rescue")
	if slot < 0:
		return
	var action: Dictionary = app.mission_select.daily_offers[slot]
	var candidate: int = int(action.recruit)
	_assert_card(slot, candidate)
	await _shot("anonymous-card")
	# The same frozen offer must survive browsing and re-opening the board.
	await _tap(app.mission_select.cancel_button)
	await _tap(app.camp_scene.hotspots[&"bus"])
	slot = _slot("rescue")
	if slot < 0:
		_check(false, "rescue remains available after browsing")
		return
	_check(TransactionReceipt.same(action, app.mission_select.daily_offers[slot]), "browsing keeps the original signed candidate")
	var world: Expedition = await _start(slot)
	if world == null or world.rescue_target == null:
		_check(false, "normal rescue created a target")
		return
	_assert_anonymous(world, candidate, "arrival")
	world.locate_objective("primary")
	_assert_anonymous(world, candidate, "after locating the target")
	await _shot("anonymous-field")
	if "--flow-rescue-compare" in OS.get_cmdline_user_args():
		await _return_and_confirm(world, candidate, false)
		return

	await _tap(world.rescue_target.button)
	await _until(world, func() -> bool: return world.rescue_target.progress >= 1.0, 5400)
	_assert_anonymous(world, candidate, "approach and assistance in progress")
	_check(world.rescue_target.status == "IN_PROGRESS" and world.rescue_target.progress < RescueTarget.SECONDS,
		"the visual check occurs during the actual assistance countdown")
	await _shot("anonymous-assistance")
	if "--flow-rescue-fault" in OS.get_cmdline_user_args():
		await _join_with_fault(world, candidate)
		return

	var initial_npc: FieldActor = world.rescue_target.npc
	await _tap(world.rescue_target.button)
	_check(world.rescue_target.status == "AVAILABLE" and world.rescue_target.npc == initial_npc,
		"cancelling the assistance retains the same hidden actor")
	_assert_anonymous(world, candidate, "after cancelling assistance")
	await _tap(world.rescue_target.button)
	await _until(world, func() -> bool: return world.rescue_target.progress >= 2.0, 5400)
	await _suspend(world, candidate)


func _resume() -> void:
	var post: bool = "--flow-rescue-post" in OS.get_cmdline_user_args()
	var previous: String = "admitted" if post else "before"
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		output.get_base_dir().path_join(previous).path_join("checkpoint.json")))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "new process resumes the original rescue world")
	if world == null:
		return
	world.set_physics_process(false)
	world.set_process(false)
	_check(OS.get_process_id() != int(expected.pid)
		and RecordEncoding.fingerprint(SortieSnapshot.capture(world)) == expected.fingerprint,
		"new PID preserves the exact frozen world")
	var candidate: int = int(expected.candidate)
	_check(world.supply.generated.id == expected.action and world.candidate_id() == candidate
		and world.rescue_target.status == expected.status, "resume retains the original candidate and reveal boundary")
	if post:
		_assert_revealed(world, candidate)
		await _shot("admitted-restored")
	else:
		_assert_anonymous(world, candidate, "resumed before admission")
		await _shot("anonymous-restored")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()
	if post:
		await _return_and_confirm(world, candidate, true)
		return

	var original: FieldActor = world.rescue_target.npc
	await _until(world, func() -> bool: return world.rescue_target.revealed(), 5400)
	_check(world.rescue_target.npc == original and world.search_member(candidate) == original,
		"admission promotes the same actor without a replacement")
	_assert_revealed(world, candidate)
	await _shot("admitted")
	await _suspend(world, candidate)


func _slot(type: String) -> int:
	for index: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[index].type == type:
			return index
	return -1


func _assert_card(slot: int, candidate: int) -> void:
	var view: MissionSelect = app.mission_select
	var title: String = view._titles[slot].text
	var body: String = view._descriptions[slot].text
	_check(RescueTarget.ACTION_TITLE in title and RescueTarget.ANONYMOUS_NAME in body
		and "×1" in body and "归航" in body and view._role_marks[slot].role == "rescue",
		"mission card offers one anonymous survivor, a generic marker, route and return terms")
	_no_identity(title + "\n" + body + "\n" + view.choices[slot].tooltip_text, "mission card")
	_write("card.json", {"seed":app.camp_snapshot().journey.seed,
		"candidate":candidate, "action":view.daily_offers[slot].id,
		"title":title, "description":body, "marker":view._role_marks[slot].role})


func _assert_anonymous(world: Expedition, candidate: int, stage: String) -> void:
	var target: RescueTarget = world.rescue_target
	_check(target.npc.definition_id == StringName("crew_%d" % candidate)
		and not target.revealed() and not target.npc.visual.visible and target.npc.visible
		and world.search_member(candidate) == null, stage + ": original real actor hidden from view and team")
	world._hud.view.open_persona(candidate)
	_check(not world._hud.view.persona_details.visible, stage + ": candidate details are unavailable")
	var objective: Dictionary = world._exploration_objective_rows()[0]
	_check(target.candidate_name() == RescueTarget.ANONYMOUS_NAME
		and RescueTarget.ANONYMOUS_NAME in target.button.text
		and RescueTarget.ANONYMOUS_NAME in target.label.text
		and RescueTarget.ANONYMOUS_NAME in objective.title, stage + ": every visible rescue caption is anonymous")
	_no_identity(target.button.text + target.label.text + String(objective.title) + String(objective.hint), stage)


func _no_identity(shown: String, stage: String) -> void:
	for candidate: int in RescuePoolState.CANDIDATES:
		var forbidden: String = SurvivorRoster.definition(candidate).default_display_name
		_check(forbidden not in shown, stage + ": candidate names do not leak")
	_check(WeaponInventory.MECHANIC_TITLE not in shown and FirstAidV1.TITLE not in shown, stage + ": specialist roles do not leak")


func _assert_revealed(world: Expedition, candidate: int) -> void:
	var target: RescueTarget = world.rescue_target
	var name: String = SurvivorRoster.definition(candidate).default_display_name
	_check(target.revealed() and target.status == "IN_FIELD_JOINED" and target.npc.visual.visible
		and world.search_member(candidate) == target.npc and name in target.candidate_name(),
		"confirmed admission reveals the same named actor and team portrait")
	_check(world.field_joins.size() == 1 and int(world.field_joins[0].member_id) == candidate
		and SurvivorRoster.member(app.camp_snapshot().crew, candidate).is_empty(),
		"field admission is acknowledged once and is not yet a camp recruit")
	world._hud.view.open_persona(candidate)
	var detail: PersonaDetails = world._hud.view.persona_details
	_check(detail.visible and name in detail.name_label.text and not detail.recipe_label.text.is_empty(),
		"admitted actor exposes the actual name, portrait and traits")
	if candidate == WeaponInventory.MECHANIC_ID:
		_check(detail.primary_label.text == WeaponInventory.MECHANIC_TITLE
			and "生还归航" in detail.trait_label.text, "mechanic profession and future benefit are revealed in the field")
	detail.close()


func _join_with_fault(world: Expedition, candidate: int) -> void:
	var target: RescueTarget = world.rescue_target
	var original: FieldActor = target.npc
	app.progress_session.fault_hook = func(point: String) -> Error:
		return ERR_CANT_CREATE if point == "before_record_write" else OK
	await _until(world, func() -> bool: return not world.field_join_error.is_empty(), 5400)
	var pending_at: int = target._joined_at_ms
	_check(world.is_paused and target.status == "IN_PROGRESS" and world.field_joins.is_empty()
		and pending_at > 0 and "重试" in target.button.text, "injected join write failure keeps one pending original admission")
	_assert_anonymous(world, candidate, "while the join write is pending")
	await _shot("anonymous-failed-write")
	app.progress_session.fault_hook = Callable()
	await _tap(target.button)
	_check(world.rescue_target.npc == original and world.field_joins.size() == 1
		and int(world.field_joins[0].at_ms) == pending_at, "retry accepts the original actor and same confirmation time once")
	_assert_revealed(world, candidate)
	if world.is_paused:
		world.toggle_pause()
	await _return_and_confirm(world, candidate, true)


func _suspend(world: Expedition, candidate: int) -> void:
	app.open_pause_menu()
	await _hold(2)
	var snapshot: Dictionary = SortieSnapshot.capture(world)
	var receipt: Dictionary = app.progress_session._transaction.recover().receipt
	_check(not snapshot.is_empty() and SortieSnapshot.problem(snapshot, receipt).is_empty(),
		"live rescue state validates for safe suspend")
	_write("checkpoint.json", {"pid":OS.get_process_id(), "fingerprint":RecordEncoding.fingerprint(snapshot),
		"action":world.supply.generated.id, "candidate":candidate, "status":world.rescue_target.status,
		"progress":world.rescue_target.progress})
	app.suspend_sortie()
	await _hold(3)
	_check(app.expedition == null and app._requires_continue, "safe suspend publishes and returns to title")


func _forage(world: Expedition) -> void:
	for site: Expedition.SearchSite in world.sites:
		if app.food + world.food_loot >= 4:
			break
		if site.kind != &"food" or site.searched:
			continue
		if world.search_assignments.member_for(String(site.id)) == 0:
			world.request_search(site.id)
		await _until(world, func() -> bool: return site.searched, 4800)


func _return_and_confirm(world: Expedition, candidate: int, accepted: bool) -> void:
	await _extract(world)
	_check(SurvivorRoster.member(app.camp_snapshot().crew, candidate).is_empty(),
		"result preview does not yet register a new camp member")
	var result: Label = app.get_node("Interface/Screen/Result/Scroll/Body")
	if accepted:
		_check(SurvivorRoster.definition(candidate).default_display_name in result.text,
			"admitted member is identified in the prepared result")
	else:
		_no_identity(result.text, "early return result")
	await _shot("rescue-result")
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var camp: Dictionary = app.camp_snapshot()
	var recruit: Dictionary = SurvivorRoster.member(camp.crew, candidate)
	_check(not app._progress_blocked and (not recruit.is_empty() and recruit.health > 0.0 if accepted else recruit.is_empty()),
		"only the admitted living return is registered after confirmation")
	if accepted and candidate == WeaponInventory.MECHANIC_ID:
		_check(WeaponInventory.mechanic_available(camp), "confirmed surviving mechanic now qualifies for repairs")
	app.return_to_title()
	_check(TransactionReceipt.same(camp, app.camp_snapshot()), "duplicate return keeps the confirmed camp")
