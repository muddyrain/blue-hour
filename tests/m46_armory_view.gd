extends "res://tests/campaign_flow.gd"
## Native background UI evidence and real isolated camp edits. Capacity data stays in the view.

var armory: CampArmoryView


func _journey() -> void:
	await _tap(app._home_button)
	if app._opening_picker.visible:
		await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree(), "normal fresh journey opens camp")
	await _shot("01-camp")
	await _click_button(app.camp_scene.hotspots[&"crew"])
	_check(app.roster_panel.is_visible_in_tree(), "camp crew control opens real roster")
	await _shot("05-crew")
	await _click_button(app.roster_panel.back_button)
	await _click_button(app.camp_scene.hotspots[&"training"])
	_check(app.training_panel.is_visible_in_tree(), "camp training control opens actual training")
	await _shot("05b-training")
	await _click_button(app.training_panel.back_button)
	await _click_button(app.camp_scene.hotspots[&"supplies"])
	_check(app.supply_panel.is_visible_in_tree(), "camp supplies control opens real ration and facility view")
	await _shot("06-supplies")
	await _click_button(app.supply_panel.back_button)
	await _click_button(app.camp_scene.hotspots[&"weapons"])
	armory = app.loadout_panel.armory
	if not is_instance_valid(armory):
		_check(false, "playable camp has M46 armory")
		return
	var original: Dictionary = app.camp_snapshot()
	var digest: String = FileAccess.get_sha256(app.progress_path)
	await _capacity(original)
	app.loadout_panel.refresh(original)
	_check(TransactionReceipt.same(app.camp_snapshot(), original) and FileAccess.get_sha256(app.progress_path) == digest,
		"capacity projection and all navigation leave real camp and save bytes intact")
	var first: Dictionary = WeaponInventory.for_member(original, 1)
	var second: Dictionary = WeaponInventory.for_member(original, 2)
	_select_option(armory.target, armory.target.get_item_index(1))
	await _type_text(WeaponInventory.short_id(second))
	_check(armory.items.item_count == 1 and armory.items.get_item_metadata(0) == second.instance_id,
		"visible search row points to teammate's real full instance ID")
	_check("确认交换" == armory.confirm_equip.text and not armory.confirm_equip.disabled, "two-owner swap awaits explicit confirmation")
	_check(WeaponInventory.short_id(first) in armory._preview.text and WeaponInventory.short_id(second) in armory._preview.text,
		"two-owner preview lists both exact instance changes")
	await _shot("03-swap-preview")
	await _click_button(armory.cancel_preview)
	app.equip_weapon(1, second.instance_id)
	_check(TransactionReceipt.same(app.camp_snapshot(), original) and FileAccess.get_sha256(app.progress_path) == digest,
		"cancel and stale direct request cannot change camp or append an edit")
	await _click_button(armory.confirm_equip)
	await _click_button(armory.confirm_equip)
	var swapped: Dictionary = app.camp_snapshot()
	_check(WeaponInventory.for_member(swapped, 1).instance_id == second.instance_id \
		and WeaponInventory.for_member(swapped, 2).instance_id == first.instance_id, "confirmed swap updates both actual owners")
	var swapped_digest: String = FileAccess.get_sha256(app.progress_path)
	app.equip_weapon(1, second.instance_id)
	_check(FileAccess.get_sha256(app.progress_path) == swapped_digest, "duplicate confirm leaves persisted ownership unchanged")
	await _click_button(armory.back_button)
	if not await _open_bus():
		return
	var slot: int = _weapon_offer()
	_check(slot >= 0, "ordinary action has a real weapon recovery site")
	if slot < 0:
		return
	await _click_button(app.mission_select.choices[slot])
	_check(not app.mission_select.depart_button.disabled and app.expedition == null, "card selection exposes final departure review only")
	var review: String = ""
	for node: Node in app.mission_select._review_details.get_children():
		if node is Label:
			review += (node as Label).text + "\n"
	_check(WeaponInventory.short_id(first) in review and WeaponInventory.short_id(second) in review,
		"departure lists the two real swapped instances")
	await _shot("07-departure")
	var world: Expedition = await _depart()
	if world == null:
		return
	_check(world.search_member(1).weapon_instance_id == second.instance_id and world.search_member(2).weapon_instance_id == first.instance_id,
		"actual field actors use the same swapped instances")
	var reward: Expedition.SearchSite
	for site: Expedition.SearchSite in world.sites:
		if site.weapon:
			reward = site
			break
	_check(reward != null, "normal selected field contains the real weapon site")
	if reward == null:
		return
	world.request_search(reward.id)
	await _until(world, func() -> bool: return reward.searched)
	for site: Expedition.SearchSite in world.sites:
		if site != reward and site.kind == &"food" and site.reward > 0:
			world.request_search(site.id)
			await _until(world, func() -> bool: return site.searched)
			break
	await _extract(world)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	await _repair_and_equip()


