extends "res://tests/m48_campaign_flow.gd"
## Normal Windows-bound preparation and two-effect recovery; no resource/HP/world injection.
## All modes require --flow-resume. Use --m49-recovery=prepare|field|restore.
## Restore additionally requires --expected=<absolute isolated field/checkpoint.json>.

var recovery_wait_captured: bool = false


func _initialize() -> void:
	super._initialize()
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_capture_live_wait)


func _capture_live_wait() -> void:
	if recovery_wait_captured or not is_instance_valid(app) or app.get("_startup_pending") != true:
		return
	if Time.get_ticks_usec() - int(app.get("_progress_started_usec")) < 2000000:
		return
	recovery_wait_captured = true
	viewport.get_texture().get_image().save_png(output.path_join("startup-live-clock.png"))
	_write("startup-live-clock.json", {"caption":app._startup_label.text, "pid":OS.get_process_id(),
		"scope":"NATIVE_RECOVERY_EVIDENCE_NOT_PERFORMANCE_SAMPLE; screenshot encoding is retained"})


func _frame() -> void:
	await super._frame()
	var deadline: int = Time.get_ticks_msec() + 900000
	while is_instance_valid(app) and (app.get("_progress_busy") == true or app.get("_camp_commit_busy") == true) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(is_instance_valid(app) and app.get("_progress_busy") != true,
		"original serial authority reaches its actual completion before the next test action")


func _journey() -> void:
	_check(false, "M49 recovery uses --flow-resume and an existing original Windows-bound camp")


func _resume() -> void:
	var mode: String = _argument("--m49-recovery=")
	if mode == "restore":
		await _restore_two_effects()
		_snapshot_metrics()
		return
	_check(mode in ["prepare", "field"], "known M49 recovery mode")
	if mode not in ["prepare", "field"]:
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	_check(app.expedition == null and app.camp_scene.is_visible_in_tree() and not app._progress_blocked
		and EconomyBuildV1.enabled(camp), "normal Continue restores a real M48 camp without changing its binding")
	if app.expedition != null or app._progress_blocked or not EconomyBuildV1.enabled(camp):
		return
	start_hash = RecordEncoding.fingerprint(camp)
	if mode == "prepare":
		await _prepare_two_effects()
	else:
		await _field_two_effects()
	_snapshot_metrics()


func _snapshot_metrics() -> void:
	_write("snapshot-metrics.json", {"pid":OS.get_process_id(),
		"view_native_serialized_bytes":var_to_bytes(app._progress_view).size(),
		"catalog_native_serialized_bytes":var_to_bytes(app._catalog_view).size(),
		"static_memory_bytes":OS.get_static_memory_usage(), "peak_static_memory_bytes":OS.get_static_memory_peak_usage(),
		"worker_timing":app._progress_last_timing, "scope":"after operation; serialization size is not RSS"})


