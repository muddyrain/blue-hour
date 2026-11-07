extends "res://tests/investigation_flow.gd"
## Two ordinary two-sortie routes and an outdoor-work resume through the original controls.

var route: Dictionary = {}


func _journey() -> void:
	await _tap(app._home_button)
	await _tap(app._new_game_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	_check(CampaignRules.is_mission(camp.journey.campaign) and camp.day == 2 and camp.settled_sorties == 0,
		"normal title starts the explicit new mission policy")
	await _menu(0)
	var cards: Array[Dictionary] = app.mission_select.daily_offers
	if cards.size() != 3:
		return
	route = {"seed":camp.journey.seed, "start":{"food":camp.food, "cash":camp.cash,
		"crew":camp.crew, "weapons":camp.weapons}, "cards":[]}
	for index: int in range(cards.size()):
		var text: String = app.mission_select._descriptions[index].text
		route.cards.append({"id":cards[index].id, "type":cards[index].type, "title":app.mission_select._titles[index].text,
			"description":text, "sites":cards[index].sites, "level":cards[index].exploration.level})
		_check(text.contains("主收益") and text.contains("路线") and text.contains("风险")
			and text.find("主收益") < text.find("路线") and text.find("路线") < text.find("风险"),
			"card compares signed reward, route and risk in the same order")
		_check(viewport.get_visible_rect().encloses(app.mission_select.choices[index].get_global_rect()),
			"original departure button fits the viewport")
	_check(cards[0].type == "supply" and cards[1].type == "airdrop" and cards[2].has("investigation"),
		"same first decision offers supply, outdoor gear and investigation")
	await _shot("first-cards")
	if "--mission-suspend" in OS.get_cmdline_user_args():
		await _suspend_gear()
		return
	if "--mission-gear" in OS.get_cmdline_user_args():
		await _gear_route()
	else:
		await _supply_route()
	route["end"] = app.camp_snapshot()
	_write("route.json", route)


func _supply_route() -> void:
	var world: Expedition = await _start(0)
	if world == null:
		return
	var goals: Array = world.supply.generated.objective.site_ids
	var first: Expedition.SearchSite = world.search_site(StringName(goals[0]))
	var extra: Expedition.SearchSite = world.search_site(StringName(goals[1]))
	_check(first.reward >= 2 and extra.reward > 0, "one real food site can fund both next rations")
	await _click_site(world, first)
	await _until(world, func() -> bool: return first.progress >= 8.0)
	await _click_site(world, extra)
	await _until(world, func() -> bool: return extra.progress > 0.0)
	var first_worker: int = world.search_assignments.member_for(String(first.id))
	var extra_worker: int = world.search_assignments.member_for(String(extra.id))
	_check(first_worker > 0 and extra_worker > 0 and first_worker != extra_worker,
		"real nearby entrances support two independently assigned workers")
	await _shot("supply-split")
	await _until(world, func() -> bool: return first.searched)
	_check(not extra.searched and world.food_loot == first.reward, "first food site meets ration before the second finishes")
	await _click_site(world, extra)
	_check(not world.has_search_job(extra_worker) and not extra.searched, "cancel the extra reserve search and take the shorter return")
	var cancelled_progress: float = extra.progress
	await _return_to_bus(world)
	var report: Dictionary = reports.back()
	_check(report.food == first.reward and not report.site_facts[String(extra.id)].searched and report.weapons.is_empty(),
		"early return only reports the completed food site")
	var after: Dictionary = app._pending_settlement
	_check(after.last_day.food_stored == first.reward and after.last_day.task.completed == 1 and after.last_day.task.status == "EARLY",
		"early settlement banks the actual food and credits only one main site")
	await _shot("supply-closeout")
	await _confirm(0)
	_check(app.food >= 2 and app.settled_sorties == 1, "food gained makes a second sortie without another supply trip feasible")
	route.first = {"choice":"supply", "food":report.food, "bank":app.food, "cancelled_progress":cancelled_progress,
		"first_worker":first_worker, "extra_worker":extra_worker, "report":report}
	await _menu(0)
	var field: Expedition = await _start(_investigation_card())
	if field == null:
		return
	await _search_clue(field, 0)
	var elapsed: float = field.elapsed
	var threat: Dictionary = field.threat_status()
	var return_path: float = float(field.supply.generated.exploration.level.routes["cash>bus"].length)
	_check(field.weapon_loot.is_empty() and _clue_ids(app.camp_snapshot()).is_empty(),
		"deep main site carries a clue without a guaranteed weapon or immediate camp credit")
	_check(return_path > 1000.0 and threat.active_enemies > 0,
		"live enemies and a real deep return path justify leaving optional loot")
	await _return_to_bus(field)
	var investigation: Dictionary = reports.back()
	var return_threat: Dictionary = field.threat_status()
	_check(investigation.evacuated and investigation.sites_searched == 1 and investigation.weapons.is_empty()
		and app._pending_settlement.last_day.task.status == "COMPLETED", "leave optional loot and evacuate with the actual clue")
	await _shot("clue-closeout")
	await _confirm(1, true)
	await _shot("clue-committed")
	route.second = {"choice":"investigation", "site_completed_at":elapsed, "threat":threat,
		"return_path":return_path, "return_threat":return_threat, "report":investigation}


func _gear_route() -> void:
	var world: Expedition = await _start(1)
	if world == null:
		return
	var roles: Dictionary = await _outdoor_roles(world)
	if roles.is_empty():
		return
	await _finish_gear(world)
	var first: Dictionary = reports.back()
	if first.weapons.is_empty():
		return
	var item: Dictionary = first.weapons[0]
	var old: Dictionary = WeaponInventory.for_member(app.camp_snapshot(), 1)
	var ready: Dictionary = await _repair_and_equip(item.instance_id)
	if ready.is_empty():
		return
	_check(app.food == 0 and app.settled_sorties == 1, "taking gear without food leaves the next ration to supply")
	route.first = {"choice":"airdrop", "roles":roles, "new":ready, "old":old, "bank":app.food, "report":first}
	await _menu(0)
	var supply: Expedition = await _start(0)
	if supply == null:
		return
	var armed: FieldActor = supply.search_member(1)
	var before: WeaponDefinition = WeaponModifiers.combat_definition(old)
	_check(armed.weapon_instance_id == ready.instance_id and (armed.weapon_definition.id != before.id
		or not is_equal_approx(armed.weapon_definition.damage, before.damage) or not is_equal_approx(armed.weapon_definition.shot_range, before.shot_range)),
		"second sortie loads the new instance with a different effective combat profile")
	var site: Expedition.SearchSite = supply.search_site(&"food")
	await _click_site(supply, site)
	await _until(supply, func() -> bool: return site.searched)
	# Approach an actual enemy along its legal route if it stayed outside the harvest fight.
	if _weapon_event(ready).is_empty():
		var target: FieldActor = _nearest_enemy(supply, armed)
		if target != null:
			supply.command_move(target.position)
			await _until(supply, func() -> bool: return not _weapon_event(ready).is_empty(), 1800)
	var impact: Dictionary = _weapon_event(ready)
	_check(not impact.is_empty(), "the re-equipped member uses the recovered weapon in actual second-sortie combat")
	var damage: float = armed.weapon_definition.damage
	var shot_range: float = armed.weapon_definition.shot_range
	await _shot("gear-next-combat")
	await _return_to_bus(supply)
	await _confirm(0)
	route.second = {"choice":"supply", "damage":damage, "range":shot_range,
		"old_damage":before.damage, "old_range":before.shot_range, "combat":impact, "report":reports.back()}


func _outdoor_roles(world: Expedition) -> Dictionary:
	var site: Expedition.SearchSite = world.search_site(&"cash")
	_check(site != null and site.weapon and TaskActions.outdoor_site(world.supply.generated, &"cash"),
		"equipment is the original vulnerable outdoor work site with a real weapon")
	if site == null:
		return {}
	var path: PackedVector2Array = world.navigation.path_between(site.door, world.layout.bus_door)
	var guard_point: Vector2 = _point_on_path(path, 200.0)
	world.command_move(guard_point)
	await _until(world, func() -> bool:
		return world.survivors.all(func(actor: FieldActor) -> bool: return actor.position.distance_to(guard_point) < 90.0))
	await _click_site(world, site)
	var worker: int = world.search_assignments.member_for("cash")
	if worker == 0:
		return {}
	await _until(world, func() -> bool: return site.progress > 0.0)
	var guard: int = 2 if worker == 1 else 1
	var watch: FieldActor = world.search_member(guard)
	await _until(world, func() -> bool: return site.progress >= 3.0)
	var watch_distance: float = watch.position.distance_to(guard_point)
	_check(world.search_assignments.member_for("cash") == worker and world.search_member(worker).visible
		and not world.has_search_job(guard) and watch_distance < 90.0,
		"one visible worker keeps recovering while the other guards the return path")
	_check(world.task_event.started and world.task_event.resolutions.size() == 2
		and world.task_event.resolutions.any(func(row: Dictionary) -> bool: return row.reason == "spawned"),
		"first real outdoor work triggers the original one-time reinforcement event")
	await _shot("gear-worker-and-guard")
	return {"worker":worker, "guard":guard, "progress":site.progress,
		"guard_distance_to_route":watch_distance, "event":world.task_event.duplicate(true)}


func _point_on_path(path: PackedVector2Array, distance: float) -> Vector2:
	for index: int in range(1, path.size()):
		var segment: float = path[index - 1].distance_to(path[index])
		if segment >= distance:
			return path[index - 1].move_toward(path[index], distance)
		distance -= segment
	return path[-1]


func _finish_gear(world: Expedition) -> void:
	var site: Expedition.SearchSite = world.search_site(&"cash")
	var event: Dictionary = world.task_event.duplicate(true)
	await _until(world, func() -> bool: return site.searched)
	_check(world.weapon_loot.size() == 1 and TransactionReceipt.same(event, world.task_event),
		"outdoor completion carries one real weapon and never re-triggers reinforcements")
	await _return_to_bus(world)
	_check(reports.back().weapons.size() == 1 and reports.back().food == 0,
		"equipment-only return brings the actual weapon and no unsought food")
	await _confirm(0)


func _repair_and_equip(identity: String) -> Dictionary:
	var item: Dictionary = WeaponInventory.find(app.camp_snapshot(), identity)
	_check(not item.is_empty() and item.condition == "damaged", "confirmed equipment is a single repairable inventory instance")
	if item.is_empty():
		return {}
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var panel: LoadoutPanel = app.loadout_panel
	for index: int in range(panel.items.item_count):
		if panel.items.get_item_metadata(index) == identity:
			panel.items.select(index)
			panel._select(index)
			break
	await _tap(panel.repair_button)
	await _tap(panel.confirmation.get_ok_button())
	await _tap(panel.equip_by_id[1])
	var equipped: Dictionary = WeaponInventory.for_member(app.camp_snapshot(), 1)
	_check(equipped.instance_id == identity and equipped.condition == "ready", "real camp controls repair and equip the returned instance")
	await _shot("gear-equipped")
	await _tap(panel.back_button)
	return equipped


func _suspend_gear() -> void:
	var world: Expedition = await _start(1)
	if world == null:
		return
	if (await _outdoor_roles(world)).is_empty():
		return
	app.open_pause_menu()
	await _hold(2)
	var snapshot: Dictionary = SortieSnapshot.capture(world)
	_write("checkpoint.json", {"hash":RecordEncoding.fingerprint(snapshot), "pid":OS.get_process_id()})
	app.suspend_sortie()
	await _hold(3)
	_check(app.progress_session.inspect().receipt.phase == "SUSPEND_READY", "partial outdoor work and event reach durable suspension")


func _resume() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("first/checkpoint.json")))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_check(world != null, "normal Continue restores the M19 outdoor action")
	if world == null:
		return
	world.set_physics_process(false)
	world.set_process(false)
	var site: Expedition.SearchSite = world.search_site(&"cash")
	_check(OS.get_process_id() != int(expected.pid) and RecordEncoding.fingerprint(SortieSnapshot.capture(world)) == expected.hash
		and world.task_event.started and site.progress > 0.0 and not site.searched,
		"new process restores the exact action, partial progress and one-time event")
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	if app.pause_menu.visible:
		await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()
	await _finish_gear(world)
	_check(app.settled_sorties == 1 and reports.back().weapons.size() == 1, "resumed action returns its one weapon normally")


