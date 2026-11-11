extends "res://tests/m47_run_replay_flow.gd"
## Normal, path-bound campaign sources. Simulation steps are accelerated, never rewards or HP.

var edits: Array[Dictionary] = []
var preworkshop_tool: bool = false
var liquidate_surplus: bool = false
var combat_screens: Dictionary = {}
var desired_passive: String = ""
var desired_power: String = ""
var prefer_compact_funding: bool = false
var management_funding: bool = false
var card_timings: Array[Dictionary] = []
var submission_timings: Array[Dictionary] = []
var feedback_paints: Dictionary = {}
var last_tap_usec: int = 0


func _initialize() -> void:
	super()
	if DisplayServer.get_name() != "headless": RenderingServer.frame_post_draw.connect(_observe_commit_paint)


func _observe_commit_paint() -> void:
	if not is_instance_valid(app) or not is_instance_valid(viewport) or app.get("_camp_commit_busy") != true: return
	var kind: String = String(app.get("_camp_commit_label"))
	if kind.is_empty() or feedback_paints.has(kind): return
	feedback_paints[kind] = {"day":app.day,"first_painted_frame_after_tap_usec":Time.get_ticks_usec()-last_tap_usec,
		"scope":"native_rendered_wait_state; includes input/test frames; excludes screenshot encoding"}
	viewport.get_texture().get_image().save_png(output.path_join("waiting-" + kind + ".png"))
	_write("commit-feedback.json",{"operations":feedback_paints})


func _write(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true))
	file.close()


func _tap(button: BaseButton) -> void:
	last_tap_usec = Time.get_ticks_usec()
	var label: String = ""
	if is_instance_valid(app) and button == app.get_node("Interface/Screen/Result/Continue"):
		label = "return_confirmation"
	if label.is_empty() or FreezeProfile.active:
		await super._tap(button)
		return
	FreezeProfile.enabled = true
	FreezeProfile.start({"operation":label,"day":app.day})
	var began: int = Time.get_ticks_usec()
	await super._tap(button)
	var elapsed_usec: int = Time.get_ticks_usec()-began
	if FreezeProfile.active: FreezeProfile.finish()
	submission_timings.append({"operation":label,"input_and_test_frames_usec":elapsed_usec,"profile":FreezeProfile.latest})
	_write("submission-timings.json",{"samples":submission_timings})


func _journey() -> void:
	if not await _new_trip("scavenge", true):
		return
	_check(EconomyBuildV1.enabled(app.camp_snapshot()), "ordinary title creates explicit M48 economy")
	for index: int in range(2):
		if not await _gather(index == 1):
			return
	for attempt: int in range(8):
		if app.camp_snapshot().weapons.size() >= 3 and preworkshop_tool:
			break
		if not await _gather(false):
			return
	var camp: Dictionary = app.camp_snapshot()
	_check(camp.day >= 4 and EconomyBuildV1.tools(camp) >= 2 and camp.weapons.size() >= 3 and preworkshop_tool,
		"common camp has only genuinely recovered tools, cash, and an idle weapon before construction")
	_write("common.json", {"camp":RecordEncoding.fingerprint(camp), "value":camp, "route":route,"preworkshop_tool":preworkshop_tool})
	await _shot("common-camp")


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var common: Dictionary = _read("setup/common.json")
	start_hash = common.camp
	_check(RecordEncoding.fingerprint(app.camp_snapshot()) == start_hash,
		"route starts at the exact same confirmed common camp and original bound path")
	route.assign(common.route)
	match output.get_file():
		"route-a":
			await _finish_campaign("A-fast")
		"route-b":
			await _workshop_route()
		"route-c":
			await _management_route()
		_:
			_check(false, "recognized M48 phase")
	_write("edits.json", {"edits":edits, "camp":app.camp_snapshot()})


