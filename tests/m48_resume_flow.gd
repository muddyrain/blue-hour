extends "res://tests/m48_campaign_flow.gd"
## Reopens the original path-bound profile and finishes a legitimate return.
## No resource, actor, eligibility or saved-world mutation is performed.
## --flow-resume --expected=/absolute/repo/.local/.../checkpoint.json
## Expected: {fingerprint,pid}; optional {camp,powers,power_remaining,magazines,elapsed}.
## --resume-legacy skips only the M48-specific three-effects/partial-reload requirements.
## --resume-camp expects {camp,pid}, then runs an ordinary supply return.

func _journey() -> void:
	_check(false, "resume driver requires --flow-resume and a real existing isolated profile")

func _resume() -> void:
	var expected_path: String = _argument("--expected=")
	var local_root: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	var expected: Variant = null
	if expected_path.is_absolute_path() and expected_path.replace("\\", "/").begins_with(local_root) and FileAccess.file_exists(expected_path):
		expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	_check(expected is Dictionary and SurvivalContracts.integer(expected.get("pid"),1,SurvivalContracts.MAX_ID),
		"explicit original checkpoint is available inside the isolated evidence directory")
	if not expected is Dictionary or not expected.has("pid"):
		return
	route.assign(expected.get("route",[]))
	start_hash = expected.get("starting_camp","")
	_check(int(expected.pid) != OS.get_process_id(), "restore uses an independent process")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(not app._progress_blocked, "normal Continue accepts the unchanged bound source profile")
	if app._progress_blocked:
		return
	var camp: Dictionary = app.camp_snapshot()
	if expected.has("camp"):
		_check(RecordEncoding.fingerprint(camp) == expected.camp, "camp source resources and ownership restore exactly")
	if "--resume-camp" in OS.get_cmdline_user_args():
		_check(app.expedition == null and app.camp_scene.is_visible_in_tree(), "camp checkpoint resumes into its ordinary camp")
		if app.expedition != null or CampaignState.ended(camp):
			return
		var field: Expedition = await _ordinary_supply()
		if field != null:
			await _food(field,2)
			await _finish_outing(field)
		_write("restored-camp.json", {"source":expected_path,"source_pid":expected.pid,"pid":OS.get_process_id(),"camp":app.camp_snapshot(),"returns":route})
		return
	var world: Expedition = app.expedition
	_check(world != null and expected.get("fingerprint") is String, "normal Continue reconstructs the checkpoint world")
	if world == null or not expected.get("fingerprint") is String:
		return
	world.set_physics_process(false)
	world.set_process(false)
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report.duplicate(true)))
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	var actual: Dictionary = SortieSnapshot.capture(world)
	var actual_hash: String = RecordEncoding.fingerprint(actual)
	_check(actual_hash == expected.fingerprint, "whole world exact fingerprint preserves sources map health jobs equipment effects and clocks")
	if actual_hash != expected.fingerprint:
		_write("restore-mismatch.json", {"expected":expected,"actual":actual,"actual_hash":actual_hash})
		return
	var recovered: Dictionary = app.progress_session._transaction.recover()
	var issue: String = SortieSnapshot.problem(actual,recovered.receipt)
	_check(issue.is_empty(), "restored world remains valid against its genuine receipt: " + issue)
	if not issue.is_empty():
		return
	if expected.get("powers") is String:
		_check(RecordEncoding.fingerprint(world.powers) == expected.powers, "independent power proof restores exactly")
	if expected.has("world_clock_record"):
		var clock_record: Variant = JSON.parse_string(expected.world_clock_record) if expected.world_clock_record is String else expected.world_clock_record
		var decoded_clock: Dictionary = RecordEncoding.unpack(clock_record) if clock_record is Dictionary else {"error":ERR_PARSE_ERROR,"payload":{}}
		_check(decoded_clock.error == OK and SurvivalContracts.number(decoded_clock.payload.get("elapsed")),"checkpoint has an exact encoded world-clock record")
		if decoded_clock.error == OK and SurvivalContracts.number(decoded_clock.payload.get("elapsed")):
			_check(float(world.elapsed) == float(decoded_clock.payload.elapsed), "simulation clock restores the exact encoded elapsed value")
	elif expected.has("elapsed"):
		_check(float(world.elapsed) == float(expected.elapsed), "simulation clock does not advance during suspended restart")
	var exact_remaining: Array = []
	if expected.get("power_remaining_record") is Dictionary or expected.get("power_remaining_record") is String:
		var remaining_record: Variant = JSON.parse_string(expected.power_remaining_record) if expected.power_remaining_record is String else expected.power_remaining_record
		var decoded_remaining: Dictionary = RecordEncoding.unpack(remaining_record) if remaining_record is Dictionary else {"error":ERR_PARSE_ERROR,"payload":{}}
		_check(decoded_remaining.error == OK and decoded_remaining.payload.get("values") is Array,"checkpoint has an exact encoded remaining-time record")
		if decoded_remaining.error == OK and decoded_remaining.payload.get("values") is Array:
			exact_remaining = decoded_remaining.payload.values
	var clocks: Array[Dictionary] = []
	var slots: Array = world.powers.get("loadout", {}).get("slots", [])
	for slot: int in range(slots.size()):
		var remaining: float = SpecialPowers.remaining(world.powers,world.elapsed,slot)
		clocks.append({"slot":slot,"ability_id":slots[slot],"remaining":remaining,"event":SpecialPowers.event_at(world.powers,slot)})
		if slot < exact_remaining.size():
			_check(remaining == float(exact_remaining[slot]), "slot %d restores its own exact encoded remaining time" % slot)
		elif expected.get("power_remaining") is Array and slot < expected.power_remaining.size():
			_check(remaining == float(expected.power_remaining[slot]), "slot %d restores its own exact remaining time" % slot)
	var magazines: Array[Dictionary] = []
	var partial: bool = false
	for actor: FieldActor in world.survivors:
		if actor.magazine == null:
			continue
		var value: Dictionary = actor.magazine.snapshot()
		magazines.append({"member_id":actor.member_id,"value":value,"hash":RecordEncoding.fingerprint(value)})
		partial = partial or (actor.magazine.reloading and actor.magazine.remaining > 0.0 and actor.magazine.remaining < actor.magazine.seconds())
		for prior: Dictionary in expected.get("magazines", []):
			if int(prior.get("member_id",0)) == actor.member_id:
				_check(RecordEncoding.fingerprint(value) == prior.get("hash"), "member %d restores exact partial magazine" % actor.member_id)
	if "--resume-legacy" not in OS.get_cmdline_user_args():
		_check(EconomyBuildV1.enabled(camp) and slots.size() == 3, "M48 representative restores all three frozen slots")
		_check([SpecialPowers.SPEED,SpecialPowers.FREEZE,SpecialPowers.SUPPRESSION].all(func(id: String) -> bool: return id in slots)
			and clocks.size() == 3 and clocks.all(func(clock: Dictionary) -> bool: return clock.remaining > 0.0 and not clock.event.is_empty()),
			"three independently consumed continuing effects remain simultaneously active")
		_check(partial, "representative has an actually incomplete frozen reload")
	_write("restored-world.json", {"scope":"REAL_PATH_BOUND_CHECKPOINT","source":expected_path,"source_pid":expected.pid,"pid":OS.get_process_id(),"fingerprint":actual_hash,"world":actual,"clocks":clocks,"magazines":magazines,"partial_reload":partial,"receipt":recovered.hash})
	await _shot("restored-three-effects-and-reload")
	await _unpause(world)
	await _finish_outing(world)
	var final: Dictionary = app.camp_snapshot()
	_check(not app._progress_blocked and not app._progress_dirty and int(final.settled_sorties) == int(camp.settled_sorties)+1,
		"restored world completes the original bus return and exactly one confirmed settlement")
	_write("resume-return.json", {"source":expected_path,"source_pid":expected.pid,"pid":OS.get_process_id(),"before":RecordEncoding.fingerprint(camp),"after":RecordEncoding.fingerprint(final),"camp":final,"returns":route})
	if "--resume-finale" in OS.get_cmdline_user_args():
		var inventory: Array = app.camp_snapshot().weapons
		for gun: String in ["shotgun_v1","long_rifle"]:
			var matches: Array = inventory.filter(func(item: Dictionary) -> bool: return EconomyBuildV1.crafted(item) and item.weapon_id == gun)
			_check(matches.size() == 1,"retained normal management instance is unambiguous: " + gun)
			if matches.size() == 1:
				var member_id: int = 1 if gun == "shotgun_v1" else 2
				if WeaponInventory.for_member(app.camp_snapshot(),member_id).instance_id != matches[0].instance_id:
					await _equip_weapon_ui(matches[0].instance_id,member_id)
				else:
					_check(true,"normal crafted loadout retained across the exact checkpoint: " + gun)
		await _finish_campaign("C-management")
		var healing: Array = expected.get("previous_healing",[]).duplicate(true)
		healing.append_array(_management_healing())
		_check(healing.any(func(event: Dictionary) -> bool: return float(event.get("facts",{}).get("amount",0)) > 60.0 and float(event.get("facts",{}).get("amount",0)) <= 70.0),"normal strengthened medical pack accepts healing beyond its old sixty-HP cap")
		_write("management-effects.json",{"healing":healing,"reports":reports,"economy":app.camp_snapshot().journey.campaign.economy})