func _prepare_two_effects() -> void:
	prefer_compact_funding = true
	for facility: String in ["supply", "workshop"]:
		if EconomyBuildV1.level(app.camp_snapshot(), facility) == 0:
			if not await _fund("build", facility) or not await _economy("build", facility):
				return
	# Frozen ordinary equipment sources grant each ability on actual confirmed return.
	for attempt: int in range(18):
		var missing: String = ""
		for identity: String in [SpecialPowers.SPEED, SpecialPowers.FREEZE]:
			if identity not in app.camp_snapshot().journey.build.powers.owned:
				missing = identity
				break
		if missing.is_empty():
			break
		desired_power = missing
		if not await _gather(false, -1, false):
			return
	desired_power = ""
	var owns_both: bool = [SpecialPowers.SPEED, SpecialPowers.FREEZE].all(func(identity: String) -> bool:
		return identity in app.camp_snapshot().journey.build.powers.owned)
	_check(owns_both, "two requested abilities were actually recovered and confirmed through ordinary actions")
	if not owns_both:
		return
	if app.camp_snapshot().journey.build.powers.slots.size() < 2:
		if not await _power_invest(PowerState.SECOND_SLOT):
			return
	for slot: int in range(2):
		var identity: String = SpecialPowers.SPEED if slot == 0 else SpecialPowers.FREEZE
		if app.camp_snapshot().journey.build.powers.slots[slot] != identity:
			await _equip_power_ui(slot, identity)
	# An upgrade needs a real successful return after the facility's construction.
	var needs_return: bool = false
	for facility: String in ["supply", "workshop"]:
		var state: Dictionary = EconomyBuildV1.state(app.camp_snapshot()).facilities[facility]
		needs_return = needs_return or (int(state.level) == 1 and int(state.built_sortie) >= int(app.settled_sorties))
	if needs_return and not await _gather(false, -1, false):
		return
	for facility: String in ["supply", "workshop"]:
		if EconomyBuildV1.level(app.camp_snapshot(), facility) == 1:
			if not await _fund("upgrade_facility", facility) or not await _economy("upgrade_facility", facility):
				return
	# Preserve a ready firearm with its actual instance identity for the reload checkpoint.
	var firearm: String = _ready_reload_weapon(app.camp_snapshot())
	if firearm.is_empty():
		firearm = await _craft_gun("long_rifle")
	_check(not firearm.is_empty(), "the confirmed inventory retains a real ready firearm")
	if firearm.is_empty():
		return
	var member_id: int = _living_member_id(app.camp_snapshot())
	if WeaponInventory.for_member(app.camp_snapshot(), member_id).get("instance_id") != firearm:
		await _equip_weapon_ui(firearm, member_id)
	var minimum: int = 100
	if not _argument("--m49-min-receipts=").is_empty():
		minimum = maxi(100, int(_argument("--m49-min-receipts=")))
	var paid_training: bool = await _train_one()
	for attempt: int in range(18):
		var state: Dictionary = app.progress_session.inspect()
		if state.error != OK or (int(state.receipt.revision) >= minimum and app.settled_sorties >= 12):
			break
		if app.settled_sorties < 12 or not await _train_one():
			if not await _gather(false, -1, false):
				return
	var final: Dictionary = app.progress_session.inspect()
	_check(final.error == OK and final.state == "CAMP" and app.settled_sorties >= 12
		and int(final.receipt.revision) >= minimum, "prepared long source has twelve real returns and at least one hundred authentic receipts")
	_write("prepared.json", {"pid":OS.get_process_id(), "path":app.progress_path,
		"starting_camp":start_hash, "camp":RecordEncoding.fingerprint(app.camp_snapshot()),
		"value":app.camp_snapshot(), "receipt":final.get("hash", ""), "revision":final.get("receipt", {}).get("revision", 0),
		"route":route, "edits":edits, "paid_training":paid_training,
		"scope":"NORMAL_FUNDED_FACILITIES_TWO_RECOVERED_ABILITIES_AND_PAID_EDITS"})
	await _shot("prepared-long-camp")


func _train_one() -> bool:
	var before: Dictionary = app.camp_snapshot()
	var meal: Dictionary = CampEconomy.rations(int(before.day), before.crew, int(before.food), app.camp_rules)
	if int(before.food) <= int(meal.required) + 1:
		return false
	var member_id: int = 0
	for member: Dictionary in before.crew:
		if member.health > 0 and TrainingRules.preview(before, int(member.id)).get("error") == "":
			member_id = int(member.id)
			break
	if member_id == 0:
		return false
	app.open_training()
	await _tap(app.training_panel.member_buttons[member_id])
	await _tap(app.training_panel.train_button)
	await _tap(app.training_panel.confirmation.get_ok_button())
	var after: Dictionary = app.camp_snapshot()
	var trained: bool = (not app._progress_blocked and int(after.food) == int(before.food) - 1
		and int(SurvivorRoster.member(after.crew, member_id).growth.trait.progress) == int(SurvivorRoster.member(before.crew, member_id).growth.trait.progress) + 1)
	_check(trained, "one actual food-funded training improves the same living member exactly once")
	await _tap(app.training_panel.back_button)
	return trained


func _ready_reload_weapon(camp: Dictionary) -> String:
	for gun: String in ["long_rifle", "carbine", "shotgun_v1"]:
		for item: Dictionary in camp.weapons:
			if item.weapon_id == gun and item.condition == "ready":
				return String(item.instance_id)
	return ""