func _open_cards() -> bool:
	var began: int = Time.get_ticks_usec()
	var ready: bool = await super._open_cards()
	var elapsed_usec: int = Time.get_ticks_usec()-began
	card_timings.append({"day":app.day,"ready":ready,"input_through_test_frames_usec":elapsed_usec,
		"candidates":app.mission_select.daily_offers.map(func(action: Dictionary) -> Dictionary:
			return {"id":action.id,"type":action.type,"size":action.layout["size"],"theme":action.layout.topology})})
	_write("cards.json",{"samples":card_timings})
	return ready


func _gather(hardware_first: bool = true, cash_goal: int = -1, need_tools: bool = true) -> bool:
	if liquidate_surplus and cash_goal < 0: cash_goal = 0
	if management_funding and desired_power in app.camp_snapshot().journey.build.powers.owned:
		desired_power = ""
	if management_funding and desired_power.is_empty():
		for identity: String in [SpecialPowers.SPEED, SpecialPowers.FREEZE, SpecialPowers.SUPPRESSION]:
			if identity not in app.camp_snapshot().journey.build.powers.owned:
				desired_power = identity
				break
	if not await _open_cards():
		return false
	var index: int = -1
	if not desired_passive.is_empty():
		index = _find_card(func(action: Dictionary) -> bool: return desired_passive in action.get("build",{}).get("drops",[]))
	if index < 0 and not desired_power.is_empty():
		index = _find_card(func(action: Dictionary) -> bool: return action.get("powers",{}).get("sample","") == desired_power)
	if index < 0 and not need_tools and prefer_compact_funding:
		index = _find_card(func(action: Dictionary) -> bool: return action.type in ["equipment","airdrop"] and not EconomyActions.hardware(action) and not action.get("campaign",{}).get("is_finale",false) and not action.has("investigation") and action.layout["size"] != "large" and not action.has("rare_policy") and not action.has("event_sortie"))
		if index < 0:
			index = _find_card(func(action: Dictionary) -> bool: return action.type == "supply" and not action.has("rare_policy"))
	if index < 0 and hardware_first:
		index = _find_card(func(action: Dictionary) -> bool: return EconomyActions.hardware(action))
	if index < 0 and app.food < 4:
		index = _find_card(func(action: Dictionary) -> bool: return action.type == "supply" and not action.has("rare_policy"))
	if index < 0:
		index = _find_card(func(action: Dictionary) -> bool:
			return not EconomyActions.hardware(action) and not EconomyActions.tool_sources(action).is_empty())
	if index < 0:
		index = _find_card(func(action: Dictionary) -> bool: return action.type == "airdrop" and not EconomyActions.hardware(action))
	if index < 0:
		index = _find_card(func(action: Dictionary) -> bool:
			return not action.get("campaign", {}).get("is_finale", false) and action.get("weapons", 0) > 0 and not action.has("event_sortie"))
	if index < 0:
		index = _find_card(func(action: Dictionary) -> bool: return action.type == "supply")
	var world: Expedition = await _start(index)
	if world == null:
		return false
	await _collect(world, 6)
	for source: Dictionary in (EconomyActions.tool_sources(world.supply.generated) if need_tools or not prefer_compact_funding else []):
		var site: Expedition.SearchSite = world.search_site(StringName(source.site_id))
		if not site.searched:
			await _search(world, site)
	for site: Expedition.SearchSite in ([] if prefer_compact_funding else world.sites):
		if cash_goal >= 0 and int(app.cash) + world.loot >= cash_goal: break
		if site.kind == &"cash" and not site.searched:
			await _search(world,site)
	if not EconomyActions.hardware(world.supply.generated) and not EconomyActions.tool_sources(world.supply.generated).is_empty() and EconomyBuildV1.level(app.camp_snapshot(),"workshop") == 0:
		preworkshop_tool = true
	await _finish_outing(world)
	if liquidate_surplus:
		await _sell_surplus()
	return not app._progress_blocked and app.camp_snapshot().journey.state == "ACTIVE"


