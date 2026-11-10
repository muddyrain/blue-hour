extends "res://tests/m40_workshop_flow.gd"
## Two ordinary journeys from the same confirmed camp. Field time advances by real world steps.

var route: Array[Dictionary] = []
var start_hash: String = ""
var rifle_id: String = ""
var support_id: String = ""
var trained_shot: float = 0.0


func _initialize() -> void:
	exercise_departure_review = true
	super()


func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(CampFacilities.tier_two_enabled(app.camp_snapshot()), "fresh ordinary journey freezes tier-two facility policy")
	if not await _open_cards():
		return
	var world: Expedition = await _start(_find_card(func(action: Dictionary) -> bool: return action.type == "supply"))
	if world == null:
		return
	await _collect(world, 7)
	await _finish_outing(world)
	var camp: Dictionary = app.camp_snapshot()
	_check(camp.settled_sorties == 1 and camp.last_day.evacuated and CampFacilities.can_build(camp, CampFacilities.SUPPLY)
		and CampFacilities.can_build(camp, CampFacilities.WORKSHOP), "one real confirmed return unlocks both routes")
	_write("common.json", {"camp":RecordEncoding.fingerprint(camp), "seed":camp.journey.seed, "sorties":route})
	await _shot("01-camp")


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var phase_name: String = output.get_file()
	if phase_name == "b-resume":
		await _resume_rifle()
		return
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked, "fresh process continues the path-bound isolated camp")
	if not app.camp_scene.is_visible_in_tree() or app._progress_blocked:
		return
	var camp: Dictionary = app.camp_snapshot()
	var common: Dictionary = _read("setup/common.json")
	start_hash = common.camp
	match phase_name:
		"route-a", "b-prepare":
			_check(RecordEncoding.fingerprint(camp) == start_hash, "fork opens the exact same first confirmed camp")
			if phase_name == "route-a":
				await _supply_route()
			else:
				await _prepare_rifle()
		"b-extended", "b-quick":
			var prepared: Dictionary = _read("b-prepare/prepared.json")
			_check(RecordEncoding.fingerprint(camp) == prepared.camp, "both magazine variants fork the exact same rifle and toolbox")
			rifle_id = prepared.rifle
			support_id = prepared.support
			route.assign(prepared.sorties)
			await _rifle_outing(WorkshopV1.EXTENDED if phase_name == "b-extended" else WorkshopV1.QUICK)
		_:
			_check(false, "recognized M46 phase: " + phase_name)


func _supply_route() -> void:
	if not _build(CampFacilities.SUPPLY):
		return
	var first: Expedition = await _ordinary_supply()
	if first == null:
		return
	await _collect(first, 6)
	await _finish_outing(first)
	var ledger: Dictionary = app.camp_snapshot().last_day
	_check(ledger.get("facility_food") == 2 and ledger.get("facility_stored") == 2, "tier one return credits exactly two real facility rations")
	if not _upgrade(CampFacilities.SUPPLY, "before_camp_write"):
		return
	var second: Expedition = await _ordinary_supply()
	if second == null:
		return
	await _collect(second, 6)
	await _finish_outing(second)
	var camp: Dictionary = app.camp_snapshot()
	ledger = camp.last_day
	var counterfactual: Dictionary = CampEconomy.post_battle_food(int(ledger.day), camp.crew, int(ledger.food_before),
		int(ledger.food_found), int(ledger.ration_per_member), true, CampFacilities.SUPPLY_FOOD)
	_check(ledger.get("facility_food") == 3 and ledger.get("facility_stored") == 3 and int(ledger.food_after) == int(counterfactual.get("food_after", -999)) + 1,
		"tier two return credits three rations and one additional real unit over the tier-one counterfactual")
	_write("supply-ledger.json", {"actual":ledger, "tier_one_counterfactual":counterfactual,
		"facility_overflow":int(ledger.get("facility_food", 0)) - int(ledger.get("facility_stored", 0))})
	await _train()
	await _finish_campaign("A")