func _capacity(original: Dictionary) -> void:
	var view: Dictionary = original.duplicate(true)
	var fixtures: Array[String] = ["carbine", "long_rifle", "fire_axe_v1"]
	for index: int in range(22):
		view.weapons.append(WeaponModifiers.baseline({"instance_id":"view-only:%03d" % index,
			"weapon_id":fixtures[index % fixtures.size()], "condition":"damaged" if index % 3 == 0 else "ready",
			"origin":"view-only", "acquired_sortie":""}))
	app.loadout_panel.refresh(view, "容量测试视图 · 含隔离样本，操作使用真实存档另验。")
	await _hold(4)
	_check(armory.items.item_count >= 24, "24 or more separate real Godot ItemList rows")
	_check(viewport.get_visible_rect().encloses(armory.items.get_global_rect()) \
		and viewport.get_visible_rect().encloses(armory.back_button.get_global_rect()), "list and bottom navigation fit 1280x720")
	await _shot("02-inventory-24")
	var detail_y: float = armory._title.global_position.y
	var wheel_at: Vector2 = armory.items.get_global_rect().get_center()
	for index: int in range(48):
		await _mouse(wheel_at, MOUSE_BUTTON_WHEEL_DOWN, true)
		await _mouse(wheel_at, MOUSE_BUTTON_WHEEL_DOWN, false)
	var scrollbar: VScrollBar = armory.items.get_v_scroll_bar()
	_check(scrollbar.value > 0.0 and is_equal_approx(scrollbar.value, scrollbar.max_value - scrollbar.page), "mouse wheel reaches bottom of independent inventory list")
	_check(is_equal_approx(detail_y, armory._title.global_position.y), "detail stays in place while inventory scrolls")
	await _shot("02b-inventory-bottom")
	await _click(armory.search.get_global_rect().get_center())
	_check(viewport.gui_get_focus_owner() == armory.search, "pointer gives input focus to the search field")
	await _key(KEY_TAB)
	_check(viewport.gui_get_focus_owner() != armory.search and is_instance_valid(viewport.gui_get_focus_owner()), "Tab changes GUI focus inside the armory")
	_select_option(armory.status_filter, 2)
	_check(armory.items.item_count == original.loadout.size(), "equipped status uses actual owners")
	_select_option(armory.status_filter, 3)
	_select_option(armory.type_filter, 1)
	_check(armory.items.item_count > 0, "damaged and gun filters compose")
	for index: int in range(armory.items.item_count):
		var item: Dictionary = WeaponInventory.find(view, armory.items.get_item_metadata(index))
		_check(item.condition == "damaged" and not CombatEquipment.melee(item.weapon_id), "visible row matches both filters")
	await _click_button(armory._clear)
	await _type_text("长管步枪")
	_check(armory.items.item_count > 1, "Unicode name input finds the live model name")
	await _click_button(armory._clear)
	await _type_text("不存在的实例")
	_check(armory.items.item_count == 0 and not armory.confirm_equip.visible, "no-results hides stale equip controls")
	await _click_button(armory._clear)
	_select_option(armory.sort_order, 1)
	var previous: String = ""
	for index: int in range(armory.items.item_count):
		var current: String = armory.items.get_item_metadata(index)
		_check(previous < current, "instance sorting uses strict full ID order")
		previous = current
	viewport.size = Vector2i(1536, 864)
	await _hold(4)
	_check(viewport.get_visible_rect().encloses(armory.items.get_global_rect()) \
		and viewport.get_visible_rect().encloses(armory.back_button.get_global_rect()), "inventory and navigation fit wider viewport")
	await _shot("02c-inventory-wide")
	viewport.size = Vector2i(1280, 720)
	_select_option(armory.sort_order, 0)
	await _hold(3)


