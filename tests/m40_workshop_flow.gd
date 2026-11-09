extends "res://tests/campaign_flow.gd"
## Uses the same path-bound isolated camp for the independent tool and magazine comparisons.

const STEP: float = 1.0 / 30.0
var initial: Dictionary = {}
var shot_count: int = 0
var reload_started: float = -1.0
var reload_ended: float = -1.0
var rounds_filled: int = 0

func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._opening_picker.choices["scavenge"])
	await _tap(app._new_game_confirmation.get_ok_button())
	_check(WorkshopV1.enabled(app.camp_snapshot()), "normal journey enables workshop policy")
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.daily_offers.all(func(action: Dictionary) -> bool: return WorkshopSiteV1.site_id(action).is_empty()),
		"unbuilt workshop yields no toolbox cards")
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return action.has("investigation"))
	_check(index >= 0, "ordinary day-two investigation exists")
	if index < 0:
		return
	var world: Expedition = await _start(index)
	if world == null:
		return
	await _search(world, world.search_site(&"cash"))
	await _food(world, 6)
	await _bank(world)

func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	match output.get_file():
		"build":
			await _facility(CampFacilities.WORKSHOP)
		"supply":
			await _facility(CampFacilities.SUPPLY)
		"direct", "tool-first":
			await _tool_route(output.get_file() == "tool-first")
		"tool-resume":
			await _tool_resume(app.expedition)
		"recruit":
			await _recruit()
		"mod-a", "mod-b":
			await _mod_route(WorkshopV1.EXTENDED if output.get_file() == "mod-a" else WorkshopV1.QUICK)
		"mod-resume":
			await _mod_resume(app.expedition)

func _facility(choice: String) -> void:
	var before: Dictionary = app.camp_snapshot()
	await _tap(app.camp_scene.facility_buttons[choice])
	await _tap(app._facility_confirmation.get_ok_button())
	var after: Dictionary = app.camp_snapshot()
	_check(CampFacilities.selected(after) == choice and after.cash == before.cash - 12, "normal facility confirmation charges exactly 12")
	if choice == CampFacilities.SUPPLY:
		_check(WorkshopV1.mod_problem(after, WeaponInventory.for_member(after,1).instance_id, WorkshopV1.EXTENDED) == "需要已建工坊",
			"supply choice gives the explicit workshop prerequisite")
		await _tap(app.camp_scene.hotspots[&"bus"])
		_check(app.mission_select.daily_offers.all(func(action: Dictionary) -> bool: return WorkshopSiteV1.site_id(action).is_empty()),
			"same-day supply camp never offers a toolbox")

func _tool_route(wants_tool: bool) -> void:
	var camp: Dictionary = app.camp_snapshot()
	await _tap(app.camp_scene.hotspots[&"bus"])
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return not WorkshopSiteV1.site_id(action).is_empty())
	_check(index >= 0, "ordinary workshop camp sees a certified toolbox card")
	if index < 0:
		return
	_check("工具箱 ×1" in app.mission_select._descriptions[index].text, "normal mission card shows optional toolbox")
	var world: Expedition = await _start(index)
	if world == null:
		return
	var tool: Expedition.SearchSite = world._toolbox_site()
	_check(tool != null and not tool.weapon and tool.reward > 0 and tool.id != &"cash", "frozen real optional site has original positive reward")
	if tool == null:
		return
	if wants_tool:
		var no_candidate: Dictionary = world.supply.generated.duplicate(true)
		no_candidate.erase("workshop_tool")
		no_candidate.exploration.level.optional.site_id = "missing"
		_check(WorkshopSiteV1.site_id(WorkshopSiteV1.freeze(no_candidate)).is_empty(), "no legal optional point yields no toolbox")
		_check(not WorkshopV1.recovered(world.supply.generated, {"evacuated":false, "site_facts":{String(tool.id):{"searched":true}}}),
			"completed point still yields no toolbox after failed evacuation")
	await _search(world, world.search_site(&"cash"))
	var before_tool: Dictionary = {"action":world.supply.generated.id, "map":world.layout.id, "camp":RecordEncoding.fingerprint(camp),
		"site":String(tool.id), "site_kind":String(tool.kind), "site_reward":tool.reward, "main_at":world.elapsed}
	if not wants_tool:
		var committed: Dictionary = await _bank(world)
		_check(WorkshopV1.tools(app.camp_snapshot()) == 0, "direct return credits no toolbox")
		_write("tool-route.json", {"before":before_tool,"return":reports.back(),"receipt":committed.get("hash",""),"stock":WorkshopV1.tools(app.camp_snapshot())})
		return
	world.locate_objective("toolbox")
	world._update_ui()
	await _shot("optional-toolbox")
	world.request_search(tool.id)
	await _until(world, func() -> bool: return tool.progress > 0.15)
	_check(not tool.searched and WorkshopV1.tools(app.camp_snapshot()) == 0, "unfinished toolbox is not camp stock")
	await _suspend(world, "tool-checkpoint.json", {"before":before_tool,"site":String(tool.id),"progress":tool.progress})

