extends "res://tests/campaign_flow.gd"
## Run with --bh-rescue-seed=m36-campaign-1235 and a fresh isolated profile.

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	for day: int in [2, 3]:
		await _tap(app.camp_scene.hotspots[&"bus"])
		var offers: Array = app.mission_select.daily_offers
		var slot: int = offers.find_custom(func(offer: Dictionary) -> bool:
			return not offer.powers.sample.is_empty())
		_check(slot >= 0, "day %d has a normal equipment action with a power sample" % day)
		if slot < 0:
			return
		var world: Expedition = await _start(slot)
		if world == null:
			return
		var gear: Expedition.SearchSite = world.search_site(&"cash")
		world.request_search(gear.id)
		for site: Expedition.SearchSite in world.sites:
			if site.kind == &"food":
				world.request_search(site.id)
				break
		await _until(world, func() -> bool: return gear.searched)
		for site: Expedition.SearchSite in world.sites:
			if app.food + world.food_loot >= 4:
				break
			if site.kind == &"food" and not site.searched:
				if world.search_assignments.member_for(String(site.id)) == 0:
					world.request_search(site.id)
				await _until(world, func() -> bool: return site.searched)
		await _extract(world)
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		_check(not app._progress_blocked and app.day == day + 1, "normal return saved")

	await _tap(app.camp_scene.facility_buttons[CampFacilities.SUPPLY])
	await _tap(app._facility_confirmation.get_ok_button())
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var before: Dictionary = app.camp_snapshot()
	var panel: LoadoutPanel = app.loadout_panel
	var power: PowerLoadoutPanel = panel.power_panel
	_check(before.cash == 47 and before.journey.build.powers.slots == [""], "47 coins and a locked second slot")
	if before.cash != 47:
		return
	var other: String = WeaponInventory.for_member(before, 2).instance_id
	_check(not panel.equip_by_id[1].disabled, "ready equipment can be assigned before a failure")
	app.progress_session.fault_hook = func(point: String) -> Error:
		return ERR_CANT_CREATE if point == "before_camp_write" else OK
	await _tap(power.purchases[PowerState.SECOND_SLOT])
	await _tap(power.confirmation.get_ok_button())
	var edit_id: String = app.progress_session._pending_edit
	_check(not edit_id.is_empty() and app._progress_blocked and app._progress_dirty, "the purchase is pending")
	_check(TransactionReceipt.same(before, app.camp_snapshot()), "the balance and slot have not changed")
	_check(power.retry_button.is_visible_in_tree(), "the purchase retry is visible")

	panel.items.select(1)
	panel._select(1)
	_check(panel._selected_id == other and panel.equip_by_id[1].disabled,
		"browsing equipment keeps assignment locked")
	_check(power.purchases[PowerState.FREEZE].disabled, "other power edits are locked")
	app.equip_weapon(1, other)
	app.repair_weapon(other)
	app.equip_build_item(0, "")
	_check(app.progress_session._pending_edit == edit_id and TransactionReceipt.same(before, app.camp_snapshot()),
		"other edit requests preserve the original purchase and camp")
	_check(power.retry_button.is_visible_in_tree() and not power.retry_button.disabled,
		"the original retry stays available after other edit requests")
	if not power.retry_button.is_visible_in_tree():
		return

	app.progress_session.fault_hook = Callable()
	await _tap(power.retry_button)
	var after: Dictionary = app.camp_snapshot()
	var committed: Dictionary = app.progress_session._transaction.recover()
	_check(committed.error == OK and committed.receipt.transaction_id == edit_id, "the original edit was committed")
	_check(after.cash == 23 and after.camp_spending == before.camp_spending + 24
		and after.journey.build.powers.slots == ["", ""], "one debit opens the second slot")
	_check(not app._progress_blocked and not app._progress_dirty and not power.retry_button.visible
		and not panel.equip_by_id[1].disabled, "successful retry restores normal controls")
	app.retry_power_edit()
	_check(TransactionReceipt.same(after, app.camp_snapshot())
		and app.progress_session._transaction.recover().hash == committed.hash, "duplicate retry changes neither camp nor receipt")

	# The route carries ready starters. Change only a view copy to exercise repair eligibility.
	var view: Dictionary = after.duplicate(true)
	view.weapons[0].condition = "damaged"
	panel._selected_id = view.weapons[0].instance_id
	panel.refresh(view, "", true)
	_check(panel.repair_button.disabled, "a repairable selection is locked during retry")
	panel.refresh(view)
	_check(not panel.repair_button.disabled, "a repairable selection becomes actionable after retry")
	panel.refresh(after)