func _repair_and_equip() -> void:
	var before: Dictionary = app.camp_snapshot()
	var damaged: Dictionary = {}
	for item: Dictionary in before.weapons:
		if item.condition == "damaged":
			damaged = item
			break
	_check(not damaged.is_empty() and app.camp_scene.is_visible_in_tree(), "actual successful extraction banks a damaged instance")
	if damaged.is_empty():
		return
	await _click_button(app.camp_scene.hotspots[&"weapons"])
	await _type_text(WeaponInventory.short_id(damaged))
	_check(armory.items.item_count == 1 and armory._to_workshop.visible, "damaged instance routes to its workshop quote")
	await _click_button(armory._to_workshop)
	var quote: int = WeaponInventory.repair_quote(before, damaged)
	_check(armory._selected == damaged.instance_id and "实付 %d 币" % quote in armory._detail.text, "real repair quote corresponds to the exact item")
	await _shot("04-workshop")
	await _click_button(armory.repair_button)
	await _tap(armory.confirmation.get_ok_button())
	var repaired: Dictionary = app.camp_snapshot()
	_check(repaired.cash == before.cash - quote and WeaponInventory.find(repaired, damaged.instance_id).condition == "ready", "repair commits exactly one quoted payment")
	await _click_button(armory._to_inventory)
	_check(armory._selected == damaged.instance_id and not armory.confirm_equip.disabled, "workshop return reveals the same now-idle instance")
	var holder: int = armory.target.get_selected_id()
	var former: Dictionary = WeaponInventory.for_member(repaired, holder)
	await _click_button(armory.confirm_equip)
	var assigned: Dictionary = app.camp_snapshot()
	_check(WeaponInventory.owner(assigned, damaged.instance_id) == holder and WeaponInventory.owner(assigned, former.instance_id) == 0,
		"idle equipment transaction transfers real repaired item and returns previous one to stock")
	_write("armory-edit.json", {"camp_fingerprint":RecordEncoding.fingerprint(assigned), "owner":holder,
		"item":damaged.instance_id, "formerly_equipped":former.instance_id, "quote":quote})


func _resume() -> void:
	var proof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/armory-edit.json")))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var state: Dictionary = app.camp_snapshot()
	_check(RecordEncoding.fingerprint(state) == proof.camp_fingerprint, "different process restores exact confirmed inventory and repair payment")
	_check(WeaponInventory.owner(state, proof.item) == int(proof.owner) \
		and WeaponInventory.owner(state, proof.formerly_equipped) == 0, "reopened camp retains actual owner and idle previous equipment")
	for attempt: int in range(3):
		if not await _open_bus():
			return
		var slot: int = _weapon_offer(true)
		var match_drop: bool = slot >= 0
		if not match_drop:
			slot = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return action.type == "rescue")
		var match_rescue: bool = not match_drop and slot >= 0
		if not match_drop and not match_rescue:
			slot = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return action.type == "supply")
		if slot < 0:
			break
		await _click_button(app.mission_select.choices[slot])
		var world: Expedition = await _depart()
		if world == null:
			return
		if attempt == 0:
			_check(world.search_member(int(proof.owner)).weapon_instance_id == proof.item, "next real expedition deploys the repaired transferred instance")
		if match_drop:
			for site: Expedition.SearchSite in world.sites:
				if site.weapon:
					world.request_search(site.id)
					await _until(world, func() -> bool: return site.searched)
					break
		elif match_rescue:
			var candidate: RescueTarget = world.rescue_target
			_check(candidate != null, "normal rescue opens its original contact")
			if candidate == null:
				return
			candidate.request()
			await _until(world, func() -> bool: return candidate.progress >= RescueTarget.SECONDS)
			if not candidate.revealed():
				candidate.request()
				await _until(world, func() -> bool: return candidate.revealed())
		for site: Expedition.SearchSite in world.sites:
			if site.kind == &"food" and site.reward > 0 and not site.searched:
				world.request_search(site.id)
				await _until(world, func() -> bool: return site.searched)
				break
		await _extract(world)
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
		if match_drop or match_rescue:
			await _same_model_evidence(state, proof.formerly_equipped)
			return
	_check(false, "three normal days found no duplicate model for real two-instance comparison")