func _train() -> void:
	var before: Dictionary = app.camp_snapshot()
	var member: Dictionary = SurvivorRoster.member(before.crew, 1)
	var untrained: float = TraitRules.factor(member, "shot")
	var previous_trait: Dictionary = member.growth.trait
	var level: int = int(previous_trait.level)
	_check(level < TraitRules.THRESHOLDS.size(), "the ordinary shooting trait still has a training step")
	if level >= TraitRules.THRESHOLDS.size():
		return
	var required: int = TraitRules.THRESHOLDS[level] - int(previous_trait.progress)
	_check(required > 0 and int(before.food) >= required + int(before.last_day.food_required),
		"legitimate stores can fund the next trait step and leave a meal")
	if required <= 0 or int(before.food) < required:
		return
	app.open_training()
	await _tap(app.training_panel.member_buttons[1])
	for count: int in range(required):
		await _tap(app.training_panel.train_button)
		if count == 0:
			await _shot("05-training")
		await _tap(app.training_panel.confirmation.get_ok_button())
	var after: Dictionary = app.camp_snapshot()
	var final_member: Dictionary = SurvivorRoster.member(after.crew, 1)
	trained_shot = TraitRules.factor(final_member, "shot")
	_check(int(after.food) == int(before.food) - required and trained_shot < untrained,
		"ordinary one-ration training reaches the next existing trait threshold")
	training_effects.append({"untrained":untrained, "trained":trained_shot, "food_spent":required,
		"trait_before":previous_trait, "trait_after":final_member.growth.trait})
	await _tap(app.training_panel.back_button)


func _prepare_rifle() -> void:
	if not _build(CampFacilities.WORKSHOP):
		return
	for attempt: int in range(4):
		if not await _open_cards():
			return
		var toolbox_index: int = _find_card(func(action: Dictionary) -> bool: return not WorkshopSiteV1.site_id(action).is_empty())
		var index: int = toolbox_index if toolbox_index >= 0 else _find_card(func(action: Dictionary) -> bool: return action.type == "supply")
		var world: Expedition = await _start(index)
		if world == null:
			return
		await _collect(world, 5)
		var toolbox: Expedition.SearchSite = world._toolbox_site()
		if toolbox != null and not toolbox.searched:
			await _search(world, toolbox)
			await _shot("toolbox-recovered")
		await _finish_outing(world)
		if WorkshopV1.tools(app.camp_snapshot()) > 0:
			break
	_check(WorkshopV1.tools(app.camp_snapshot()) > 0, "a normal certified optional site banks a real toolbox")
	if WorkshopV1.tools(app.camp_snapshot()) == 0 or not _upgrade(CampFacilities.WORKSHOP, "after_record_publish"):
		return
	if app.camp_snapshot().journey.build.powers.owned.is_empty():
		if not await _investigate():
			return
	var camp: Dictionary = app.camp_snapshot()
	var owned: Array = camp.journey.build.powers.owned
	_check(not owned.is_empty(), "normal main site returned a real special power")
	if owned.is_empty():
		return
	support_id = owned[0]
	var rifle_index: int = camp.weapons.find_custom(func(item: Dictionary) -> bool:
		return item.weapon_id == "long_rifle" and item.condition == "ready" and WorkshopV1.mod_problem(camp, item.instance_id, WorkshopV1.QUICK).is_empty())
	_check(rifle_index >= 0, "calibration bench permits an authentic ready ordinary long rifle")
	if rifle_index < 0:
		return
	rifle_id = camp.weapons[rifle_index].instance_id
	if not _edit({"kind":"power_equip", "member_id":0, "value":support_id}):
		return
	_write("prepared.json", {"camp":RecordEncoding.fingerprint(app.camp_snapshot()), "rifle":rifle_id,
		"support":support_id, "sorties":route, "starting_camp":start_hash})