func _finish_outing(world: Expedition) -> void:
	FreezeProfile.enabled = true
	var began: int = Time.get_ticks_usec()
	await super._finish_outing(world)
	var camp: Dictionary = app.camp_snapshot()
	_write("return-%02d.json" % route.size(),{"wall_usec":Time.get_ticks_usec()-began,
		"profile":FreezeProfile.latest,"camp":camp,"route":route.back() if not route.is_empty() else {}})
	if EconomyBuildV1.level(camp,"workshop") == 2 and EconomyBuildV1.tools(camp) >= 3 and camp.cash >= 28:
		_write("component-source-camp.json",{"camp":camp,"scope":"NORMAL_RECOVERED_CAMP_READ_ONLY_COMPONENT_BRANCHES"})


func _search(world: Expedition, site: Expedition.SearchSite) -> void:
	# Keep the squad covering its worker through ordinary move and work intentions.
	world.command_move(site.door)
	await _until(world, func() -> bool:
		return world.survivors.all(func(member: FieldActor) -> bool:
			return member.health <= 0 or member.position.distance_to(site.door) < 80.0))
	world.request_search(site.id)
	await _until(world,func() -> bool: return site.searched)


func _until(world: Expedition, done: Callable, limit: int = 12000) -> void:
	for tick: int in range(limit):
		if done.call() or world.phase == Expedition.Phase.FINISHED or world.is_paused: break
		if tick % 30 == 0:
			_maybe_heal(world)
		world.step(STEP)
		if tick % 30 == 0:
			await _frame()
			await _combat_screenshot()
	_check(done.call(),"bounded normal team movement/work reaches checkpoint")
	if not done.call():
		_write("checkpoint-failure-%d.json" % rows.size(),{"elapsed":world.elapsed,"phase":world.phase,"paused":world.is_paused,"camp":app.camp_snapshot()})
		quit(1)
		await process_frame


func _combat_screenshot() -> void:
	if events.is_empty(): return
	for event: Dictionary in events.slice(maxi(0,events.size()-20)):
		var label: String = ""
		if event.get("kind") == "shot" and not event.get("secondary",{}).is_empty(): label = "actual-pierce"
		if event.get("kind") == "shotgun" and event.get("rounds_refunded",0) > 0: label = "actual-refund"
		if not label.is_empty() and not combat_screens.has(label):
			combat_screens[label] = true
			await _shot(label)


func _maybe_heal(world: Expedition) -> void:
	if not world.build_mode() or not world.basic_support.ready("heal"): return
	var strong: bool = BuildItems.frozen_factors(world.supply.generated.build).heal > 1.5
	if world.survivors.any(func(member: FieldActor) -> bool:
		return member.health > 0 and member.max_health - member.health > (64.0 if strong and member.max_health >= 150.0 else 40.0)):
		world.request_heal()


func _economy(op: String, target_id: String = "", choice: String = "", fault: String = "") -> bool:
	var before: Dictionary = app.camp_snapshot()
	var offer: Dictionary = EconomyBuildV1.offer(before, op, target_id, choice)
	if not offer.available:
		_check(false, "%s available: %s" % [op, offer.reason])
		return false
	var identity: String = String(before.profile_id) + ":edit:" + RunSave.new_profile_id()
	var request: Dictionary = EconomyBuildV1.request(before, op, target_id, choice, identity)
	if not fault.is_empty():
		if not _edit(request, fault): return false
	else:
		if not await _ui_economy(op, target_id, choice): return false
	request = app.progress_session._transaction.recover().receipt.rules.request
	edits.append({"request":request, "before":RecordEncoding.fingerprint(before), "cash_before":before.cash,
		"tools_before":EconomyBuildV1.tools(before), "cash_after":app.cash,
		"tools_after":EconomyBuildV1.tools(app.camp_snapshot()),
		"receipt":app.progress_session._transaction.recover().get("hash", "")})
	return true


