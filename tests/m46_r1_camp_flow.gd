extends "res://tests/m46_armory_view.gd"
## Real camp edits and departure through an isolated rendered viewport.

const SHARED_CALL_SIGN: String = "同名队员"


func _initialize() -> void:
	exercise_departure_review = true
	super()


func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	await _camp_scenario()


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var saved: Dictionary = app.camp_snapshot()
	var resumed: bool = app.camp_scene.is_visible_in_tree() and int(saved.settled_sorties) > 0 \
		and bool(saved.last_day.get("evacuated", false)) and not app._progress_blocked
	_check(resumed, "Continue restores the isolated camp after a real confirmed return")
	if resumed:
		await _camp_scenario()


func _camp_scenario() -> void:
	var camp: CampSceneView = app.camp_scene
	var menu: MissionSelect = app.mission_select
	await _click_button(camp.hotspots[&"crew"])
	for id: int in [1, 2]:
		await _click_button(app.roster_panel.buttons_by_id[id])
		app.roster_panel.name_edit.text = SHARED_CALL_SIGN
		await _click_button(app.roster_panel.save_button)
	await _click_button(app.roster_panel.back_button)
	var before: Dictionary = app.camp_snapshot()
	var digest: String = FileAccess.get_sha256(app.progress_path)
	var first: Dictionary = WeaponInventory.for_member(before, 1)
	var second: Dictionary = WeaponInventory.for_member(before, 2)
	_check(SurvivorRoster.member(before.crew, 1).call_sign == SHARED_CALL_SIGN
		and SurvivorRoster.member(before.crew, 2).call_sign == SHARED_CALL_SIGN,
		"ordinary rename confirmations save identical call signs for two real IDs")
	_check(not first.is_empty() and not second.is_empty() and WeaponInventory.short_id(second) == "starter:2",
		"initial inventory exposes the exact starter instance IDs")

	await _click_button(camp.hotspots[&"bus"])
	var first_worker: Thread = app.get("_mission_worker")
	var first_key: Variant = app.get("_mission_request_key")
	_check(menu.visible and menu.loading and first_worker != null, "cold bus actually enters pending review")
	if first_worker == null or not menu.loading:
		return
	await _click_button(menu.cancel_button)
	_check(app.get("_mission_worker") == first_worker and camp.is_visible_in_tree() and not menu.visible,
		"cancel returns to camp while original request is still pending")
	await _click_button(camp.hotspots[&"bus"])
	_check(menu.visible and menu.loading and app.get("_mission_worker") == first_worker,
		"reopening unchanged camp reuses the same in-flight request")
	await _click_button(menu.cancel_button)

	await _click_button(camp.hotspots[&"crew"])
	var crew_open: bool = app.roster_panel.is_visible_in_tree()
	_check(crew_open and app.get("_mission_worker") == first_worker,
		"crew opens immediately while first request is pending")
	if crew_open:
		await _click_button(app.roster_panel.back_button)
	await _click_button(camp.hotspots[&"supplies"])
	var supplies_open: bool = is_instance_valid(app.supply_panel) and app.supply_panel.is_visible_in_tree()
	_check(supplies_open and app.get("_mission_worker") == first_worker,
		"supplies opens immediately while first request is pending")
	if supplies_open:
		await _click_button(app.supply_panel.back_button)
	await _click_button(camp.hotspots[&"weapons"])
	var armory_open: bool = is_instance_valid(app.loadout_panel) and app.loadout_panel.is_visible_in_tree()
	_check(armory_open and app.get("_mission_worker") == first_worker,
		"armory opens immediately while first request is pending")
	if not armory_open:
		# Baseline failure can still prove the identity and search regressions.
		if not await _wait_for_worker():
			return
		await _click_button(camp.hotspots[&"weapons"])
	if not is_instance_valid(app.loadout_panel) or not app.loadout_panel.is_visible_in_tree():
		return
	armory = app.loadout_panel.armory
	_check(TransactionReceipt.same(before, app.camp_snapshot()) and FileAccess.get_sha256(app.progress_path) == digest,
		"waiting, returning and opening camp pages leave the saved camp unchanged")
	await _type_text("#starter:2")
	var prefixed: String = _single_instance()
	await _type_text("starter:2")
	var bare: String = _single_instance()
	_check(prefixed == second.instance_id and bare == second.instance_id,
		"prefixed and bare starter short ID select the same full instance")
	if bare != second.instance_id:
		return
	var first_option: int = armory.target.get_item_index(1)
	var second_option: int = armory.target.get_item_index(2)
	var label_one: String = "01 · " + SHARED_CALL_SIGN
	var label_two: String = "02 · " + SHARED_CALL_SIGN
	_check(first_option >= 0 and second_option >= 0
		and armory.target.get_item_text(first_option) == label_one
		and armory.target.get_item_text(second_option) == label_two,
		"recipient choices distinguish identical call signs using stable IDs")
	if first_option < 0 or second_option < 0:
		return
	_check(label_two in armory.items.get_item_text(0) and label_two in armory._meta.text,
		"list row and selected weapon details display the same numbered owner")
	_select_option(armory.target, second_option)
	_check(armory.target.get_selected_id() == 2 and armory.confirm_equip.disabled,
		"selecting the actual owner with the same call sign cannot swap")
	_select_option(armory.target, first_option)
	var preview: String = armory._preview.text
	_check(armory.target.get_selected_id() == 1 and not armory.confirm_equip.disabled
		and _has_swap_line(preview, label_one, first, second)
		and _has_swap_line(preview, label_two, second, first),
		"both sides of the exchange preview pair numbered recipients with the correct instances")
	await _shot("numbered-swap-preview")

	var original_pending_at_confirmation: bool = app.get("_mission_worker") == first_worker
	_check(original_pending_at_confirmation, "first verification is still outstanding when confirming equip")
	await _click_button(armory.confirm_equip)
	var after: Dictionary = app.camp_snapshot()
	var swapped_digest: String = FileAccess.get_sha256(app.progress_path)
	_check(WeaponInventory.for_member(after, 1).instance_id == second.instance_id
		and WeaponInventory.for_member(after, 2).instance_id == first.instance_id
		and swapped_digest != digest and not app._progress_blocked,
		"confirmed swap applies and persists the correct same-name members' instances")
	await _click_button(armory.back_button)
	await _click_button(camp.hotspots[&"bus"])
	var worker_on_reopen: Thread = app.get("_mission_worker")
	var current_key: Variant = app.get("_mission_request_key")
	_check(menu.visible and menu.loading and menu.daily_offers.is_empty() and menu.depart_button.disabled,
		"immediate post-edit reopen waits for the current camp's cards")
	_check(first_key is String and current_key is String and first_key == RecordEncoding.fingerprint(before)
		and first_key != current_key
		and current_key == RecordEncoding.fingerprint(after),
		"post-edit review is keyed to the current confirmed camp")
	_check(_review_matches(menu, label_one, second) and _review_matches(menu, label_two, first),
		"waiting departure review already shows the newly saved numbered loadout")
	for attempt: int in range(5):
		app.open_mission_select()
	_check(app.get("_mission_worker") == worker_on_reopen and app.get("_mission_request_key") == current_key,
		"repeat requests through the real open handler do not launch another active job")
	var active_workers: Array[Thread] = []
	var deadline: int = Time.get_ticks_msec() + 90000
	var stale_cards: bool = false
	while app.get("_mission_worker") != null and Time.get_ticks_msec() < deadline:
		var worker: Thread = app.get("_mission_worker")
		if worker not in active_workers:
			active_workers.append(worker)
		if worker == first_worker and not menu.daily_offers.is_empty():
			stale_cards = true
		await _frame()
	_check(not stale_cards and active_workers.filter(func(worker: Thread) -> bool: return worker != first_worker).size() == 1,
		"superseded verification exposes no cards and there is only one replacement job")
	if app.get("_mission_worker") != null:
		_check(false, "verification completes before the bounded deadline")
		return
	_check(menu.visible and not menu.loading and not menu.daily_offers.is_empty()
		and menu.choices[0].is_visible_in_tree() and not menu.choices[0].disabled,
		"only the current verification publishes usable departure cards")
	if menu.daily_offers.is_empty():
		return
	_check(_review_matches(menu, label_one, second) and _review_matches(menu, label_two, first)
		and FileAccess.get_sha256(app.progress_path) == swapped_digest,
		"late work leaves the new review and saved loadout intact")
	var signed: Dictionary = menu.daily_offers[0].duplicate(true)
	await _click_button(menu.choices[0])
	await _shot("numbered-departure")
	var world: Expedition = await _depart()
	if world == null:
		return
	_check(WeaponInventory.for_member(after, 1).instance_id == world.search_member(1).weapon_instance_id
		and WeaponInventory.for_member(after, 2).instance_id == world.search_member(2).weapon_instance_id
		and TransactionReceipt.same(signed, world.supply.generated),
		"real expedition uses the selected signed action and the two swapped identities")
	_write("r1-flow.json", {"old_request":first_key, "new_request":current_key, "before":digest, "after":swapped_digest,
		"workers_observed_after_reopen":active_workers.size(), "stale_cards_observed":stale_cards,
		"search_ids":[prefixed, bare], "instance_for_01":world.search_member(1).weapon_instance_id,
		"instance_for_02":world.search_member(2).weapon_instance_id, "action":signed.id})