func _rifle_outing(mod: String) -> void:
	var before: Dictionary = app.camp_snapshot()
	var item: Dictionary = WeaponInventory.find(before, rifle_id)
	var fault: String = "before_camp_write" if mod == WorkshopV1.EXTENDED else "after_record_publish"
	if not _edit({"kind":mod, "member_id":0, "value":rifle_id}, fault):
		return
	var after: Dictionary = app.camp_snapshot()
	_check(after.cash == before.cash - 8 and WorkshopV1.tools(after) == WorkshopV1.tools(before) - 1
		and WorkshopV1.mod_for(after, rifle_id) == mod and TransactionReceipt.same(item, WeaponInventory.find(after, rifle_id)),
		"rifle edit debits one toolbox and eight coins while preserving the original instance")
	if WeaponInventory.owner(after, rifle_id) != 1 and not _edit({"kind":"equip", "member_id":1, "value":rifle_id}):
		return
	var world: Expedition = await _ordinary_supply()
	if world == null:
		return
	var actor: FieldActor = world.search_member(1)
	var gun: WeaponMagazine = actor.magazine
	var parameters: Dictionary = WeaponMagazine.parameters("long_rifle", mod)
	initial = {"instance_id":rifle_id, "mod":mod, "capacity":gun.capacity(), "base_seconds":parameters.seconds,
		"factor":gun.reload_factor, "seconds":gun.seconds(), "action":world.supply.generated.id, "map":world.layout.id}
	_check(gun.instance_id == rifle_id and gun.modification == mod and gun.capacity() == parameters.capacity
		and gun.rounds == gun.capacity() and is_equal_approx(gun.seconds(), float(parameters.seconds) * gun.reload_factor),
		"next normal field uses the same equipped modified rifle, full capacity and holder reload factor")
	_measure_initial(world, actor)
	if mod == WorkshopV1.QUICK:
		_check(world.request_power(0), "existing equipped support activates through the original field transaction")
		var event: Dictionary = SpecialPowers.event_at(world.powers, 0)
		_check(event.get("ability_id") == support_id and SpecialPowers.remaining(world.powers, world.elapsed, 0) > 0.0
			and not world.request_power(0), "active support interval exists and a second activation cannot spend the same slot")
		_write("support.json", {"event":event, "used":not event.is_empty(), "remaining":SpecialPowers.remaining(world.powers, world.elapsed, 0)})
	await _drive(world, func() -> bool: return gun.reloading)
	_check(gun.reloading and shot_count == gun.capacity(), "real attacks empty the entire modified rifle magazine")
	if not gun.reloading:
		return
	reload_started = world.elapsed
	if mod == WorkshopV1.QUICK:
		await _drive(world, func() -> bool: return gun.remaining <= gun.seconds() - 0.2)
		_check(gun.reloading and gun.rounds == 0 and gun.remaining > 0.0, "quick rifle is in a real partial reload at suspend")
		await _suspend(world, "magazine-checkpoint.json", {"initial":initial, "magazine":gun.snapshot(),
			"magazine_hash":RecordEncoding.fingerprint(gun.snapshot()), "shots":shot_count,
			"reload_started":reload_started, "sorties":route, "starting_camp":start_hash})
		return
	await _measure_reload(world, actor)
	await _finish_outing(world)


func _resume_rifle() -> void:
	var world: Expedition = app.expedition
	var proof: Dictionary = _checkpoint(world, "b-quick/magazine-checkpoint.json")
	if proof.is_empty():
		return
	initial = proof.initial
	start_hash = proof.starting_camp
	route.assign(proof.sorties)
	shot_count = int(proof.shots)
	reload_started = float(proof.reload_started)
	var actor: FieldActor = world.search_member(1)
	var gun: WeaponMagazine = actor.magazine
	_check(gun.instance_id == initial.instance_id and gun.modification == initial.mod
		and RecordEncoding.fingerprint(gun.snapshot()) == proof.magazine_hash, "fresh process restores the exact modified rifle and partial reload")
	await _unpause(world)
	await _measure_reload(world, actor)
	var used: Dictionary = SpecialPowers.event_at(world.powers, 0)
	_check(not used.is_empty() and SpecialPowers.remaining(world.powers, world.elapsed, 0) == 0.0
		and not world.request_power(0), "expired support keeps its used charge after real field continuation")
	_write("support-resumed.json", {"used":used, "elapsed":world.elapsed,
		"remaining":SpecialPowers.remaining(world.powers, world.elapsed, 0)})
	await _finish_outing(world)
	await _finish_campaign("B")