func _living_member_id(camp: Dictionary) -> int:
	for member: Dictionary in camp.crew:
		if member.health > 0:
			return int(member.id)
	return 0


func _field_two_effects() -> void:
	var camp: Dictionary = app.camp_snapshot()
	var slots: Array = camp.journey.build.powers.slots
	_check(slots.size() >= 2 and slots[0] == SpecialPowers.SPEED and slots[1] == SpecialPowers.FREEZE,
		"prepared camp has the two actual independently equipped ability slots")
	if slots.size() < 2 or slots[0] != SpecialPowers.SPEED or slots[1] != SpecialPowers.FREEZE:
		return
	if not await _open_cards():
		return
	var index: int = _find_card(func(action: Dictionary) -> bool:
		return action.layout["size"] == "large" and not action.get("campaign", {}).get("is_finale", false))
	if index < 0:
		index = _find_card(func(action: Dictionary) -> bool: return action.type == "supply")
	var world: Expedition = await _start(index)
	if world == null:
		return
	_write("representative-map.json", _geometry(world.supply.generated))
	await _collect(world, 2)
	var actor: FieldActor = null
	for member: FieldActor in world.survivors:
		if member.health > 0 and member.magazine != null:
			actor = member
			break
	_check(actor != null, "a real living firearm user can produce the representative reload")
	if actor == null:
		return
	await _drive(world, func() -> bool: return actor.magazine.reloading)
	_check(actor.magazine.reloading and world.phase != Expedition.Phase.FINISHED,
		"actual shots start the original incomplete reload")
	if not actor.magazine.reloading or world.phase == Expedition.Phase.FINISHED:
		return
	world.step(0.1)
	await _tap(world.power_panel.activation_button)
	world.step(0.07)
	await _tap(world.second_power_panel.activation_button)
	var remaining: Array[float] = [SpecialPowers.remaining(world.powers, world.elapsed, 0),
		SpecialPowers.remaining(world.powers, world.elapsed, 1)]
	_check(remaining[0] > 0.0 and remaining[1] > 0.0 and remaining[0] != remaining[1]
		and actor.magazine.reloading and actor.magazine.remaining > 0.0 and actor.magazine.remaining < actor.magazine.seconds(),
		"two original effects have independent positive clocks while the real reload remains partial")
	var magazines: Array[Dictionary] = []
	for member: FieldActor in world.survivors:
		if member.magazine != null:
			magazines.append({"member_id":member.member_id, "hash":RecordEncoding.fingerprint(member.magazine.snapshot())})
	await _shot("two-effects-partial-reload")
	await _suspend(world, "checkpoint.json", {"camp":RecordEncoding.fingerprint(camp),
		"starting_camp":start_hash, "path":app.progress_path, "powers":RecordEncoding.fingerprint(world.powers),
		"world_clock_record":RecordEncoding.stringify({"elapsed":world.elapsed}),
		"power_remaining_record":RecordEncoding.stringify({"values":remaining}), "magazines":magazines,
		"route":route, "edits":edits, "scope":"NORMAL_TWO_EFFECTS_ACTUAL_RELOAD_PATH_BOUND_SUSPEND"})
	var saved: Dictionary = app.progress_session.inspect()
	_check(saved.error == OK and saved.state == "SUSPENDED" and saved.receipt.phase == "SUSPEND_READY",
		"original suspend and readback retain the complete two-effect world")
	_write("suspend-receipt.json", {"pid":OS.get_process_id(), "path":app.progress_path,
		"receipt":saved.get("hash", ""), "phase":saved.get("receipt", {}).get("phase", ""),
		"binding_sha256":FileAccess.get_sha256(app.progress_path + ".txn/binding.json")})