func _menu(_count: int) -> void:
	await _tap(app.camp_scene.hotspots[&"bus"])
	_check(app.mission_select.visible and app.mission_select.daily_offers.size() == 3, "ordinary bus opens three actual cards")


func _click_site(world: Expedition, site: Expedition.SearchSite) -> void:
	world.camera.pan_by(site.door - world.camera.position)
	world.camera.force_update_scroll()
	await _hold(2)
	var point: Vector2 = world.get_global_transform_with_canvas() * site.door
	_check(viewport.get_visible_rect().has_point(point), "real target door is visible for the map click")
	for down: bool in [true, false]:
		var mouse: InputEventMouseButton = InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		mouse.position = point
		mouse.global_position = point
		mouse.pressed = down
		viewport.push_input(mouse, true)
		await _frame()


func _weapon_event(item: Dictionary) -> Dictionary:
	for event: Dictionary in events:
		if event.get("member_id") != 1:
			continue
		if event.get("instance_id") == item.instance_id or (item.weapon_id == "shotgun_v1" and event.kind == "shotgun" and not event.targets.is_empty()) \
			or (item.weapon_id == "fire_axe_v1" and event.kind == "axe_swing" and not event.targets.is_empty()):
			return event
	return {}


func _nearest_enemy(world: Expedition, actor: FieldActor) -> FieldActor:
	var nearest: FieldActor
	var distance: float = INF
	for enemy: FieldActor in world.enemies:
		var current: float = actor.position.distance_squared_to(enemy.position)
		if enemy.health > 0.0 and current < distance and not world.navigation.path_between(actor.position, enemy.position).is_empty():
			nearest = enemy
			distance = current
	return nearest