func _measure_reload(world: Expedition, actor: FieldActor) -> void:
	var gun: WeaponMagazine = actor.magazine
	await _drive(world, func() -> bool: return not gun.reloading)
	var measured: float = world.elapsed - reload_started
	var immediate_shot: bool = events.any(func(event: Dictionary) -> bool:
		return event.kind == "shot" and event.member_id == actor.member_id and event.elapsed == world.elapsed)
	var refill: int = gun.rounds + int(immediate_shot)
	_check(not gun.reloading and absf(measured - gun.seconds()) <= STEP + 0.0001 and refill == gun.capacity(),
		"actual reload time matches the frozen effective seconds and refills the modified magazine")
	_write("rifle-measurement.json", {"initial":initial, "shots":shot_count, "elapsed":measured, "refill":refill})
	await _shot("rifle-in-action")


func _build(choice: String) -> bool:
	var before: Dictionary = app.camp_snapshot()
	if not _edit({"kind":"facility", "member_id":0, "value":choice}):
		return false
	var after: Dictionary = app.camp_snapshot()
	_check(CampFacilities.selected(after) == choice and after.cash == before.cash - CampFacilities.BUILD_COST,
		"normal investment charges only the existing level-one cost")
	_check(not CampFacilities.upgrade_offer(after, choice).available, "upgrade is blocked until a later confirmed return")
	return true


func _upgrade(choice: String, fault: String) -> bool:
	var before: Dictionary = app.camp_snapshot()
	_check(CampFacilities.upgrade_offer(before, choice).available, "the later successful confirmed return unlocks tier two")
	if not _edit({"kind":"facility_upgrade", "member_id":0, "value":choice}, fault):
		return false
	var after: Dictionary = app.camp_snapshot()
	_check(CampFacilities.upgraded(after) and after.cash == before.cash - 10 and after.camp_spending == before.camp_spending + 10,
		"one upgrade charges ten coins and advances only the selected facility")
	return true


func _edit(request: Dictionary, fault: String = "") -> bool:
	var before: Dictionary = app.camp_snapshot()
	var injected: Dictionary = {"publishes":0, "failures":0}
	if not fault.is_empty():
		app.progress_session.fault_hook = func(point: String) -> Error:
			if point == "after_record_publish":
				injected.publishes += 1
			if point == fault and (point != "after_record_publish" or injected.publishes == 2):
				injected.failures += 1
				return ERR_CANT_CREATE
			return OK
	var result: Dictionary = app.progress_session.edit(before, request)
	app.progress_session.fault_hook = Callable()
	var edit_id: String = app.progress_session._pending_edit
	if not fault.is_empty():
		var published: bool = app._accept_transaction(result, true)
		var durable: Dictionary = app.progress_session._transaction.recover()
		var disk: Dictionary = app.progress_session._transaction._save.read_transaction_exact()
		var expected_phase: String = "EDIT_READY" if fault == "before_camp_write" else "EDIT_COMMITTED"
		var expected_camp: Dictionary = before if expected_phase == "EDIT_READY" else CampEdit.propose(before, request)
		_check(injected.failures == 1 and result.error != OK and not published and app._progress_blocked
			and app._progress_dirty and durable.receipt.phase == expected_phase
			and disk.error == OK and TransactionReceipt.same(disk.data, expected_camp)
			and TransactionReceipt.same(before, app.camp_snapshot()), "injected %s leaves exact durable phase and no premature UI update" % fault)
		result = app.progress_session.retry()
	var accepted: bool = app._accept_transaction(result, true)
	_check(accepted, "real camp edit commits: %s" % request.kind)
	if not accepted:
		return false
	if not fault.is_empty():
		var committed: Dictionary = app.progress_session._transaction.recover()
		var repeated: Dictionary = app.progress_session._transaction.commit_edit(edit_id)
		var journal: ReceiptJournal = ReceiptJournal.new(app.progress_session._transaction._journal.directory)
		var replay: Dictionary = journal.read_all()
		_check(repeated.error == OK and replay.error == OK and committed.hash == repeated.hash and committed.hash == replay.hash
			and committed.receipt.transaction_id == edit_id and TransactionReceipt.same(TransactionReceipt.camp(replay.receipt), app.camp_snapshot()),
			"retry, repeated confirmation and independent journal replay preserve one edit identity and debit")
		_write("fault-%s.json" % request.kind, {"point":fault, "edit":edit_id, "receipt":committed.hash,
			"before_cash":before.cash, "after_cash":app.cash, "before_tools":WorkshopV1.tools(before), "after_tools":WorkshopV1.tools(app.camp_snapshot())})
	return true


