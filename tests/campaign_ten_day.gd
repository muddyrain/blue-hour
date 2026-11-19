extends SceneTree
## Continuous App campaign, never a constructed late-day fixture.
## Run with tools/check_ten_day.py. State crosses real engine processes on disk.
## Seed injection overrides only AppMain's existing initial-state constructor.

const SEED: String = "blue-hour-ten-day-20261116"
const STEP: float = 1.0 / 30.0
class SeededApp extends AppMain:
	func _pool_initial() -> Dictionary:
		return EnemyState.initial("blue-hour-ten-day-20261116")

var app: AppMain
var output: String
var mode: String
var checks: int = 0
var failures: int = 0
var started: int
var log_file: FileAccess

func _initialize() -> void:
	started = Time.get_ticks_msec()
	_run.call_deferred()

func _ok(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("BH_TEN_DAY_FAIL " + label)
	_event("assert", {"label":label, "pass":value})
	return value

func _event(kind: String, data: Dictionary = {}) -> void:
	var row: Dictionary = data.duplicate(true)
	row.event = kind
	row.process = mode
	row.wall_ms = Time.get_ticks_msec() - started
	var line: String = JSON.stringify(row)
	if log_file != null:
		log_file.store_line(line)
		log_file.flush()
	if kind != "assert":
		print("BH_TEN_DAY " + line)

func _wait(done: Callable, label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if done.call(): return _ok(true, label)
		await process_frame
	return _ok(false, label)

func _advance(world: Expedition, done: Callable, label: String, cap: int = 9000) -> bool:
	for tick: int in range(cap):
		if done.call(): return _ok(true, label)
		if world.is_paused or (world.phase == Expedition.Phase.FINISHED and not world.bus_view.running()): break
		world.step(STEP)
		if tick % 30 == 0: await process_frame
	if not done.call():
		_event("stopped", {"label":label, "day":world.day, "elapsed":world.elapsed,
			"phase":world.phase, "paused":world.is_paused, "living":world.living_count(), "notice":world._notice_text})
	return _ok(done.call(), label)

func _run() -> void:
	mode = OS.get_environment("BH_TEN_DAY_MODE")
	output = OS.get_environment("BH_TEN_DAY_OUTPUT").simplify_path()
	var local: String = ProjectSettings.globalize_path("res://.local/")
	if not output.begins_with(local) or mode not in ["new", "resume", "verify", "hunger", "hunger-partial", "hunger-retry", "hunger-reload"]:
		printerr("BH_TEN_DAY_ARGUMENTS isolated output and explicit process mode required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	log_file = FileAccess.open(output.path_join(mode + ".jsonl"), FileAccess.WRITE)
	_event("start", {"seed_input":SEED, "seed_stored":SEED.md5_text(), "pid":OS.get_process_id(), "renderer":DisplayServer.get_name()})
	var entry: Dictionary = PlayableEntry.resolve(OS.get_cmdline_user_args())
	if not _ok(entry.progress.begins_with(local) and OS.get_user_data_dir().begins_with(local), "all persistence is project-local"):
		_finish()
		return
	app = load("res://src/app/main.tscn").instantiate() as AppMain
	app.set_script(SeededApp)
	root.add_child(app)
	if not await _wait(func() -> bool: return app.is_node_ready() and not app._startup_pending, "formal main startup completes"):
		_finish()
		return
	if mode in ["new", "hunger", "hunger-partial", "hunger-retry"]:
		if not _ok(not FileAccess.file_exists(entry.progress) and not app._requires_continue, "fresh formal entry without a save"):
			_finish()
			return
		app._enter_camp()
		app._opening_picker._select("scavenge")
		app._new_game_confirmation.hide()
		app._confirm_new_journey()
		var initial: Dictionary = app.camp_snapshot()
		if not _ok(initial.day == 2 and initial.food == 4 and initial.cash == 53 and initial.crew.size() == 2
			and initial.crew[0].definition_id == "crew_1" and initial.crew[0].call_sign == "顾予安"
			and initial.crew[1].definition_id == "crew_2" and initial.crew[1].call_sign == "夏之遥"
			and initial.crew[0].growth.level == 1 and initial.crew[1].growth.level == 1
			and initial.journey.seed == SEED.md5_text() and initial.settled_sorties == 0
			and TransactionReceipt.camp_problem(initial).is_empty(), "unmodified legal opening pair, resources, growth and fixed constructor seed"):
			_finish()
			return
		_write_state("initial", initial)
		if mode == "new": await _capture("01-opening-camp")
	else:
		if not _ok(app._requires_continue and not app._progress_blocked, "new process detects durable Continue"):
			_finish()
			return
		app.continue_game()
		if app._hunger_confirmation.visible:
			app._hunger_confirmation.hide()
			app._hunger_confirmation.confirmed.emit()
		if mode == "hunger-reload":
			var saved: Dictionary = app.camp_snapshot()
			_check_partial_morning(saved.last_settlement_id, saved.journey.deaths)
			await _check_morning_card_layout()
			_finish()
			return
		var expected: Dictionary = _read_state("midpoint" if mode == "resume" else "final")
		var restored: Dictionary = app.camp_snapshot()
		_event("reload", {"day":restored.day, "state_hash":RecordEncoding.fingerprint(restored), "expected_hash":RecordEncoding.fingerprint(expected), "state":_stats(restored)})
		if not _ok(not expected.is_empty() and TransactionReceipt.same(expected, restored)
			and restored.journey.seed == SEED.md5_text() and not app._progress_blocked
			and not app._requires_continue, "fresh process exact-loads complete camp including roster resources growth weapons facilities and campaign"):
			_finish()
			return
		app._enter_camp()
	if mode.begins_with("hunger"):
		if mode == "hunger": await _hunger_route()
		elif mode == "hunger-partial": await _partial_hunger_return()
		else: await _retry_hunger_return()
		_finish()
		return
	if mode != "verify":
		var last_day: int = 5 if mode == "new" else 10
		while app.day <= last_day and failures == 0:
			if not await _day(): break
		if failures == 0:
			_ok(app.day == last_day + 1, "all consecutive departures and returns reached process boundary")
			_write_state("midpoint" if mode == "new" else "final", app.camp_snapshot())
			if mode == "new":
				app.open_roster()
				await _capture("02-midpoint-roster")
				app.close_roster()
	else:
		_ok(app.day == 11 and app.settled_sorties == 9, "day ten sortie settled naturally into day eleven")
		_ok(app.crew.any(func(member: Dictionary) -> bool: return member.growth.xp_total > 0 and member.growth.level > 1), "natural multiday combat experience produced a persisted level increase")
		_ok(SurvivorRoster.definition(1).gender == &"male" and SurvivorRoster.definition(2).gender == &"female", "opening identities retain their official genders")
		_ok(app._recruits.size() >= 1, "naturally rescued members remain registered after restart")
		_ok(EconomyBuildV1.level(app.camp_snapshot(), "supply") >= 1 and EconomyBuildV1.level(app.camp_snapshot(), "workshop") >= 1, "naturally purchased facilities survive independent load")
		_ok(app.weapons.any(func(item: Dictionary) -> bool: return item.weapon_level > 1), "naturally paid weapon upgrade survives independent load")
	_finish()

func _stats(camp: Dictionary) -> Dictionary:
	return {"day":camp.day, "food":camp.food, "cash":camp.cash,
		"settled_sorties":camp.settled_sorties, "crew":camp.crew, "loadout":camp.loadout,
		"weapons":camp.weapons, "training":camp.training, "recruits":camp.recruits,
		"campaign":camp.journey.campaign, "tools":EconomyBuildV1.tools(camp)}

func _write_state(label: String, camp: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(RecordEncoding.stringify(camp))
	file.close()
	_event("checkpoint", {"label":label, "day":camp.day, "state_hash":RecordEncoding.fingerprint(camp)})

func _read_state(label: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.path_join(label + ".json")))
	if not parsed is Dictionary: return {}
	var decoded: Dictionary = RecordEncoding.unpack(parsed)
	return decoded.payload if decoded.get("error") == OK else {}

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame: int in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var path: String = output.path_join(label + ".png")
	_ok(root.get_texture().get_image().save_png(path) == OK, "native formal screenshot " + label)
	_event("screenshot", {"path":path, "day":app.day})

func _choose(offers: Array[Dictionary], before: Dictionary) -> int:
	var best: int = -1
	var score: int = -100000
	for index: int in range(offers.size()):
		var action: Dictionary = offers[index]
		var value: int = 0
		match String(action.type):
			"supply": value = 50
			"rescue": value = 80 if before.food >= RosterState.living_count(before) * 2 and before.crew.size() < 4 else 10
			"airdrop": value = 65 if before.food >= RosterState.living_count(before) * 2 else 20
			_: value = 5
		if before.day == 2 and action.type == "supply": value += 200
		if before.food < RosterState.living_count(before) * 2 and action.type == "supply": value += 200
		if int(before.day) in [4,7,10] and CampaignPressureV1.blockade_night(action): value += 1000
		if value > score and app.mission_select.choices[index].visible and not app.mission_select.choices[index].disabled:
			best = index
			score = value
	return best

func _day() -> bool:
	var before: Dictionary = app.camp_snapshot().duplicate(true)
	_event("day_begin", {"state":_stats(before)})
	app.open_mission_select()
	if not await _wait(func() -> bool: return app.mission_select.visible and not app.mission_select.loading and not app.mission_select.daily_offers.is_empty(), "daily cards loaded through production worker"):
		return false
	var offers: Array[Dictionary] = app.mission_select.daily_offers
	var index: int = _choose(offers, before)
	if not _ok(index >= 0, "a formal card is available"): return false
	var selected: Dictionary = offers[index].duplicate(true)
	var summary: Array[Dictionary] = []
	for offer: Dictionary in offers:
		summary.append({"type":offer.type, "id":offer.id, "recruit":offer.get("recruit",0), "blockade":CampaignPressureV1.blockade_night(offer)})
	_event("choice", {"day":before.day, "offers":summary, "index":index, "selected":summary[index], "offers_hash":RecordEncoding.fingerprint({"offers":offers})})
	app.mission_select._choose(index)
	app.mission_select._confirm_departure()
	if not _ok(app.phase == AppMain.Phase.EXPEDITION and is_instance_valid(app.expedition) and not app._progress_blocked, "confirmed card starts production controller and transaction"):
		return false
	var world: Expedition = app.expedition
	world.set_physics_process(false)
	world.set_process(false)
	world.spawn_resolved.connect(func(event: Dictionary) -> void:
		_event("spawn", {"day":world.day, "elapsed":world.elapsed, "record":event}))
	if not _ok(TransactionReceipt.same(world.supply.generated, selected) and world.day == int(before.day)
		and world.tuning.daylight_seconds == 105.0 and world.survivors.size() == RosterState.living_count(before), "departure uses unchanged selected action day roster and daylight"):
		return false
	if not await _advance(world, func() -> bool: return not world.bus_view.running(), "formal bus arrival"): return false
	_event("field", {"day":world.day, "location":world.layout.display_name, "type":selected.type})
	if world.rescue_target != null:
		world.command_move(world.rescue_target.npc.position)
		world.rescue_target.request()
		if not await _advance(world, func() -> bool: return world.rescue_target.status == "IN_FIELD_JOINED", "natural candidate assistance and persisted field join"): return false
		_ok(world.field_joins.size() == 1 and world.survivors.size() == RosterState.living_count(before) + 1, "same rescued NPC joins the actual squad")
	if world.recon_site != null:
		var recon: Expedition.SearchSite = world.recon_site
		world.command_move(recon.door)
		world.request_search(recon.id)
		if not _ok(world.search_assignments.member_for(String(recon.id)) > 0, "formal reconnaissance order is assigned"): return false
		if not await _advance(world, func() -> bool: return recon.searched, "normal reconnaissance work reveals the mission targets"): return false
		_event("recon", {"day":world.day, "elapsed":world.elapsed, "site":recon.id})
	# Prefer food and the selected mission's primary work. Orders use discoverable
	# sites, normal navigation, real work time and the untouched director/combat.
	var targets: Array[Expedition.SearchSite] = []
	for site: Expedition.SearchSite in world.sites:
		if world.site_discovered(site): targets.append(site)
	for id: String in selected.objective.site_ids:
		if not _ok(targets.any(func(site: Expedition.SearchSite) -> bool: return String(site.id) == id), "mission objective is revealed through formal exploration " + id): return false
	targets.sort_custom(func(a: Expedition.SearchSite, b: Expedition.SearchSite) -> bool:
		var rank_a: int = -1 if String(a.id) in selected.objective.site_ids else (0 if a.kind == &"food" else 1)
		var rank_b: int = -1 if String(b.id) in selected.objective.site_ids else (0 if b.kind == &"food" else 1)
		return rank_a < rank_b if rank_a != rank_b else a.door.distance_squared_to(world.layout.bus_door) < b.door.distance_squared_to(world.layout.bus_door))
	var searched: Array[String] = []
	for site: Expedition.SearchSite in targets:
		if String(site.id) not in selected.objective.site_ids and (world.elapsed > 76.0 or searched.size() >= 2): break
		if site == world.recon_site or site == world.billboard_site: continue
		world.command_move(site.door)
		world.request_search(site.id)
		if not _ok(world.search_assignments.member_for(String(site.id)) > 0, "normal search order assigned " + String(site.id)): return false
		if not await _advance(world, func() -> bool: return site.searched, "normal movement and work completes " + String(site.id)): return false
		searched.append(String(site.id))
		_event("searched", {"day":world.day, "site":site.id, "elapsed":world.elapsed, "food_carried":world.food_loot, "cash_carried":world.loot, "tools_carried":world._carried_tools()})
	world.command_move(world.layout.bus_door)
	var blockade: bool = CampaignPressureV1.blockade_night(selected)
	if blockade:
		if not await _advance(world, func() -> bool: return world.elapsed >= 112.0, "scheduled blockade crosses unchanged 105-second night boundary"): return false
		_ok(world.threat_status().stage >= ThreatDirector.Stage.NIGHT, "blockade reached real night director stage")
		if world.day == 10: await _capture("03-day10-blockade-night")
	if not await _advance(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds, "bus ready through normal clock"): return false
	world.request_bus_action()
	if not _ok(world.phase == Expedition.Phase.ENGINE, "engine starts through bus action"): return false
	world.request_bus_gather()
	if not await _advance(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED, "full squad gathers and extracts"): return false
	if not await _advance(world, func() -> bool: return app.phase == AppMain.Phase.RESULT and not world.bus_view.running(), "formal departure animation and frozen return UI"): return false
	var pending: Dictionary = app._pending_settlement.duplicate(true)
	if not _ok(not pending.is_empty() and TransactionReceipt.same(before, app.camp_snapshot()), "frozen result precedes camp mutation"): return false
	var diners: Array[int] = []
	for survivor: FieldActor in world.survivors:
		if survivor.health > 0 and not SurvivorRoster.member(before.crew, survivor.member_id).is_empty():
			diners.append(survivor.member_id)
	diners.sort()
	var meal: Dictionary = pending.last_day
	var facility_cap: int = EconomyBuildV1.level(before, "supply")
	var expected_bonus: int = mini(facility_cap, floori(world.food_loot / 2.0))
	if not _ok(meal.ration_member_ids == diners and meal.food_required == diners.size()
			and meal.food_before == before.food and meal.food_found == world.food_loot
			and meal.get("facility_food", 0) == expected_bonus,
			"each night uses this outing's food, its departure facility and surviving pre-existing diners"): return false
	if blockade:
		if not _ok(app.get_node("Interface/Screen/Result/Scroll/Body").text.contains("经历入夜"), "frozen result reports the scheduled blockade night actually experienced"): return false
	if world.day == 10: await _capture("04-day10-return")
	var field: Dictionary = {"elapsed":world.elapsed, "searched":searched, "living_return":world.living_count(),
		"food_carried":world.food_loot, "cash_carried":world.loot, "kills":world.kills,
		"joins":world.field_joins, "health":world.survivors.map(func(actor: FieldActor) -> Dictionary: return {"id":actor.member_id,"hp":actor.health}),
		"blockade":blockade, "threat":world.threat_status()}
	await app._confirm_result_ui()
	var after: Dictionary = app.camp_snapshot()
	if not _ok(app.day == int(before.day) + 1 and app.settled_sorties == int(before.settled_sorties) + 1
		and not app._progress_dirty and not app._progress_blocked and TransactionReceipt.camp_problem(after).is_empty(), "return confirmation naturally advances and persists exactly one day"):
		return false
	var durable: Dictionary = app.progress_session.inspect()
	if not _ok(durable.error == OK and durable.state == "CAMP" and TransactionReceipt.same(after, durable.camp), "formal durable save matches settled state"): return false
	if not _ok(after.last_day.task.status == "COMPLETED", "selected formal mission objectives completed before returning"): return false
	_event("day_return", {"day":before.day, "field":field, "ledger":after.last_day, "state":_stats(after)})
	if after.journey.state != "ACTIVE":
		_event("design_end", {"day":after.day,"journey_state":after.journey.state,"ledger":after.last_day})
		return _ok(false, "campaign survives strategy to the next day")
	await _invest()
	return failures == 0

func _invest() -> void:
	var before: Dictionary = app.camp_snapshot()
	for facility: String in ["supply", "workshop", "planning"]:
		var op: String = "build" if EconomyBuildV1.level(before, facility) == 0 else "upgrade_facility"
		var quote: Dictionary = EconomyBuildV1.offer(before, op, facility)
		if quote.available:
			await app.confirm_economy_edit(EconomyBuildV1.request(before, op, facility, "", before.profile_id + ":edit:" + RunSave.new_profile_id()))
			_ok(not app._progress_blocked and not app._progress_dirty and EconomyBuildV1.level(app.camp_snapshot(), facility) == EconomyBuildV1.level(before, facility) + 1, "paid facility transaction " + facility)
			_event("camp_edit", {"op":op,"target":facility,"quote":quote,"state":_stats(app.camp_snapshot())})
			before = app.camp_snapshot()
	var gun: Dictionary = WeaponInventory.for_member(before, 1)
	if not gun.is_empty():
		var quote: Dictionary = EconomyBuildV1.offer(before, "upgrade_weapon", gun.instance_id)
		if quote.available:
			await app.confirm_economy_edit(EconomyBuildV1.request(before, "upgrade_weapon", gun.instance_id, "", before.profile_id + ":edit:" + RunSave.new_profile_id()))
			_ok(WeaponInventory.find(app.camp_snapshot(), gun.instance_id).weapon_level == gun.weapon_level + 1, "paid existing weapon upgrade")
			_event("camp_edit", {"op":"upgrade_weapon","quote":quote,"state":_stats(app.camp_snapshot())})
			before = app.camp_snapshot()
	if before.food > RosterState.living_count(before) * 2:
		var preview: Dictionary = TrainingRules.preview(before, 1)
		if preview.error.is_empty():
			app.open_training()
			app.confirm_training(preview.request)
			_ok(app.food == int(before.food) - 1 and SurvivorRoster.member(app.crew, 1).growth.trait.progress == SurvivorRoster.member(before.crew, 1).growth.trait.progress + 1, "formal camp training pays food and saves personal progress")
			app.close_training()
			_event("camp_edit", {"op":"train_trait","state":_stats(app.camp_snapshot())})

func _empty_return() -> Expedition:
	app.open_mission_select()
	if not await _wait(func() -> bool: return app.mission_select.visible and not app.mission_select.loading and not app.mission_select.daily_offers.is_empty(), "hunger control loads formal cards"): return null
	var chosen: int = -1
	for index: int in range(app.mission_select.daily_offers.size()):
		if app.mission_select.daily_offers[index].type == "supply" and not app.mission_select.choices[index].disabled:
			chosen = index
			break
	if not _ok(chosen >= 0, "hunger control has a normal food mission"): return null
	app.mission_select._choose(chosen)
	app.mission_select._confirm_departure()
	if not _ok(app.phase == AppMain.Phase.EXPEDITION and not app._progress_blocked, "hunger control departs formally"): return null
	var world: Expedition = app.expedition
	world.set_physics_process(false)
	world.set_process(false)
	if not await _advance(world, func() -> bool: return not world.bus_view.running(), "hunger control arrival"): return null
	world.command_move(world.layout.bus_door)
	if not await _advance(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds, "hunger control waits for ready bus"): return null
	world.request_bus_action()
	world.request_bus_gather()
	if not await _advance(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED, "hunger control extracts living pair"): return null
	if not await _advance(world, func() -> bool: return app.phase == AppMain.Phase.RESULT and not world.bus_view.running(), "hunger control frozen return UI"): return null
	return world


func _pay_for_training(times: int) -> bool:
	for index: int in range(times):
		var preview: Dictionary = TrainingRules.preview(app.camp_snapshot(), 1)
		if not _ok(preview.error.is_empty(), "one ration can fund training"): return false
		app.open_training()
		app.confirm_training(preview.request)
		app.close_training()
	return _ok(app.food == 4 - times and not app._progress_blocked, "training spends exactly the selected rations")


func _partial_hunger_return() -> void:
	if not _pay_for_training(3): return
	var world: Expedition = await _empty_return()
	if not is_instance_valid(world): return
	var evening: String = app.get_node("Interface/Screen/Result/Scroll/Body").text
	if not _ok(evening.contains("本次口粮缺口 1 粮") and not evening.contains("饥饿死亡")
		and not evening.contains("生命0/") and not evening.contains("营地：第")
		and app._pending_settlement.journey.active_member_ids.size() == 1
		and RosterState.living_count(app.camp_snapshot()) == 2, "evening shows two returning survivors and one missing ration only"): return
	var id: String = app._pending_settlement.last_settlement_id
	var expected: Array = app._pending_settlement.journey.deaths.duplicate(true)
	await app._confirm_result_ui()
	_check_partial_morning(id, expected)


func _check_partial_morning(id: String, expected: Array) -> void:
	var morning: String = ReturnFeedback.starvation_text(app.crew, expected, id)
	_ok(app.camp_scene.is_visible_in_tree(), "nonterminal morning enters the actual camp scene")
	_ok(app.camp_scene._return_text.is_visible_in_tree(), "camp return summary is visible")
	_ok(not morning.is_empty() and app.camp_scene._return_text.text.contains("第 3 天清晨 · " + morning), "camp summary names the morning victim")
	_ok(RosterState.living_count(app.camp_snapshot()) == 1, "one resident survives this meal")
	_ok(TransactionReceipt.same({"deaths":expected}, {"deaths":app.camp_snapshot().journey.deaths}), "committed death matches the frozen identity")
	_event("partial_morning", {"day":app.day, "meal":app.last_day, "notice":morning, "display":app.camp_scene._return_text.text})


func _check_morning_card_layout() -> void:
	var scene: CampSceneView = app.camp_scene
	var ledger: Dictionary = app.last_day.duplicate(true)
	var names: String = "顾予安、夏之遥、陆望舒、韩知秋、许行舟、林雨桐、宋明远"
	for extended: bool in [false, true]:
		if extended:
			ledger.facility_food = 2
			ledger.facility_stored = 1
		scene._return_text.text = "第 10 天清晨 · 餐后饥饿死亡：%s\n%s" % [names, ReturnFeedback.food_text(ledger)]
		scene._return_objective.text = "补给 · 提前撤离未完成（0/3）"
		scene._return_objective.visible = extended
		scene._return_advice.visible = extended
		for frame: int in range(4): await process_frame
		var card: Rect2 = scene._return_summary.get_global_rect()
		var food: Rect2 = scene._return_text.get_global_rect()
		var tag: String = "extended" if extended else "compact"
		_ok(scene.get_global_rect().encloses(card) and card.encloses(food)
			and scene._return_text.get_visible_line_count() == scene._return_text.get_line_count(),
			"all seven names and every meal line fit the " + tag + " morning card")
		if extended:
			var objective: Rect2 = scene._return_objective.get_global_rect()
			var advice: Rect2 = scene._return_advice.get_global_rect()
			_ok(card.encloses(advice) and objective.position.y >= food.end.y and advice.position.y >= objective.end.y,
				"morning meal, objective and repair notice occupy separate visible rows")
		_event("morning_layout", {"case":tag, "card":str(card), "meal":str(food), "lines":scene._return_text.get_line_count()})


func _retry_hunger_return() -> void:
	if not _pay_for_training(4): return
	app.progress_session.fault_hook = func(point: String) -> Error:
		if point == "before_record_write" and is_instance_valid(app.expedition) and app.expedition.phase == Expedition.Phase.FINISHED:
			return ERR_CANT_CREATE
		return OK
	var world: Expedition = await _empty_return()
	app.progress_session.fault_hook = Callable()
	if not is_instance_valid(world): return
	if not _ok(app._progress_dirty and app._progress_blocked and app._pending_settlement.is_empty()
		and app.get_node("Interface/Screen/Result/Heading").text == "结算未应用"
		and not app.get_node("Interface/Screen/Result/Scroll/Body").text.contains("饥饿死亡"),
		"failed result preparation keeps morning losses hidden and offers retry"): return
	await app._confirm_result_ui()
	var saved: Dictionary = app.progress_session.inspect()
	_ok(saved.get("state") == "ENDED" and app.day == 3 and app.phase == AppMain.Phase.RESULT
		and app.get_node("Interface/Screen/Result/Backdrop/MorningCamp").is_visible_in_tree()
		and app.get_node("Interface/Screen/Result/Scroll/Body").text.contains("餐后饥饿死亡：顾予安、夏之遥"),
		"retry of frozen packet commits a single night and reveals both names in the morning")


func _hunger_route() -> void:
	# Separate directed consequence check: deliberately return without searching.
	# Three real meals spend the opening four food, then invoke the original
	# FrozenSettlement starvation policy. Never counted as the ten-day route.
	for outing: int in range(3):
		var before: Dictionary = app.camp_snapshot()
		var world: Expedition = await _empty_return()
		if not is_instance_valid(world): return
		var pending: Dictionary = app._pending_settlement
		if not _ok(not pending.is_empty() and app.day == int(before.day), "return remains a frozen preview until confirming camp"): return
		if outing == 2:
			var preview: String = app.get_node("Interface/Screen/Result/Scroll/Body").text
			_ok(app.get_node("Interface/Screen/Result/Heading").text == "巴士归航"
				and preview.contains("本次口粮缺口 2 粮") and not preview.contains("饥饿死亡")
				and not preview.contains("生命0/") and not preview.contains("旅程已结束")
				and not app._battle_new_button.visible, "evening shows the shortfall without revealing overnight fates")
		_ok(world.food_loot == 0 and world.living_count() == 2 and pending.last_day.food_consumed == (2 if outing < 2 else 0)
			and pending.last_day.food_shortage == (0 if outing < 2 else 2) and pending.food == (2 if outing == 0 else 0), "three real returns exhaust four initial food without resource edits")
		await app._confirm_result_ui()
		var after: Dictionary = app.camp_snapshot()
		_event("hunger_return", {"outing":outing + 1, "day":before.day, "ledger":after.last_day, "state":_stats(after), "deaths":after.journey.deaths})
		var saved: Dictionary = app.progress_session.inspect()
		if not _ok(saved.error == OK and TransactionReceipt.same(saved.camp, after), "hunger consequence is durably saved"): return
		if outing == 2:
			var morning: String = app.get_node("Interface/Screen/Result/Scroll/Body").text
			_ok(saved.state == "ENDED" and saved.receipt.phase == "COMMITTED"
				and saved.receipt.envelope.result.hunger.victim_ids.size() == 2
				and app.get_node("Interface/Screen/Result/Heading").text == "第 %d 天清晨 · 营地" % int(after.day)
				and app.get_node("Interface/Screen/Result/Backdrop/MorningCamp").is_visible_in_tree()
				and morning.contains("旅程结束 · 口粮耗尽") and morning.contains("餐后饥饿死亡：顾予安、夏之遥"),
				"committed next morning reveals both overnight losses at camp and ends journey")
	var final: Dictionary = app.camp_snapshot()
	_ok(final.journey.state == "FAILED" and RosterState.living_count(final) == 0 and final.journey.deaths.size() == 2
		and final.journey.deaths.all(func(death: Dictionary) -> bool: return death.cause == "STARVATION")
		and final.last_day.evacuated, "official zero-ration consequence is post-return starvation of both members")

func _finish() -> void:
	_event("complete", {"checks":checks,"failures":failures,"day":app.day if is_instance_valid(app) else -1})
	if is_instance_valid(app):
		if is_instance_valid(app.audio): app.audio.shutdown()
		app.queue_free()
		await process_frame
	if log_file != null: log_file.close()
	print("BH_TEN_DAY_SUMMARY " + JSON.stringify({"checks":checks,"failures":failures,"mode":mode,"wall_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures == 0 else 1)