func _ui_economy(op: String, target_id: String, choice: String) -> bool:
	var before: Dictionary = app.camp_snapshot()
	if op in ["build", "upgrade_facility"]:
		app.open_supplies()
		await _tap(app.supply_panel.build_buttons[target_id] if op == "build" else app.supply_panel.upgrade_buttons[target_id])
		await _shot("preview-%02d-%s" % [edits.size(), op])
		await _tap(app._facility_confirmation.get_ok_button())
		await _tap(app.supply_panel.back_button)
	else:
		app.open_loadout(op != "sell")
		var armory: CampArmoryView = app.loadout_panel.armory
		if op == "craft":
			await _tap(armory.craft_buttons[target_id])
		else:
			if op == "sell": armory.select_inventory(target_id)
			else: armory.show_workshop(target_id)
			await _hold(2)
			await _tap(armory.economy_buttons[op + ":" + choice])
		await _shot("preview-%02d-%s" % [edits.size(), op])
		await _tap(armory.confirmation.get_ok_button())
		await _tap(app.loadout_panel.back_button)
	var after: Dictionary = app.camp_snapshot()
	var changed: bool = not TransactionReceipt.same(before, after) and not app._progress_dirty and not app._progress_blocked
	_check(changed, "normal visible preview and confirmation commits " + op)
	return changed


func _fund(op: String, target_id: String = "", choice: String = "") -> bool:
	for attempt: int in range(18):
		var quote: Dictionary = EconomyBuildV1.offer(app.camp_snapshot(), op, target_id, choice)
		if quote.available:
			return true
		if not await _gather(true,int(quote.cost) if liquidate_surplus else -1,int(quote.tools) > EconomyBuildV1.tools(app.camp_snapshot())):
			return false
	_check(false, "normal economy can fund " + op)
	return false


func _sell_idle() -> void:
	for item: Dictionary in app.camp_snapshot().weapons:
		if WeaponInventory.owner(app.camp_snapshot(), item.instance_id) == 0:
			if await _economy("sell", item.instance_id):
				return
	_check(false, "an unassigned recovered weapon is sold exactly once")


func _sell_surplus() -> void:
	var inventory: Array = app.camp_snapshot().weapons.duplicate(true)
	for item: Dictionary in inventory:
		if item.condition == "ready" and not item.acquired_sortie.is_empty() and not EconomyBuildV1.crafted(item) and WeaponInventory.owner(app.camp_snapshot(),item.instance_id) == 0:
			await _economy("sell",item.instance_id)


func _craft_gun(gun: String) -> String:
	var existing: Array = app.camp_snapshot().weapons.map(func(item: Dictionary) -> String: return String(item.instance_id))
	if not await _fund("craft", gun) or not await _economy("craft", gun):
		return ""
	var created: Array = app.camp_snapshot().weapons.filter(func(item: Dictionary) -> bool:
		return EconomyBuildV1.crafted(item) and item.weapon_id == gun and item.instance_id not in existing)
	_check(created.size() == 1, "crafted unique ready instance exists")
	return "" if created.is_empty() else String(created.back().instance_id)


func _workshop_route() -> void:
	liquidate_surplus = true
	await _sell_idle()
	if not await _economy("build", "workshop", "", "before_camp_write"):
		return
	var gun: String = await _craft_gun("carbine")
	if gun.is_empty():
		return
	if await _fund("combat_component", gun, WeaponModifiers.PIERCE):
		await _economy("combat_component", gun, WeaponModifiers.PIERCE)
	await _equip_weapon_ui(gun)
	for level: int in range(2, 6):
		if level == 4:
			if await _fund("upgrade_facility", "workshop"):
				await _economy("upgrade_facility", "workshop")
		if not await _fund("upgrade_weapon", gun) or not await _economy("upgrade_weapon", gun):
			return
	if not await _build_invest("next_slot"):
		return
	_write("level-five.json", {"instance":WeaponInventory.find(app.camp_snapshot(), gun), "camp":app.camp_snapshot()})
	var level_five_start: int = events.size()
	await _finish_campaign("B-workshop")
	var level_five_events: Array = events.slice(level_five_start)
	_check(level_five_events.any(func(event: Dictionary) -> bool:
		return event.get("kind") == "shot" and event.get("instance_id") == gun and float(event.get("applied_damage", 0)) > 0),
		"five-level crafted weapon actually fires and deals damage")
	_check(events.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("instance_id") == gun and float(event.get("secondary",{}).get("applied_damage",0)) > 0),"crafted pierce actually damages a second legal target on the normal campaign")
	_write("level-five-combat.json", {"events":level_five_events,"instance":WeaponInventory.find(app.camp_snapshot(),gun)})