func _tool_resume(world: Expedition) -> void:
	var prior: Dictionary = _checkpoint(world, "tool-first/tool-checkpoint.json")
	if prior.is_empty():
		return
	var tool: Expedition.SearchSite = world._toolbox_site()
	_check(tool != null and String(tool.id) == prior.site and is_equal_approx(tool.progress, float(prior.progress)),
		"tool site and partial work match the diagnostic JSON after exact snapshot recovery")
	if tool == null:
		return
	await _unpause(world)
	await _until(world, func() -> bool: return tool.searched)
	var recovered_at: float = world.elapsed
	_check(WorkshopV1.tools(app.camp_snapshot()) == 0, "carried toolbox cannot be spent in camp before confirmation")
	await _shot("carried-toolbox")
	var committed: Dictionary = await _bank(world)
	_check(WorkshopV1.tools(app.camp_snapshot()) == 1, "true optional completion banks exactly one toolbox")
	_write("tool-route.json", {"before":prior.before,"site_at":recovered_at,"return":reports.back(),
		"receipt":committed.get("hash",""),"stock":WorkshopV1.tools(app.camp_snapshot())})

func _recruit() -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return action.type == "rescue")
	_check(index >= 0, "ordinary rescue offers a second authentic carbine")
	if index < 0:
		return
	var world: Expedition = await _start(index)
	if world == null:
		return
	var target: RescueTarget = world.rescue_target
	_check(target != null, "original rescue site exists")
	if target == null:
		return
	target.request()
	await _until(world, func() -> bool: return target.progress >= RescueTarget.SECONDS)
	if not target.revealed():
		target.request()
	await _until(world, func() -> bool: return target.revealed())
	await _food(world, 7)
	await _bank(world)
	var camp: Dictionary = app.camp_snapshot()
	_check(WorkshopV1.tools(camp) == 1 and camp.weapons.filter(func(item: Dictionary) -> bool:
		return item.weapon_id == "carbine" and item.condition == "ready").size() >= 2,
		"original rescue adds a separate carbine and preserves the toolbox")

