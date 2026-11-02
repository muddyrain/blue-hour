class_name HungerPlaytest
extends SurvivalPilotPlaytest
## Natural trips use original values. Mixed/short-two are separately labelled synthetic fixtures.

var _hunger_case: String = "trip"
var _long_name: bool = false
var _packet_path: String = ""


func _run() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\","/").to_lower() or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hunger-case="):
			_hunger_case = arg.trim_prefix("--hunger-case=")
		if arg == "--hunger-map=market":
			_map = 1
		if arg == "--hunger-long-name":
			_long_name = true
		if arg.begins_with("--hunger-packet="):
			_packet_path = arg.trim_prefix("--hunger-packet=")
		if arg.begins_with("--p0d-barrier="):
			_barrier = arg.trim_prefix("--p0d-barrier=")
		if arg == "--migration-handshake":
			_handshake = true
	app.progress_session.fault_hook = _fault
	await _settle()
	if _hunger_case == "observe":
		_expect(app._progress_blocked and not app._requires_continue, "unsafe/incomplete or non-opt-in progress blocks before applying a camp")
		var original: String = _digest()
		app.open_expedition()
		_expect(app.expedition == null and _digest() == original, "blocked progress cannot revive an old camp or start a mission")
		await _capture("blocked.png")
	elif _hunger_case == "hold":
		_write(output_dir.path_join("barrier.json"),{"pid":OS.get_process_id(),"point":"hold"})
		while not FileAccess.file_exists(output_dir.path_join("release")):
			await get_tree().create_timer(0.03).timeout
	elif _hunger_case == "legacy-ready":
		await super._enter()
		_initial = app.camp_snapshot()
		_migration_case = "ready"
		await _normal_sortie()
	else:
		if _hunger_case in ["mixed","short-two"]:
			var empty: Dictionary = app.progress_session.inspect()
			if app.run_save.has_files() or empty.error != OK or empty.state != "EMPTY":
				push_error("Controlled fixture requires a new empty isolated profile; existing files preserved")
				get_tree().quit(2)
				return
			_expect(true, "controlled fixture only uses a new empty isolated profile")
			var fixture: Dictionary = app.camp_snapshot()
			fixture.food = 0
			if _hunger_case == "mixed":
				for member: Dictionary in fixture.crew:
					member.health = 4.0
			app._accept_transaction(app.progress_session.create(fixture),true)
			app._hunger_consented = true
			app.get_node("Interface/Screen/Brand").text = "受控夹具 / 非自然流程：食物0；混合死因为4HP"
		else:
			await _enter()
		_initial = app.camp_snapshot()
		_expect(app.hunger_trial and app._hunger_consented, "explicit UI opt-in enters the original transaction system")
		if _initial.settled_sorties == 0 and _hunger_case not in ["locked","mixed","short-two"]:
			_expect(_initial.food == 2 and _initial.cash == 53 and _initial.crew.all(func(row: Dictionary) -> bool: return row.health == 200) and _initial.journey.seed == "NONE", "normal200HP/food2/original weapons; no injected resources or rehearsal seed")
		if _long_name and _initial.journey.state == "ACTIVE":
			await _tap(app._roster_button)
			var id: int = int(_initial.journey.active_member_ids[0])
			await _tap(app.roster_panel.member_buttons[id-1])
			app.roster_panel.name_edit.text = "暮色归航试验同行者甲号员"
			await _tap(app.roster_panel.save_button)
			await _tap(app.roster_panel.back_button)
			_initial = app.camp_snapshot()
		await _capture("continued-camp.png")
		if _hunger_case in ["trip","mixed","short-two"]:
			await _hunger_sortie()
		elif _hunger_case == "contracts":
			_contract_checks()
		elif _hunger_case == "locked":
			_expect(app._progress_dirty and app._progress_blocked, "real Windows commit refusal leaves original READY and blocks camp")
			await _capture("locked-result.png")
		else:
			_expect(_hunger_case == "continue", "known hunger proof case")
			if _initial.journey.state == "FAILED":
				_expect(app.phase == app.Phase.RESULT and not app._pending_settlement, "fresh process keeps durable FAILED and shows terminal")
				app.open_expedition()
				_expect(app.expedition == null, "terminal cannot start another sortie")
				await _capture("terminal-reopened.png")
	await _hold(30)
	var state: Dictionary = app.progress_session.inspect()
	_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"checks":_checks,"failures":_failures,"case":_hunger_case,"camp":app.camp_snapshot(),"initial":_initial,"state":state.get("state"),"reason":state.get("reason",""),"receipt":state.get("receipt",{}),"confirmed_deaths":state.get("confirmed_deaths",[]),"reports":_reports,"events":_events,"visible_member_ids":app._camp_backdrop.visible_member_ids,"display":DisplayServer.get_name(),"window_size":DisplayServer.window_get_size(),"controlled_fixture":_hunger_case in ["mixed","short-two"],"input_layer":"real viewport events and original gameplay intentions, NOT OS input; mixed/short-two alone use explicitly synthetic initial values"})
	app.audio.shutdown()
	OS.delay_msec(150)
	get_tree().quit(0 if _failures == 0 else 1)