func _same_model_evidence(previous: Dictionary, idle_id: String) -> void:
	var camp: Dictionary = app.camp_snapshot()
	for item: Dictionary in camp.weapons:
		if not WeaponInventory.find(previous, item.instance_id).is_empty():
			continue
		var matches: Array = camp.weapons.filter(func(other: Dictionary) -> bool:
			return other.weapon_id == item.weapon_id and other.instance_id != item.instance_id and other.condition == "ready")
		if not matches.is_empty():
			await _click_button(app.camp_scene.hotspots[&"weapons"])
			armory = app.loadout_panel.armory
			var older: Dictionary = matches[0]
			var older_owner: int = WeaponInventory.owner(camp, older.instance_id)
			if item.condition == "ready" and older_owner > 0 and WeaponInventory.owner(camp, item.instance_id) > 0:
				# Use the real idle weapon from the original transfer to release one same-model item.
				var idle: Dictionary = WeaponInventory.find(camp, idle_id)
				if idle.is_empty() or WeaponInventory.owner(camp, idle_id) != 0:
					_check(false, "an actual idle weapon is available for the duplicate status case")
					return
				await _type_text(WeaponInventory.short_id(idle))
				_select_option(armory.target, armory.target.get_item_index(older_owner))
				await _click_button(armory.confirm_equip)
				camp = app.camp_snapshot()
			var distinct: bool = item.condition != older.condition or ((WeaponInventory.owner(camp, item.instance_id) > 0) != (WeaponInventory.owner(camp, older.instance_id) > 0))
			await _type_text(WeaponInventory.definition(item.weapon_id).display_name)
			_check(armory.items.item_count >= 2 and distinct, "same actual model renders distinct states and full instance IDs")
			await _shot("08-same-model-distinct-instances")
			return
	_check(false, "normal matching-model reward reached camp with distinct condition and identity")


func _open_bus() -> bool:
	await _click_button(app.camp_scene.hotspots[&"bus"])
	var deadline: int = Time.get_ticks_msec() + 90000
	while app.mission_select.loading and Time.get_ticks_msec() < deadline:
		await _frame()
	var ready: bool = app.mission_select.is_visible_in_tree() and not app.mission_select.daily_offers.is_empty()
	_check(ready, "native bus review produces usable signed cards")
	return ready


func _weapon_offer(require_duplicate: bool = false) -> int:
	var models: Array = app.camp_snapshot().weapons.map(func(item: Dictionary) -> String: return item.weapon_id)
	return app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool:
		return action.get("sites", []).any(func(site: Dictionary) -> bool:
			return site.get("weapon", false) and (not require_duplicate or site.get("drop", {}).get("weapon_id") in models)))


func _depart() -> Expedition:
	await _click_button(app.mission_select.depart_button)
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "real departure confirmation starts a durable world")
	if world != null:
		world.set_physics_process(false)
		world.set_process(false)
		await _until(world, func() -> bool: return not world.bus_view.running())
	return world


func _select_option(button: OptionButton, index: int) -> void:
	button.select(index)
	button.item_selected.emit(index)


func _type_text(value: String) -> void:
	await _click(armory.search.get_global_rect().get_center())
	await _key(KEY_A, 0, true)
	for index: int in range(value.length()):
		await _key(KEY_NONE, value.unicode_at(index))
	await _hold(2)


func _key(code: Key, unicode: int = 0, control: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = unicode
		event.ctrl_pressed = control
		event.pressed = pressed
		viewport.push_input(event, true)
		await _frame()


func _click_button(button: Button) -> void:
	await _hold(2)
	_check(button.is_visible_in_tree() and not button.disabled and viewport.get_visible_rect().encloses(button.get_global_rect()),
		"visible pointer target: " + button.text)
	if button.is_visible_in_tree() and not button.disabled:
		await _click(button.get_global_rect().get_center())


func _click(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	await _frame()
	await _mouse(point, MOUSE_BUTTON_LEFT, true)
	await _mouse(point, MOUSE_BUTTON_LEFT, false)
	await _hold(3)


func _mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	viewport.push_input(event, true)
	await _frame()


func flow_input_description() -> String:
	return "Godot viewport mouse, wheel, Unicode keys and Tab; option-selected signals; original world intentions; no physical input"
