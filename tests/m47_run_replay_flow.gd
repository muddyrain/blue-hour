extends "res://tests/m46_campaign_flow.gd"
## Native viewport scenarios. Directed lethal damage is explicitly separated from the normal route.

var streets: Array[Dictionary] = []


func _journey() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_check("--bh-open-streets" not in args and "--open-streets" not in args, "M47 uses the standard entry without a pilot flag")
	match output.get_file():
		"opening-layout":
			await _opening_layout()
		"victory":
			if not await _new_trip("scavenge", true):
				return
			await _finish_campaign("standard-m47")
			var projection: Dictionary = app.progress_session.catalog_state()
			_check(projection.error == OK and projection.specialties == {"scavenge":2, "firepower":0, "support":0}
				and projection.specialization_result.delta == 2, "confirmed pump victory banks two experience on the chosen specialty")
			_write("progress.json", projection)
			await _shot("03-terminal-specialization")
		"wipe", "early-wipe":
			await _directed_wipe(output.get_file() == "wipe")
		"maps", "field-before":
			if await _new_trip("support"):
				await _map_case(output.get_file() == "field-before")
		"cards":
			if await _new_trip("support") and await _open_cards():
				_write("signed-maps.json", {"offers":_signed_maps()})
		_:
			_check(false, "known M47 flow phase")
	_write("streets.json", {"sorties":streets})


func _resume() -> void:
	match output.get_file():
		"reward":
			await _reward_trip("scavenge")
		"repeat-victory":
			if not await _new_trip("scavenge"):
				return
			await _finish_campaign("second-scavenge-victory")
			var progress: Dictionary = app.progress_session.catalog_state()
			_check(progress.error == OK and progress.specialties.scavenge == 4
				and progress.specialization_result.shared == [OpeningBuild.PLANS.scavenge.unlock_id],
				"second confirmed victory opens the reward to other specialties")
			_write("shared-progress.json", progress)
		"shared-reward":
			await _reward_trip("support")
		"field-after":
			await _tap(app._continue_button)
			if app._hunger_confirmation.visible:
				await _tap(app._hunger_confirmation.get_ok_button())
			var world: Expedition = app.expedition
			var proof: Dictionary = _checkpoint(world, "field-before/street-checkpoint.json")
			if not proof.is_empty():
				_check(RecordEncoding.fingerprint(world.layout.world_data.bus) == proof.bus
					and world.food_loot == int(proof.food), "restored street keeps the original road and carried food")
				await _unpause(world)
				await _finish_outing(world)
		_:
			_check(false, "known M47 continuation phase")
	_write("streets.json", {"sorties":streets})