func _enter() -> void:
	if not app._requires_continue:
		await super._enter()
		return
	var before: String = _digest()
	await _tap(app._continue_button)
	_expect(app._hunger_confirmation.visible and app._requires_continue, "Continue requires separate policy consent, never starts a new journey")
	await _capture("continue-policy.png")
	await _tap(app._hunger_confirmation.get_cancel_button())
	_expect(not app._hunger_confirmation.visible and _digest() == before and app._requires_continue, "cancel policy closes Window and keeps exact progress and pending result")
	await _tap(app._continue_button)
	# AcceptDialog handles Escape before Viewport.push_input, in its native Window hook.
	# Do not pretend a viewport event verifies it; the explicit OS checklist retains Escape.
	await _tap(app._hunger_confirmation.get_ok_button())
	if _hunger_case != "locked":
		_expect(not app._progress_blocked and not app._requires_continue, "explicit Continue activates only the original frozen camp")


func _hunger_sortie() -> void:
	var before: Dictionary = app.camp_snapshot()
	await _open_map(_map)
	if app.expedition == null:
		return
	var sortie: Expedition = app.expedition
	_expect(sortie.hunger_trial and not sortie.battle_drill and sortie.drill_panel.buttons.is_empty(), "natural safe spawns and unchanged original AI; visible isolated policy without deployment cheats")
	var ids: Array[int] = []
	for actor: FieldActor in sortie.survivors:
		ids.append(actor.member_id)
	_expect(ids == before.journey.active_member_ids, "only actual living stable IDs deploy, no renumbering or revival")
	sortie.finished.connect(func(report: Dictionary) -> void: _reports.append(report.duplicate(true)))
	sortie.combat_feedback.connect(func(event: Dictionary) -> void: _events.append(event.duplicate(true)))
	await _ui_checks(sortie)
	sortie.request_search(&"cash")
	for frame: int in range(3600):
		if sortie.searched and sortie.kills > 0:
			break
		await _step(sortie)
	_expect(sortie.searched and sortie.kills > 0, "real navigation/search/AI/gunfire complete original mission")
	if _map == 1:
		sortie.request_search(&"food")
		for frame: int in range(3600):
			if sortie.search_site(&"food").searched:
				break
			await _step(sortie)
		_expect(sortie.search_site(&"food").searched, "actual food search produces original food reward")
	await _capture("search-combat.png")
	# Search/first defeat can finish before the original bus preparation timer.
	# Wait by stepping the real world; never bypass the timer or force engine state.
	for frame: int in range(1800):
		if sortie.elapsed >= sortie.tuning.bus_ready_seconds:
			break
		await _step(sortie)
	_expect(sortie.elapsed >= sortie.tuning.bus_ready_seconds, "original bus preparation completes before engine input")
	sortie._hud.view._bus_button.grab_focus()
	await _key_battle(KEY_ENTER)
	sortie._hud.view._bus_button.release_focus()
	_expect(sortie.phase == Expedition.Phase.ENGINE and not sortie.boarding_status().ordered, "engine never automatically recalls crew")
	if _hunger_case == "mixed":
		# Reuse the original visible rehearsal button and unmodified enemy/AI/damage gate.
		# This labelled controlled fixture is NOT the natural200HP/food2 proof.
		sortie.drill_panel.queue_free()
		sortie.battle_drill = true
		sortie.drill_panel = BattleDrillPanel.new()
		sortie.drill_panel.expedition = sortie
		sortie._hud.view.add_child(sortie.drill_panel)
		await _settle()
		sortie.drill_panel._status.text += "\n受控混合死因：4HP / 0粮 / 按钮近敌"
		await _capture("controlled-mixed.png")
		sortie.drill_panel.buttons[0].grab_focus()
		await _key_battle(KEY_ENTER)
		sortie.drill_panel.buttons[0].release_focus()
		var target: FieldActor = _actor(sortie,1)
		for frame: int in range(180):
			if target.health == 0:
				break
			await _step(sortie)
		_expect(target.health == 0 and target.permanent_death and target.damage_received == 4, "controlled original AI melee passes real persisted battle death gate")
	for frame: int in range(180):
		if sortie.phase == Expedition.Phase.BOARDING:
			break
		await _step(sortie)
	await _key_battle(KEY_SPACE)
	var clock: float = sortie.elapsed
	sortie._hud.view._bus_button.grab_focus()
	await _key_battle(KEY_ENTER)
	_expect(sortie.is_paused and sortie.elapsed == clock and sortie.boarding_status().ordered, "paused real keyboard gather freezes the clock")
	sortie._hud.view._bus_button.release_focus()
	await _key_battle(KEY_SPACE)
	for frame: int in range(3600):
		if sortie.phase == Expedition.Phase.FINISHED:
			break
		await _step(sortie)
	_expect(_reports.size() == 1 and _reports[0].evacuated and app.phase == app.Phase.RESULT, "one real EXTRACTED report reaches frozen settlement")
	var packet: Dictionary = app.progress_session.packet
	_expect(not packet.is_empty() and FrozenSettlement.validate(packet).is_empty(), "original strict frozen validator accepts full102 hunger packet")
	if packet.is_empty():
		return
	_write(output_dir.path_join("packet.json"),packet)
	var value: Dictionary = packet.envelope.result
	if _hunger_case == "mixed":
		_expect(value.food.ration_member_ids == [2] and value.deaths[0].cause == "BATTLE" and value.deaths[1].cause == "STARVATION", "same real sortie separates BATTLE/STARVATION and excludes battle dead from meal")
	if _hunger_case == "short-two":
		_expect(value.food.food_shortage == 2 and value.hunger.victim_ids == [1,2], "controlled zero-food meal loses two living people exactly once")
	_expect(value.scope == FrozenSettlement.HUNGER_PILOT and value.rules.hunger.source == "PROJECT_TEMP", "explicit policy and selection version frozen in transaction")
	for row: Dictionary in value.battle.member_results:
		var member: Dictionary = SurvivorRoster.member(value.camp.crew,int(row.id))
		_expect(member.service.damage_received == SurvivorRoster.member(before.crew,int(row.id)).service.damage_received + row.damage_received, "starvation never adds invented combat damage ID="+str(row.id))
	var body: Label = app.get_node("Interface/Screen/Result/Scroll/Body")
	await _settle()
	_expect("缺口" in body.text and "PROJECT_TEMP" in body.text and body.get_minimum_size().y <= body.size.y, "long Chinese and hunger ledger fit the real result control")
	await _capture("hunger-result.png")
	await _hold(60)
	if value.camp.journey.state == "ACTIVE":
		await _tap(app.get_node("Interface/Screen/Result/Continue"))
	else:
		_expect(app._battle_meta.state == "FAILED" and app._pending_settlement.is_empty(), "EXTRACTED can commit FAILED after final starvation")
	var after: Dictionary = app.camp_snapshot()
	_expect(TransactionReceipt.same(after,value.camp) and app.progress_session.inspect().state in ["CAMP","ENDED"], "camp exactly equals unique frozen after")
	var digest: String = _digest()
	app.return_to_title()
	app.return_to_title()
	_expect(TransactionReceipt.same(after,app.camp_snapshot()) and _digest() == digest, "repeat return never repeats death/day/food/reward")
	await _capture("returned-camp.png")