func _open_cards() -> bool:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var deadline: int = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var menu: MissionSelect = app.mission_select
		if menu.visible and not menu.daily_offers.is_empty() and menu.choices[0].is_visible_in_tree() and not menu.choices[0].disabled:
			return true
		await _frame()
	_check(false, "normal bus presents selectable certified cards")
	return false


func _find_card(predicate: Callable) -> int:
	return app.mission_select.daily_offers.find_custom(predicate)


func _start(slot: int) -> Expedition:
	_check(slot >= 0, "a legal card exists for this route")
	if slot < 0:
		return null
	_before = app.camp_snapshot()
	var expected: Dictionary = app.mission_select.daily_offers[slot]
	await _tap(app.mission_select.choices[slot])
	if app.expedition == null:
		var depart: Button = app.mission_select.get("depart_button") as Button
		if is_instance_valid(depart):
			if PumpStationAction.enabled(expected):
				await _shot("07-departure")
			await _tap(depart)
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "confirmed card opens the real original expedition")
	if world == null:
		return null
	_check(TransactionReceipt.same(world.supply.generated, expected), "field uses the same exact candidate selected in the UI")
	world.set_physics_process(false)
	world.set_process(false)
	await _until(world, func() -> bool: return not world.bus_view.running())
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	if trained_shot > 0.0:
		var actor: FieldActor = world.search_member(1)
		_check(actor != null and is_equal_approx(actor.trait_shot_factor, trained_shot), "real field actor uses the trained trait factor")
		training_effects.back().field_factor = actor.trait_shot_factor
		trained_shot = 0.0
	return world


func _ordinary_supply() -> Expedition:
	if not await _open_cards():
		return null
	return await _start(_find_card(func(action: Dictionary) -> bool: return action.type == "supply" and not PumpStationAction.enabled(action)))


func _collect(world: Expedition, desired_food: int) -> void:
	var cash_site: Expedition.SearchSite = world.search_site(&"cash")
	if cash_site != null and world.supply.supports(cash_site.kind) and not cash_site.searched:
		await _search(world, cash_site)
	await _food(world, desired_food)


func _finish_outing(world: Expedition) -> void:
	var action: Dictionary = world.supply.generated
	world.command_move(world.layout.bus_door)
	var committed: Dictionary = await _bank(world)
	var camp: Dictionary = app.camp_snapshot()
	route.append({"day":action.day, "action":action.id, "signature":RecordEncoding.fingerprint(action),
		"map":action.layout.id, "receipt":committed.get("hash", ""), "ledger":camp.last_day,
		"food":camp.food, "cash":camp.cash, "toolboxes":WorkshopV1.tools(camp),
		"clues":camp.journey.campaign.clues.map(func(clue: Dictionary) -> String: return clue.id)})