func _new_trip(plan: String, cancel_probe: bool = false) -> bool:
	var launch: Button = app.get_node("Interface/Screen/Title/Reset") if not app._home_button.is_visible_in_tree() else app._home_button
	await _tap(launch)
	_check(app._new_game_confirmation.visible and app._opening_picker.choices.size() == 3,
		"the ordinary title offers all three opening cards")
	if cancel_probe:
		await _shot("01-opening-specialties")
		var before: Dictionary = app.progress_session.inspect()
		await _tap(app._new_game_confirmation.get_cancel_button())
		await _tap(launch)
		_check(TransactionReceipt.same(before, app.progress_session.inspect()) and not FileAccess.file_exists(app.progress_path),
			"cancelling and reopening leave the durable profile untouched")
	await _tap(app._opening_picker.choices[plan])
	await _tap(app._new_game_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	var created: bool = app.camp_scene.visible and not app._progress_blocked and OpeningBuild.is_m47(camp)
	_check(created, "the ordinary confirmation durably creates an M47 journey")
	if not created:
		return false
	var item: String = OpeningBuild.PLANS[plan].item_id
	_check(OpeningBuild.plan(camp) == plan and camp.journey.campaign.open_streets_policy == OpenStreetsV1.VERSION
		and camp.journey.build.owned == [item] and camp.journey.build.slots == [item, ""]
		and camp.journey.build.powers.owned.is_empty(), "the confirmed origin freezes its map and equips only the single starter")
	_write("initial.json", {"plan":plan, "seed":camp.journey.seed, "cash":camp.cash,
		"food":camp.food, "crew":camp.crew, "weapons":camp.weapons,
		"eligible":OpeningBuild.eligible(camp), "policy":camp.journey.campaign.open_streets_policy})
	return true


func _map_case(suspend: bool) -> void:
	if not await _open_cards():
		return
	var requested: String = _argument("--flow-theme=")
	var requested_size: String = _argument("--flow-size=")
	var index: int = -1
	for i: int in range(app.mission_select.daily_offers.size()):
		var action: Dictionary = app.mission_select.daily_offers[i]
		var layout: Dictionary = action.layout
		if (requested.is_empty() or requested == layout.topology) and (requested_size == layout["size"]
				or (requested_size.is_empty() and layout.has("open_streets"))):
			index = i
		if action.type == "rescue":
			_check("待救援幸存者" in app.mission_select._descriptions[i].text, "normal rescue card keeps the candidate anonymous")
	_write("signed-maps.json", {"offers":_signed_maps()})
	var world: Expedition = await _start(index)
	if world == null:
		return
	var objectives: Array = world.supply.generated.objective.site_ids
	if not objectives.is_empty():
		await _search(world, world.search_site(StringName(objectives[0])))
	if suspend:
		await _suspend(world, "street-checkpoint.json", {"bus":RecordEncoding.fingerprint(world.layout.world_data.bus),
			"food":world.food_loot})
	else:
		await _finish_outing(world)


func _signed_maps() -> Array[Dictionary]:
	var signed: Array[Dictionary] = []
	for action: Dictionary in app.mission_select.daily_offers:
		_check(DailyActions.problem(action).is_empty(), "candidate authenticates against the existing signed action contract")
		signed.append(_geometry(action))
	return signed


func _geometry(action: Dictionary) -> Dictionary:
	var layout: Dictionary = action.layout
	var district: Dictionary = layout.get("themed_district", layout.get("warehouse_district", {}))
	return {"action":action.id, "signature":RecordEncoding.fingerprint(action),
		"layout":RecordEncoding.fingerprint(layout), "size":layout["size"], "bounds":layout.bounds,
		"theme":layout.topology, "family":district.get("family", ""),
		"revision":layout.get("open_streets", layout.get("scenery_revision", 0)), "fallback":layout.fallback,
		"buildings":layout.entities.size(), "task":action.type, "bus":layout.bus}


func _extract(world: Expedition) -> void:
	if not world.layout.world_data.has("open_streets"):
		await super._extract(world)
		return
	await _until(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds)
	world.request_bus_action()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	world.request_bus_gather()
	await _until(world, func() -> bool: return world.bus_view.stage == "embarking")
	var bus: BusJourney = world.bus_view
	if bus.stage != "embarking":
		return
	var parked: Vector2 = world._bus_sprite.position
	var occupants: int = bus._boarding_actors.size()
	var ready: Dictionary = app.progress_session.inspect()
	var terminal_failure: bool = app._pending_settlement.journey.state == "FAILED"
	_check(ready.receipt.phase == "RESULT_READY" and app.phase == app.Phase.EXPEDITION,
		"roadside boarding holds the frozen result behind the visible bus sequence")
	await _advance(world, func() -> bool: return bus._boarding_index >= 1, 200)
	if occupants >= 2:
		_check(bus._boarding_index == 1 and not bus._boarding_actors[0].visible and bus._boarding_actors[1].visible
			and world._bus_sprite.position == parked, "one survivor boards before the next moves through the door")
	if streets.is_empty() and output.get_file() in ["victory", "maps"]:
		await _shot("02-standard-street-bus")
	await _advance(world, func() -> bool: return bus.stage == "departing", 500)
	var direction: Vector2 = (WorldLayout.point(bus.route.out_path[1]) - parked).normalized()
	world.step(0.15)
	_check((world._bus_sprite.position - parked).dot(direction) > 0.0 and bus._boarding_index == occupants,
		"after all living passengers board, the bus begins moving along the certified road")
	var tail_gate: bool = false
	for tick: int in range(1800):
		if bus.stage == "done":
			break
		world.step(STEP)
		if not world.layout.world_bounds.has_point(world._bus_sprite.position) and not bus._entire_bus_outside():
			tail_gate = app.phase == app.Phase.EXPEDITION and not app._screen.visible
		if tick % 28 == 0:
			await _frame()
	var shown: Dictionary = app.progress_session.inspect()
	var unchanged: bool = shown.receipt.phase == "COMMITTED" if terminal_failure else shown.hash == ready.hash
	_check(tail_gate and bus._entire_bus_outside() and app.phase == app.Phase.RESULT and unchanged,
		"result remains hidden with the tail in bounds and opens after full exit using the same frozen receipt")
	streets.append(_geometry(world.supply.generated).merged({"boarded":occupants,
		"direction":[direction.x, direction.y], "tail_gate":tail_gate, "ready_hash":ready.hash}))
	await _hold(3)


func _reward_trip(plan: String) -> void:
	if not await _new_trip(plan):
		return
	var unlocked: String = OpeningBuild.PLANS.scavenge.unlock_id
	_check(OpeningBuild.eligible(app.camp_snapshot()) == [unlocked], "next eligible journey freezes the committed unlock")
	var found: bool = false
	for attempt: int in range(5):
		if not await _open_cards():
			return
		var index: int = _find_card(func(action: Dictionary) -> bool: return BuildActions.specialization_candidate(action) == unlocked)
		var world: Expedition = await _start(index if index >= 0 else _find_card(func(action: Dictionary) -> bool: return action.type == "supply"))
		if world == null:
			return
		if index >= 0:
			await _search(world, world.search_site(&"cash"))
		else:
			await _food(world, 4)
		if index >= 0:
			_check(not unlocked in app.camp_snapshot().journey.build.owned, "search reward stays outside camp until confirmation")
		await _finish_outing(world)
		if index >= 0:
			found = unlocked in app.camp_snapshot().journey.build.owned
			break
	_check(found, "the original gear action search and bus confirmation bring the unlock into camp")
	if not found:
		return
	_check(app.progress_session.catalog_state().specialty_discoveries.has(unlocked), "catalog now records the actual confirmed discovery")
	if not await _equip_passive(1, unlocked):
		return
	var field: Expedition = await _ordinary_supply()
	if field == null:
		return
	var factors: Dictionary = BuildItems.frozen_factors(field.supply.generated.build)
	var actor_speed: float = field.search_member(1).effective_speed()
	_check(is_equal_approx(factors.move, 1.10) and is_equal_approx(factors.work, 0.75 if plan == "scavenge" else 1.0),
		"ordinary next deployment freezes the equipped harness alongside the untouched work factor")
	await _shot("04-unlock-in-use")
	await _food(field, 2)
	await _finish_outing(field)
	_write("reward-route.json", {"sorties":route, "factors":factors, "actor_speed":actor_speed,
		"discovery":app.progress_session.catalog_state().specialty_discoveries[unlocked]})


func _equip_passive(slot: int, id: String) -> bool:
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var loadout: LoadoutPanel = app.loadout_panel
	await _tap(loadout.armory._nav[&"support"])
	var choice: OptionButton = loadout.build_panel.slot_choices[slot]
	var index: int = loadout.build_panel._index_for(choice, id)
	_check(index > 0 and choice.get_item_metadata(index) == id, "the recovered item appears in the camp's real passive slot dropdown")
	if index <= 0:
		return false
	await _tap(choice)
	var popup: PopupMenu = choice.get_popup()
	_check(popup.visible, "passive slot opens its normal dropdown")
	if not popup.visible:
		return false
	popup.set_focused_item(index)
	for down: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = down
		viewport.push_input(key, true)
		await _frame()
	await _hold(4)
	var equipped: bool = not app._progress_blocked and app.camp_snapshot().journey.build.slots[slot] == id
	_check(equipped, "normal camp dropdown confirms and saves the recovered passive")
	await _tap(loadout.back_button)
	return equipped


func _investigate() -> bool:
	if not await _open_cards():
		return false
	var before: Dictionary = app.camp_snapshot()
	var world: Expedition = await _start(_find_card(func(action: Dictionary) -> bool: return action.has("investigation")))
	if world == null:
		return false
	var clue: Dictionary = world.supply.generated.investigation
	await _search(world, world.search_site(StringName(clue.site_id)))
	await _food(world, 4)
	await _finish_outing(world)
	var after: Dictionary = app.camp_snapshot()
	var credited: bool = after.journey.campaign.clues.size() == before.journey.campaign.clues.size() + 1
	_check(credited and after.journey.campaign.clues.back().id == clue.clue_id, "real investigation banks the selected clue after extraction")
	return credited


func _finish_campaign(branch: String) -> void:
	if app.camp_snapshot().settled_sorties == 0:
		var supplies: Expedition = await _ordinary_supply()
		if supplies == null:
			return
		await _food(supplies, 6)
		await _finish_outing(supplies)
	await super._finish_campaign(branch)


func _directed_wipe(qualified: bool) -> void:
	if not await _new_trip("firepower"):
		return
	if qualified:
		for index: int in range(2):
			var outing: Expedition = await _ordinary_supply()
			if outing == null:
				return
			await _collect(outing, 5)
			await _finish_outing(outing)
	var world: Expedition = await _ordinary_supply()
	if world == null:
		return
	for actor: FieldActor in world.survivors:
		actor.take_damage(actor.health + 1.0)
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	var projection: Dictionary = app.progress_session.catalog_state()
	var expected: int = int(qualified)
	_check(app.progress_session.inspect().state == "ENDED" and projection.error == OK
		and projection.specialties.firepower == expected and projection.specialties.scavenge == 0
		and projection.specialties.support == 0 and projection.specialization_result.delta == expected,
		"real death gates and terminal confirmation grant +1 only after two earlier returns")
	_write("wipe.json", {"scope":"DIRECTED_LETHAL_DAMAGE", "returns":route, "progress":projection})


func _argument(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func _opening_layout() -> void:
	for frame_size: Vector2i in [Vector2i(1280, 720), Vector2i(1440, 900)]:
		viewport.size = frame_size
		await _hold(5)
		await _tap(app._home_button)
		var dialog: ConfirmationDialog = app._new_game_confirmation
		var position: Vector2 = Vector2(dialog.position)
		var confirm: Button = dialog.get_ok_button()
		var cancel: Button = dialog.get_cancel_button()
		var rect: Rect2 = viewport.get_visible_rect()
		_check(rect.encloses(Rect2(confirm.get_global_rect().position + position, confirm.size))
			and rect.encloses(Rect2(cancel.get_global_rect().position + position, cancel.size)),
			"both dialog actions are inside the %s native viewport" % frame_size)
		var capture: String = "01-opening-specialties" if frame_size.x == 1280 else "alternate-opening-layout"
		await _shot(capture)
		await _mouse_dialog(cancel, position)
		_check(not dialog.visible and not FileAccess.file_exists(app.progress_path), "mouse cancel closes the dialog without creating a journey")


func _mouse_dialog(button: Button, dialog_position: Vector2) -> void:
	var point: Vector2 = button.get_global_rect().get_center() + dialog_position
	for down: bool in [true, false]:
		var mouse: InputEventMouseButton = InputEventMouseButton.new()
		mouse.position = point
		mouse.global_position = point
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = down
		viewport.push_input(mouse, true)
		await _frame()
	await _hold(3)


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _hold(2)
	RenderingServer.force_draw()
	var image: Image = viewport.get_texture().get_image()
	_check(image.get_size() == viewport.size
		and image.save_png(output.path_join(label + ".png")) == OK, "native viewport capture " + label)