func _contract_checks() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_packet_path))
	_expect(FrozenSettlement.validate(packet).is_empty(), "original strict102 packet accepted before negative tests")
	var before: String = _digest()
	_expect(FrozenSettlement.prepare_survival_hunger(app.progress_session._transaction,packet).error == OK, "exact published packet retry accepted without recalculating victims")
	var tampered: Dictionary = packet.duplicate(true)
	tampered.envelope.result.hunger.victim_ids = []
	_expect(not FrozenSettlement.validate(tampered).is_empty(), "tampered frozen victim list rejected by original shared validator")
	_expect(FrozenSettlement.prepare_survival_hunger(app.progress_session._transaction,tampered).error != OK, "published transaction refuses tampered victim envelope even on retry")
	for kind: String in ["root","old-token","schema","policy","no-policy","gear","interruption","abandon"]:
		var value: Dictionary = packet.input.duplicate(true)
		match kind:
			"root": value.token.root_id = "12345678901234567890123456789012"
			"old-token": value.token.transaction_id = value.before.profile_id+":1"
			"schema": value.before.schema_version = 101
			"policy": value.rules.hunger.source = "LOCAL_VERIFIED"
			"no-policy": value.rules.hunger = {}
			"gear": value.rules.dead_equipment = {}
			"interruption": value.completion = "TECHNICAL_INTERRUPTION"
			"abandon": value.completion = "PLAYER_ABANDONED"
		value.token.base_hash = SurvivalContracts.fingerprint(value.before)
		value.token.rules_hash = SurvivalContracts.fingerprint(value.rules)
		_expect(not FrozenSettlement.compute(value).error.is_empty(), "strict102 isolated contract rejects "+kind)
	_expect(before == _digest(), "all rejected probes preserve camp, backup and journal head")


func _fault(point: String) -> Error:
	if _barrier == "ready-published" and point == "after_record_publish":
		var ready: Dictionary = ReceiptJournal.new(app.progress_path+".txn/journal").read_all()
		if ready.error == OK and ready.receipt.phase == "RESULT_READY":
			_write(output_dir.path_join("barrier-packet.json"),app.progress_session.packet)
	if _barrier == "starvation-confirmed" and point == "after_record_publish":
		var current: Dictionary = ReceiptJournal.new(app.progress_path+".txn/journal").read_all()
		if current.error == OK and current.receipt.phase == "DEATH_CONFIRMED" and current.receipt.deaths.any(func(row: Dictionary) -> bool: return row.death.cause == "STARVATION"):
			_write(output_dir.path_join("barrier.json"),{"pid":OS.get_process_id(),"point":_barrier})
			var deadline: int = Time.get_ticks_msec()+45000
			while Time.get_ticks_msec() < deadline:
				OS.delay_msec(10)
	return super._fault(point)