func _restore_two_effects() -> void:
	var source: String = _argument("--expected=").replace("\\", "/").simplify_path()
	var local_root: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(source)) if source.is_absolute_path() and source.begins_with(local_root) and FileAccess.file_exists(source) else null
	_check(expected is Dictionary and SurvivalContracts.integer(expected.get("pid"), 1, SurvivalContracts.MAX_ID) and int(expected.pid) != OS.get_process_id()
		and expected.get("path") == app.progress_path, "explicit checkpoint belongs to this original path and another isolated PID")
	if not expected is Dictionary or expected.get("path") != app.progress_path:
		return
	route.assign(expected.get("route", []))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	_check(world != null and not app._progress_blocked, "normal Continue reconstructs the original suspended world")
	if world == null or app._progress_blocked:
		return
	world.set_physics_process(false)
	world.set_process(false)
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	var actual: Dictionary = SortieSnapshot.capture(world)
	var exact_clock: Dictionary = RecordEncoding.unpack(JSON.parse_string(expected.world_clock_record))
	var exact_remaining: Dictionary = RecordEncoding.unpack(JSON.parse_string(expected.power_remaining_record))
	var before: Dictionary = app.camp_snapshot()
	_check(RecordEncoding.fingerprint(actual) == expected.fingerprint and RecordEncoding.fingerprint(before) == expected.camp,
		"whole world and camp preserve their exact original fingerprints across PID")
	_check(exact_clock.error == OK and world.elapsed == float(exact_clock.payload.elapsed)
		and RecordEncoding.fingerprint(world.powers) == expected.powers, "world clock and complete ability state restore exactly")
	var clocks: Array[float] = []
	for slot: int in range(2):
		var remaining: float = SpecialPowers.remaining(world.powers, world.elapsed, slot)
		clocks.append(remaining)
		_check(exact_remaining.error == OK and remaining == float(exact_remaining.payload.values[slot]) and remaining > 0.0
			and not SpecialPowers.event_at(world.powers, slot).is_empty(), "slot %d restores its own accepted event and exact clock" % slot)
	var partial: bool = false
	for actor: FieldActor in world.survivors:
		if actor.magazine == null:
			continue
		partial = partial or (actor.magazine.reloading and actor.magazine.remaining > 0.0 and actor.magazine.remaining < actor.magazine.seconds())
		for prior: Dictionary in expected.magazines:
			if int(prior.member_id) == actor.member_id:
				_check(RecordEncoding.fingerprint(actor.magazine.snapshot()) == prior.hash,
					"member %d restores the exact actual magazine and partial reload" % actor.member_id)
	_check(partial, "independent process retains the real incomplete reload")
	var recovered: Dictionary = app.progress_session._transaction.recover()
	_check(SortieSnapshot.problem(actual, recovered.receipt).is_empty(), "restored world still authenticates against the original claimed receipt")
	_write("restored-world.json", {"source":source, "source_pid":expected.pid, "pid":OS.get_process_id(),
		"path":app.progress_path, "world":actual, "fingerprint":RecordEncoding.fingerprint(actual),
		"clocks":clocks, "partial_reload":partial, "receipt":recovered.get("hash", "")})
	if failures > 0:
		return
	await _shot("restored-two-effects-partial-reload")
	await _unpause(world)
	await _finish_outing(world)
	var final: Dictionary = app.camp_snapshot()
	_check(not app._progress_blocked and not app._progress_dirty and int(final.settled_sorties) == int(before.settled_sorties) + 1,
		"restored world completes the actual bus return and one confirmed settlement")
	_write("resume-return.json", {"source":source, "source_pid":expected.pid, "pid":OS.get_process_id(),
		"before":expected.camp, "after":RecordEncoding.fingerprint(final), "camp":final, "route":route})


func _extract(world: Expedition) -> void:
	await _until(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds)
	world.request_bus_action()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	world.request_bus_gather()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	# Finish now authenticates on the serial worker before the original bus
	# departure animation starts. Fixed frame counts cannot stand in for that ACK.
	await _frame()
	for index: int in range(1500):
		if not world.bus_view.running():
			break
		world.step(STEP)
		if index % 30 == 0:
			await _frame()
	var gathered: Vector2i = world.bus_view.final_boarding
	_check(app.phase == app.Phase.RESULT and gathered.x == gathered.y and gathered.y == world.living_count(),
		"actual bus completes departure after full result authentication")
	await _hold(3)