func _mod_route(mod: String) -> void:
	var camp: Dictionary = app.camp_snapshot()
	var item: Dictionary = WeaponInventory.for_member(camp, 1)
	var identity: String = item.instance_id
	await _tap(app.camp_scene.hotspots[&"weapons"])
	_select_weapon(identity)
	var panel: LoadoutPanel = app.loadout_panel
	_check(WorkshopV1.tools(camp) == 1 and WorkshopV1.mod_for(camp, identity).is_empty(), "same confirmed camp starts with one tool and original gun")
	await _shot("workshop-options")
	await _tap(panel.workshop_buttons[mod])
	await _tap(panel.workshop_confirmation.get_ok_button())
	var edited: Dictionary = app.camp_snapshot()
	_check(edited.cash == camp.cash - 8 and edited.camp_spending == camp.camp_spending + 8
		and WorkshopV1.tools(edited) == 0 and WorkshopV1.mod_for(edited, identity) == mod
		and TransactionReceipt.same(item, WeaponInventory.find(edited, identity)), "one 8-coin and one-tool edit preserves exact weapon drop and affixes")
	var edit: Dictionary = app.progress_session._transaction.recover()
	_check(edit.error == OK and edit.receipt.phase == "EDIT_COMMITTED", "normal workshop confirmation publishes a camp edit")
	var other: Dictionary = edited.weapons.filter(func(candidate: Dictionary) -> bool:
		return candidate.weapon_id == "carbine" and candidate.condition == "ready" and candidate.instance_id != identity)[0]
	var owner_id: int = WeaponInventory.owner(edited, other.instance_id)
	_select_weapon(identity)
	await _tap(panel.equip_by_id[owner_id])
	var transferred: Dictionary = app.camp_snapshot()
	_check(WeaponInventory.for_member(transferred,owner_id).instance_id == identity
		and WorkshopV1.mod_for(transferred,identity) == mod and WorkshopV1.mod_for(transferred,other.instance_id).is_empty(),
		"transfer takes the modification with the gun and leaves the other carbine stock")
	_select_weapon(identity)
	await _tap(panel.equip_by_id[1])
	await _tap(panel.back_button)
	await _tap(app.camp_scene.hotspots[&"bus"])
	var index: int = app.mission_select.daily_offers.find_custom(func(action: Dictionary) -> bool: return not action.has("rare_policy") and action.type == "airdrop")
	if index < 0:
		index = 0
	var world: Expedition = await _start(index)
	if world == null:
		return
	var actor: FieldActor = world.search_member(1)
	var gun: WeaponMagazine = actor.magazine
	var parameters: Dictionary = WeaponMagazine.parameters("carbine", mod)
	initial = {"camp":RecordEncoding.fingerprint(camp), "action":world.supply.generated.id,"map":String(world.layout.id),
		"instance_id":identity,"mod":mod,"capacity":gun.capacity(),"base_seconds":parameters.seconds,"factor":gun.reload_factor,
		"seconds":gun.seconds(),"edit_hash":edit.get("hash",""),"other":other.instance_id}
	_check(gun.instance_id == identity and gun.capacity() == parameters.capacity and gun.rounds == parameters.capacity
		and world.search_member(owner_id).magazine.capacity() == 12, "next normal sortie freezes selected gun and separate stock carbine")
	_measure_initial(world, actor)
	await _drive(world, func() -> bool: return gun.reloading)
	_check(gun.reloading and shot_count == gun.capacity(), "actual shots empty the first modified magazine")
	if not gun.reloading:
		return
	reload_started = world.elapsed
	if mod == WorkshopV1.QUICK:
		await _drive(world, func() -> bool: return gun.remaining <= gun.seconds() - 0.2)
		var snap: Dictionary = gun.snapshot()
		_check(snap.reloading and snap.rounds == 0 and snap.remaining > 0.0, "safe suspend occurs in the actual reload")
		await _suspend(world, "magazine-checkpoint.json", {"initial":initial, "magazine":snap,
			"shot_count":shot_count,"reload_started":reload_started})
		return
	await _finish_magazine(world, actor)

func _mod_resume(world: Expedition) -> void:
	var proof: Dictionary = _checkpoint(world, "mod-b/magazine-checkpoint.json")
	if proof.is_empty():
		return
	initial = proof.initial
	reload_started = proof.reload_started
	shot_count = proof.shot_count
	var actor: FieldActor = world.search_member(1)
	var gun: WeaponMagazine = actor.magazine
	_check(gun.reloading and gun.rounds == proof.magazine.rounds and gun.instance_id == initial.instance_id
		and gun.modification == initial.mod and is_equal_approx(gun.remaining, float(proof.magazine.remaining)),
		"actual reload remaining, empty rounds and same modified instance recover")
	var saved: Dictionary = SortieSnapshot.capture(world)
	var receipt: Dictionary = app.progress_session._transaction.recover().receipt
	for field: String in ["rounds","remaining"]:
		var forged: Dictionary = saved.duplicate(true)
		var row: Dictionary = SortieSnapshot._member(forged.survivors, 1)
		row.magazine[field] = 99
		_check(SortieSnapshot.problem(forged, receipt) == "MAGAZINE_VALUES", "forged excessive " + field + " rejects")
	await _unpause(world)
	await _finish_magazine(world, actor)

func _measure_initial(world: Expedition, actor: FieldActor) -> void:
	world.combat_feedback.connect(func(event: Dictionary) -> void:
		if event.kind == "shot" and event.member_id == actor.member_id:
			shot_count += 1)