func _management_route() -> void:
	liquidate_surplus = true
	management_funding = true
	for facility: String in ["supply", "workshop", "planning"]:
		if not await _fund("build", facility) or not await _economy("build", facility):
			return
	if not await _fund("upgrade_facility", "workshop") or not await _economy("upgrade_facility", "workshop"):
		return
	var gun: String = await _craft_gun("shotgun_v1")
	if gun.is_empty():
		return
	if await _fund("combat_component", gun, WeaponModifiers.REFUND):
		await _economy("combat_component", gun, WeaponModifiers.REFUND)
	await _equip_weapon_ui(gun)
	if not await _build_invest("medical_pack_v1"):
		return
	await _equip_passive_ui(1,"medical_pack_v1")
	var long_gun: String = await _craft_gun("long_rifle")
	if long_gun.is_empty(): return
	await _equip_weapon_ui(long_gun,2)
	for purchase: String in [PowerState.SECOND_SLOT,PowerState.THIRD_SLOT]:
		if not await _power_invest(purchase): return
	if "--flow-all-slots" in OS.get_cmdline_user_args():
		for count: int in range(2):
			if not await _build_invest("next_slot"): return
		for item_id: String in ["pressure_rounds_v1","quick_loader_v1"]:
			for attempt: int in range(12):
				if item_id in app.camp_snapshot().journey.build.owned: break
				desired_passive = item_id
				if not await _gather(): return
			desired_passive = ""
		await _equip_passive_ui(2,"pressure_rounds_v1")
		await _equip_passive_ui(3,"quick_loader_v1")
	for attempt: int in range(12):
		if [SpecialPowers.SPEED,SpecialPowers.FREEZE,SpecialPowers.SUPPRESSION].all(func(identity: String) -> bool: return identity in app.camp_snapshot().journey.build.powers.owned): break
		for identity: String in [SpecialPowers.SPEED,SpecialPowers.FREEZE,SpecialPowers.SUPPRESSION]:
			if identity not in app.camp_snapshot().journey.build.powers.owned:
				desired_power = identity
				break
		if not await _gather(): return
	desired_power = ""
	management_funding = false
	await _equip_power_ui(0,SpecialPowers.SPEED)
	await _equip_power_ui(1,SpecialPowers.FREEZE)
	await _equip_power_ui(2,SpecialPowers.SUPPRESSION)
	await _gather()
	_check(events.any(func(event: Dictionary) -> bool: return event.get("kind") == "shotgun" and event.get("instance_id") == gun and not event.get("targets",[]).is_empty()),"normal crafted shotgun actually hits legal targets")
	_check(events.any(func(event: Dictionary) -> bool: return event.get("kind") == "shot" and event.get("instance_id") == long_gun and float(event.get("applied_damage",0)) > 0),"normal crafted long rifle actually damages legal targets")
	_check(events.any(func(event: Dictionary) -> bool: return event.get("kind") == "shotgun" and event.get("instance_id") == gun and event.get("rounds_refunded",0) == 1),"normal crafted shotgun really earns its unique per-trigger refund")
	_write("management-combat.json",{"shotgun":gun,"long_rifle":long_gun,"events":events,"route":route})
	await _shot("three-facilities")
	app.open_supplies()
	await _hold(2)
	await _shot("facility-ledger")
	await _tap(app.supply_panel.back_button)
	app.open_loadout()
	await _tap(app.loadout_panel.armory._nav[&"support"])
	app.loadout_panel.armory._support.scroll_vertical = 0
	await _hold(2)
	await _shot("four-passives-configuration" if app.camp_snapshot().journey.build.slots.size() == 4 else "passive-configuration")
	app.loadout_panel.armory._support.scroll_vertical = 100000
	await _hold(2)
	await _shot("three-powers-configuration")
	await _tap(app.loadout_panel.back_button)
	if "--flow-suspend-build" in OS.get_cmdline_user_args():
		await _build_checkpoint()
		return
	await _finish_campaign("C-management")
	var healing: Array[Dictionary] = []
	for report: Dictionary in reports:
		for event: Dictionary in report.get("support", {}).get("accepted", []):
			if event.kind == "heal": healing.append(event)
	_check(not healing.is_empty(), "enhanced support is actually accepted on the management campaign")
	_write("management-effects.json", {"healing":healing,"economy":app.camp_snapshot().journey.campaign.economy})