func _single_instance() -> String:
	return String(armory.items.get_item_metadata(0)) if armory.items.item_count == 1 else ""


func _has_swap_line(preview: String, label: String, former: Dictionary, replacement: Dictionary) -> bool:
	var from_id: String = WeaponInventory.short_id(former)
	var to_id: String = WeaponInventory.short_id(replacement)
	for line: String in preview.split("\n"):
		var arrow: int = line.find("→")
		if label in line and line.find(from_id) >= 0 and line.find(from_id) < arrow and line.find(to_id) > arrow:
			return true
	return false


func _review_matches(menu: MissionSelect, label: String, item: Dictionary) -> bool:
	var children: Array[Node] = menu._review_details.get_children()
	for i: int in range(children.size() - 1):
		var identity: Label = children[i] as Label
		var equipped: Label = children[i + 1] as Label
		if identity != null and equipped != null and label in identity.text \
				and WeaponInventory.short_id(item) in equipped.text:
			return true
	return false


func _wait_for_worker() -> bool:
	var deadline: int = Time.get_ticks_msec() + 90000
	while app.get("_mission_worker") != null and Time.get_ticks_msec() < deadline:
		await _frame()
	var finished: bool = app.get("_mission_worker") == null
	_check(finished, "verification completes before the bounded deadline")
	return finished