func _drive(world: Expedition, condition: Callable) -> void:
	for tick: int in range(10500):
		if condition.call() or world.is_paused or world.phase == Expedition.Phase.FINISHED:
			return
		if tick % 45 == 0 and not world.enemies.is_empty():
			var enemy: FieldActor = world._nearest_target(world.survivors[0], world.enemies, INF)
			if enemy != null and world.survivors[0].position.distance_to(enemy.position) > 125.0:
				world.command_move(enemy.position)
		world.step(STEP)
		if tick % 20 == 0:
			await _frame()

func _finish_magazine(world: Expedition, actor: FieldActor) -> void:
	var gun: WeaponMagazine = actor.magazine
	await _drive(world, func() -> bool: return not gun.reloading)
	reload_ended = world.elapsed
	# The same step may both fill and fire one chambered round.
	rounds_filled = gun.rounds + int(events.any(func(event: Dictionary) -> bool:
		return event.kind == "shot" and event.member_id == actor.member_id and event.elapsed == reload_ended))
	_check(absf(reload_ended - reload_started - gun.seconds()) <= STEP + 0.0001 and rounds_filled == gun.capacity(),
		"measured reload uses simulation time and fills the frozen capacity")
	await _food(world, 3)
	var committed: Dictionary = await _bank(world)
	_write("magazine-route.json", {"initial":initial,"shots":shot_count if output.get_file() == "mod-resume" else initial.capacity,
		"reload_start":reload_started,"reload_end":reload_ended,"measured":reload_ended - reload_started,
		"refilled":rounds_filled,"return":reports.back(),"receipt":committed.get("hash","")})

func _search(world: Expedition, site: Expedition.SearchSite) -> void:
	world.request_search(site.id)
	await _until(world, func() -> bool: return site.searched)

func _food(world: Expedition, target: int) -> void:
	for site: Expedition.SearchSite in world.sites:
		if app.food + world.food_loot >= target:
			break
		if site.kind == &"food" and not site.searched:
			await _search(world, site)

func _bank(world: Expedition) -> Dictionary:
	await _extract(world)
	_check(not app._pending_settlement.is_empty() and not app._progress_blocked, "actual bus exit prepares original settlement")
	if app._pending_settlement.is_empty():
		return {}
	var token: Dictionary = app.progress_session.token.duplicate(true)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var camp: Dictionary = app.camp_snapshot()
	var committed: Dictionary = app.progress_session._transaction.recover()
	var repeated: Dictionary = app.progress_session._transaction.commit(token)
	_check(committed.error == OK and committed.receipt.phase == "COMMITTED" and repeated.error == OK
		and repeated.hash == committed.hash and TransactionReceipt.same(camp,app.camp_snapshot()), "normal and repeated return confirm one receipt")
	return committed

func _suspend(world: Expedition, filename: String, facts: Dictionary) -> void:
	app.open_pause_menu()
	await _hold(2)
	var snapshot: Dictionary = SortieSnapshot.capture(world)
	_write(filename, facts.merged({"fingerprint":RecordEncoding.fingerprint(snapshot),"pid":OS.get_process_id()}))
	app.suspend_sortie()
	await _hold(3)
	_check(app.expedition == null and app._requires_continue, "normal suspend writes and releases world")

func _checkpoint(world: Expedition, path: String) -> Dictionary:
	var prior: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(path)))
	_check(world != null and prior is Dictionary, "normal Continue restores previous world")
	if world == null or not prior is Dictionary:
		return {}
	world.set_physics_process(false)
	world.set_process(false)
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	_check(prior.pid != OS.get_process_id() and prior.fingerprint == RecordEncoding.fingerprint(SortieSnapshot.capture(world)),
		"separate process restores the exact saved snapshot")
	return prior

func _unpause(world: Expedition) -> void:
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()

func _select_weapon(identity: String) -> void:
	var panel: LoadoutPanel = app.loadout_panel
	for index: int in range(panel.items.item_count):
		if panel.items.get_item_metadata(index) == identity:
			panel.items.select(index)
			panel._select(index)
			return
	_check(false, "instance selection exists")