func _management_healing() -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	for report: Dictionary in reports:
		for event: Dictionary in report.get("support",{}).get("accepted",[]):
			if event.kind == "heal": accepted.append(event)
	return accepted


func _power_invest(choice: String) -> bool:
	for attempt: int in range(20):
		if PowerState.investment_problem(app.camp_snapshot(),choice).is_empty(): break
		if not await _gather(true,PowerState.investment_cost(app.camp_snapshot(),choice),false): return false
	var before: Dictionary = app.camp_snapshot()
	if not PowerState.investment_problem(before,choice).is_empty():
		_check(false,"normal sources can fund " + choice)
		return false
	app.open_loadout()
	await _tap(app.loadout_panel.armory._nav[&"support"])
	await _tap(app.loadout_panel.power_panel.purchases[choice])
	await _shot("power-investment-" + choice)
	await _tap(app.loadout_panel.power_panel.confirmation.get_ok_button())
	await _tap(app.loadout_panel.back_button)
	return app.cash == int(before.cash) - PowerState.investment_cost(before,choice)


func _equip_power_ui(slot: int, identity: String) -> void:
	app.open_loadout()
	await _tap(app.loadout_panel.armory._nav[&"support"])
	var panel: PowerLoadoutPanel = app.loadout_panel.power_panel
	var lists: Array = [panel.choices,panel.second_choices,panel.third_choices]
	await _tap(lists[slot][identity])
	_check(app.camp_snapshot().journey.build.powers.slots[slot] == identity,"normal power choice commits independent slot")
	await _tap(app.loadout_panel.back_button)


func _build_checkpoint() -> void:
	var world: Expedition = await _ordinary_supply()
	if world == null: return
	await _collect(world,4)
	var actor: FieldActor = world.search_member(2)
	if actor == null or actor.health <= 0:
		for member: FieldActor in world.survivors:
			if member.health > 0: actor = member; break
	if actor == null: return
	await _drive(world,func() -> bool: return actor.magazine.reloading)
	_check(actor.magazine.reloading,"normal long-rifle shots enter real reload before representative checkpoint")
	if not actor.magazine.reloading: return
	world.step(0.1)
	await _tap(world.power_panel.activation_button)
	await _tap(world.second_power_panel.activation_button)
	await _tap(world.third_power_panel.activation_button)
	await _shot("three-powers-partial-reload")
	var magazines: Array[Dictionary] = []
	for member: FieldActor in world.survivors:
		if member.magazine != null:
			magazines.append({"member_id":member.member_id,"hash":RecordEncoding.fingerprint(member.magazine.snapshot())})
	var remaining: Array[float] = []
	for slot: int in range(3): remaining.append(SpecialPowers.remaining(world.powers,world.elapsed,slot))
	await _suspend(world,"checkpoint.json",{"camp":RecordEncoding.fingerprint(app.camp_snapshot()),
		"starting_camp":start_hash,"powers":RecordEncoding.fingerprint(world.powers),"elapsed":world.elapsed,"world_clock_record":RecordEncoding.stringify({"elapsed":world.elapsed}),
		"previous_healing":_management_healing(),"magazines":magazines,"power_remaining":remaining,"power_remaining_record":RecordEncoding.stringify({"values":remaining}),"route":route,"edits":edits})