func _extract(world: Expedition) -> void:
	await _until(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds)
	world.request_bus_action()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	world.request_bus_gather()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	for tick: int in range(1500):
		if not world.bus_view.running():
			break
		world.step(STEP)
		if tick % 30 == 0:
			await _frame()
	var gathered: Vector2i = world.bus_view.final_boarding
	_check(app.phase == app.Phase.RESULT and gathered.x == gathered.y and gathered.y == world.living_count(),
		"real bus gathers living crew and completes its departure before result")
	await _hold(3)


func _investigate() -> bool:
	if not await _open_cards():
		return false
	var before: Dictionary = app.camp_snapshot()
	var world: Expedition = await _start(_find_card(func(action: Dictionary) -> bool: return action.has("investigation")))
	if world == null:
		return false
	var clue: Dictionary = world.supply.generated.investigation
	await _search(world, world.search_site(StringName(clue.site_id)))
	await _food(world, 5)
	await _finish_outing(world)
	var after: Dictionary = app.camp_snapshot()
	_check(after.journey.campaign.clues.size() == before.journey.campaign.clues.size() + 1
		and after.journey.campaign.clues.back().id == clue.clue_id, "actual investigation credits exactly the selected clue on confirmed return")
	return after.journey.campaign.clues.size() > before.journey.campaign.clues.size()


func _finish_campaign(branch: String) -> void:
	while app.camp_snapshot().journey.campaign.clues.size() < 2:
		if not await _investigate():
			return
	if not await _open_cards():
		return
	var world: Expedition = await _start(_find_card(func(action: Dictionary) -> bool: return PumpStationAction.enabled(action)))
	if world == null:
		return
	await _search(world, world.search_site(PumpStationAction.CONSOLE))
	_check(world.station_stopped() and world.encounter != null, "real console work shuts down the pump and exposes the boss")
	await _shot("pump-console")
	await _fight_pump(world)
	_check(not world.encounter.defeat.is_empty() and world.living_count() > 0, "real attacks kill the boss with living survivors")
	if world.encounter.defeat.is_empty():
		return
	await _shot("pump-boss-defeated")
	await _finish_outing(world)
	var saved: Dictionary = app.camp_snapshot()
	_check(saved.journey.campaign.outcome == "VICTORY" and app.progress_session.inspect().state == "ENDED",
		"normal bus evacuation and explicit confirmation durably win the pump finale")
	await _shot("confirmed-victory")
	_write("route.json", {"branch":branch, "starting_camp":start_hash, "final_camp":RecordEncoding.fingerprint(saved),
		"sorties":route, "victory":saved.journey.campaign.outcome, "training":training_effects})


func _fight_pump(world: Expedition) -> void:
	var sequence: int = -1
	for tick: int in range(2700):
		if world.is_paused or world.phase == Expedition.Phase.FINISHED or not world.encounter.defeat.is_empty():
			return
		var charge: Dictionary = world.encounter.pump.state
		if not charge.lane.is_empty() and charge.sequence != sequence:
			sequence = int(charge.sequence)
			var side: Vector2 = (WorldLayout.point(charge.lane.to) - WorldLayout.point(charge.lane.from)).normalized().orthogonal()
			var member: FieldActor = world.survivors[0]
			for sign_value: float in [1.0, -1.0]:
				var safe: Vector2 = member.position + side * 92.0 * sign_value
				if world.navigation.is_clear(safe) and not world.navigation.path_between(member.position, safe).is_empty():
					world.command_move(safe)
					break
		elif tick % 90 == 0 and charge.lane.is_empty():
			var target: Vector2 = world.encounter.actor.position + Vector2(116, 60)
			if world.navigation.is_clear(target):
				world.command_move(target)
		world.step(STEP)
		if tick % 30 == 0:
			_frame_boss(world)
			await _frame()


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(path)))