func _build_invest(choice: String) -> bool:
	if choice != "next_slot" and choice not in app.camp_snapshot().journey.build.owned: desired_passive = choice
	for attempt: int in range(20):
		if BuildState.investment_offer(app.camp_snapshot(),choice).available:
			break
		if not await _gather(true,int(BuildState.investment_offer(app.camp_snapshot(),choice).cost) if liquidate_surplus else -1,false): return false
	desired_passive = ""
	var before: Dictionary = app.camp_snapshot()
	var offer: Dictionary = BuildState.investment_offer(before,choice)
	_check(offer.available, "normal sources can fund passive investment " + choice)
	if not offer.available: return false
	app.open_loadout()
	var armory: CampArmoryView = app.loadout_panel.armory
	await _tap(armory._nav[&"support"])
	var panel: BuildItemsPanel = armory.build_panel
	if choice == "next_slot":
		await _tap(panel._slot_button)
	else:
		var index: int = panel._index_for(panel._upgrade_choice,choice)
		panel._upgrade_choice.select(index)
		panel._refresh_upgrade()
		await _tap(panel._upgrade_button)
	await _shot("passive-investment-" + choice)
	await _tap(panel._confirmation.get_ok_button())
	await _tap(app.loadout_panel.back_button)
	_check(app.cash == int(before.cash) - int(offer.cost), "visible passive confirmation commits one debit")
	return app.cash == int(before.cash) - int(offer.cost)


func _equip_weapon_ui(identity: String, member_id: int = 1) -> void:
	app.open_loadout()
	var armory: CampArmoryView = app.loadout_panel.armory
	armory.select_inventory(identity,member_id)
	await _tap(armory.confirm_equip)
	_check(WeaponInventory.for_member(app.camp_snapshot(),member_id).instance_id == identity,
		"normal equipment confirmation assigns the exact crafted instance")
	await _tap(app.loadout_panel.back_button)


func _equip_passive_ui(slot: int, identity: String) -> void:
	app.open_loadout()
	var armory: CampArmoryView = app.loadout_panel.armory
	await _tap(armory._nav[&"support"])
	var panel: BuildItemsPanel = armory.build_panel
	var index: int = panel._index_for(panel.slot_choices[slot],identity)
	panel.slot_choices[slot].select(index)
	panel.slot_choices[slot].item_selected.emit(index)
	await _hold(3)
	_check(app.camp_snapshot().journey.build.slots[slot] == identity,"normal passive selector saves " + identity)
	await _tap(app.loadout_panel.back_button)


func _fight_pump(world: Expedition) -> void:
	var sequence: int = -1
	for tick: int in range(2700):
		if world.is_paused or world.phase == Expedition.Phase.FINISHED or not world.encounter.defeat.is_empty(): return
		if tick % 15 == 0 and world.basic_support.ready("heal"):
			_maybe_heal(world)
		var charge: Dictionary = world.encounter.pump.state
		if not charge.lane.is_empty() and charge.sequence != sequence:
			sequence = int(charge.sequence)
			var side: Vector2 = (WorldLayout.point(charge.lane.to) - WorldLayout.point(charge.lane.from)).normalized().orthogonal()
			for sign_value: float in [1.0,-1.0]:
				var safe: Vector2 = world.survivors[0].position + side * 92.0 * sign_value
				if world.navigation.is_clear(safe) and not world.navigation.path_between(world.survivors[0].position,safe).is_empty():
					world.command_move(safe)
					break
		elif tick % 90 == 0 and charge.lane.is_empty():
			var target: Vector2 = world.encounter.actor.position + Vector2(116,60)
			if world.navigation.is_clear(target): world.command_move(target)
		world.step(STEP)
		if tick % 30 == 0:
			_frame_boss(world)
			await _frame()
