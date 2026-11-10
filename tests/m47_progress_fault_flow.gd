extends "res://tests/m47_run_replay_flow.gd"
## Directed faults in a real pump victory, followed by a cold process on the same isolated slot.


func _journey() -> void:
	match output.get_file():
		"t7-first":
			if _check_isolated("t7-first") and await _new_trip("scavenge"):
				await _finish_campaign("m47-directed-progress-faults")
		"t4-starvation":
			if _check_isolated("t4-starvation") and await _new_trip("support"):
				await _starvation()
		"t4-abandon":
			if _check_isolated("t4-abandon") and await _new_trip("support"):
				await _abandon()
		_:
			_check(false, "known directed specialty phase")


func _bank(world: Expedition) -> Dictionary:
	if not PumpStationAction.enabled(world.supply.generated):
		return await super._bank(world)
	await _extract(world)
	var progress: ProductionProgress = app.progress_session
	var pending: Dictionary = progress.inspect()
	var terminal: Dictionary = pending.get("receipt", {})
	_check(terminal.get("phase") == "RESULT_READY" and app.camp_snapshot().journey.campaign.outcome == "ACTIVE",
		"real terminal is a pending result before confirmation")
	if terminal.get("phase") != "RESULT_READY":
		return {}
	var confirm: Button = app.get_node("Interface/Screen/Result/Continue")
	progress.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_camp_write" else OK
	await _tap(confirm)
	var failed: Dictionary = progress.inspect()
	var path: String = _event_path(String(terminal.base.profile_id))
	_check(app._progress_blocked and failed.get("hash") == pending.hash and failed.receipt.phase == "RESULT_READY"
		and not FileAccess.file_exists(path), "failure before terminal write keeps the same ready receipt and awards no XP")
	_check(progress.refresh_catalog().get("reason") == "CATALOG_TERMINAL_PENDING", "catalog blocks replacement while the terminal is unconfirmed")
	progress.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_specialty_publish" else OK
	await _tap(confirm)
	var committed: Dictionary = progress.inspect()
	var before_publish: Dictionary = progress.catalog_state()
	_check(committed.state == "ENDED" and committed.receipt.phase == "COMMITTED"
		and before_publish.get("reason") == "CATALOG_SPECIALTY_PENDING" and not FileAccess.file_exists(path),
		"terminal is durable while specialty publication is pending")
	_check("待同步" in app._catalog_result_notice(app.camp_snapshot()),
		"terminal view reports specialty synchronization pending")
	progress.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point == "after_specialty_publish" else OK
	var after_publish: Dictionary = progress.refresh_catalog()
	_check(after_publish.get("reason") == "CATALOG_SPECIALTY_PENDING" and FileAccess.file_exists(path),
		"loss of specialty acknowledgment retains the published record")
	progress.fault_hook = Callable()
	var repeated: Dictionary = progress._transaction.commit(RunTransaction.token_for(committed.receipt))
	_check(repeated.error == OK and repeated.hash == committed.hash, "duplicate terminal confirmation reuses the original receipt")
	_write("faults.json", {"pid":OS.get_process_id(), "pending_hash":pending.hash, "receipt_hash":committed.hash,
		"xp_hash":FileAccess.get_sha256(path), "run_id":committed.receipt.base.profile_id,
		"before_publish":before_publish, "after_publish":after_publish})
	return committed


func _resume() -> void:
	if not _check_isolated("t7-readback"):
		return
	var prior: Dictionary = _read("t7-first/faults.json")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var progress: ProductionProgress = app.progress_session
	var restored: Dictionary = progress.inspect()
	var state: Dictionary = progress.catalog_state()
	var path: String = _event_path(prior.run_id)
	_check(OS.get_process_id() != int(prior.pid) and restored.state == "ENDED" and restored.hash == prior.receipt_hash
		and state.error == OK and state.specialties == {"scavenge":2, "firepower":0, "support":0}
		and state.specialization_result.delta == 2 and FileAccess.get_sha256(path) == prior.xp_hash,
		"independent process acknowledges the original published XP exactly once")
	_check(TransactionReceipt.same(state, progress.refresh_catalog()) and TransactionReceipt.same(state, progress.refresh_catalog()),
		"repeated catalog reads keep the same complete projection")
	if restored.state != "ENDED" or state.error != OK:
		return
	_thresholds()
	_reject_tampering(path, state, restored.hash)
	_write("readback.json", {"pid":OS.get_process_id(), "receipt_hash":restored.hash,
		"xp_hash":FileAccess.get_sha256(path), "projection":progress.refresh_catalog()})
	await _check_archive(path, String(prior.run_id))


func _starvation() -> void:
	var first: Expedition = await _ordinary_supply()
	if first == null:
		return
	await _finish_outing(first)
	var second: Expedition = await _ordinary_supply()
	if second == null:
		return
	var units: Array[Expedition.SearchSite] = []
	for site: Expedition.SearchSite in second.sites:
		if site.kind == &"food" and site.reward == 2:
			units.assign([site])
			break
		if site.kind == &"food" and site.reward == 1 and units.size() < 2:
			units.append(site)
	var available: int = 0
	for site: Expedition.SearchSite in units:
		available += site.reward
	_check(available == 2, "a normal supply card has an exact two-ration route")
	if available != 2:
		return
	for site: Expedition.SearchSite in units:
		await _search(second, site)
	await _finish_outing(second)
	var prepared: Dictionary = app.camp_snapshot()
	_check(prepared.settled_sorties == 2 and prepared.food == 0 and prepared.journey.active_member_ids.size() == 2,
		"two distinct confirmed returns leave two living members and no food")
	if prepared.settled_sorties != 2 or prepared.food != 0:
		return
	var final: Expedition = await _ordinary_supply()
	if final == null:
		return
	final.command_move(final.layout.bus_door)
	await _until(final, func() -> bool: return final.elapsed >= final.tuning.bus_ready_seconds)
	final.request_bus_action()
	await _until(final, func() -> bool: return final.phase == Expedition.Phase.BOARDING)
	final.request_bus_gather()
	await _until(final, func() -> bool: return final.phase == Expedition.Phase.FINISHED)
	for tick: int in range(1800):
		if not final.bus_view.running():
			break
		final.step(STEP)
		if tick % 28 == 0:
			await _frame()
	var state: Dictionary = app.progress_session.inspect()
	var result: Dictionary = state.get("receipt", {}).get("envelope", {}).get("result", {})
	var projection: Dictionary = app.progress_session.catalog_state()
	_check(state.get("state") == "ENDED" and result.get("battle", {}).get("evacuated", false)
		and result.get("hunger", {}).get("victim_ids", []).size() == 2 and result.food.food_shortage == 2,
		"actual evacuation followed by original zero-ration settlement causes a true starvation wipe")
	_check(not final.layout.world_data.has("open_streets") or final.bus_view._entire_bus_outside(),
		"evacuated starvation still completes the original road exit")
	_check(projection.error == OK and projection.get("specialties", {}).get("support") == 1
		and projection.specialization_result.delta == 1 and projection.specialization_result.outcome == "DEFEAT",
		"the two earlier returns qualify starvation for one support XP")
	_write("starvation.json", {"returns":route, "last_action":final.supply.generated.id,
		"hunger":result.get("hunger", {}), "receipt":state.get("hash", ""), "progress":projection})


func _abandon() -> void:
	for count: int in range(2):
		var outing: Expedition = await _ordinary_supply()
		if outing == null:
			return
		await _collect(outing, 5)
		await _finish_outing(outing)
	var active: Expedition = await _ordinary_supply()
	if active == null:
		return
	var run_id: String = app.camp_snapshot().profile_id
	app.open_pause_menu()
	await _tap(app.pause_menu.buttons[2])
	await _tap(app.pause_menu.buttons[1])
	var state: Dictionary = app.progress_session.inspect()
	var projection: Dictionary = app.progress_session.refresh_catalog()
	_check(app.phase == app.Phase.TITLE and app.expedition == null and app._progress_blocked
		and String(state.get("reason", "")).begins_with("UNFINISHED_ACTION_POLICY_REQUIRED:"),
		"original pause/exit keeps abandonment as an unfinished action")
	_check(projection.error == OK and projection.specialties == SpecializationProgress.initial()
		and projection.specialization_result.is_empty() and not FileAccess.file_exists(_event_path(run_id)),
		"abandonment after two real returns grants no XP or unlocks")
	_write("abandon.json", {"returns":route, "state":state, "progress":projection})


func _thresholds() -> void:
	for plan: String in OpeningBuild.PLANS:
		var id: String = OpeningBuild.PLANS[plan].unlock_id
		for amount: int in [1, 2, 3, 4]:
			var experience: Dictionary = {"specialties":{plan:amount}}
			for receiving: String in OpeningBuild.PLANS:
				var expected: bool = amount >= (2 if plan == receiving else 4)
				_check((id in CatalogProgress.eligible_for(experience, receiving)) == expected,
					"pure threshold comparison %s %d → %s" % [plan, amount, receiving])


func _reject_tampering(path: String, expected: Dictionary, receipt_hash: String) -> void:
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(original.get_string_from_utf8()))
	if decoded.error != OK:
		_check(false, "the original specialty record decodes")
		return
	var event: Dictionary = decoded.payload
	var variants: Dictionary = {
		"outcome":event.merged({"outcome":"DEFEAT"}, true),
		"amount":event.merged({"delta":900}, true),
		"receipt":event.merged({"receipt":event.receipt.merged({"hash":"0".repeat(64)}, true)}, true),
		"repeated-return":event.merged({"returns":[event.returns[0], event.returns[0]]}, true),
	}
	var progress: ProductionProgress = app.progress_session
	for label: String in variants:
		var text: String = RecordEncoding.stringify(variants[label])
		if not _store(path, text.to_utf8_buffer()):
			break
		_store(output.path_join("forged-" + label + ".json"), text.to_utf8_buffer())
		var hash: String = FileAccess.get_sha256(path)
		_check(progress.refresh_catalog().get("reason") == "CATALOG_SPECIALTY_SOURCE" and FileAccess.get_sha256(path) == hash,
			"validly encoded forged %s is rejected and preserved" % label)
	var corrupt: PackedByteArray = "[]\n".to_utf8_buffer()
	if _store(path, corrupt):
		_store(output.path_join("corrupt-specialty.json"), corrupt)
		_check(progress.refresh_catalog().get("reason") == "CATALOG_EVENT_JSON" and FileAccess.get_file_as_bytes(path) == corrupt
			and progress.inspect().get("hash") == receipt_hash, "corrupt catalog bytes remain intact and the original journey remains readable")
	if not _store(path, original):
		return
	var duplicate: String = path.get_base_dir().path_join("specialty-" + RunSave.new_profile_id() + ".json")
	if _store(duplicate, original):
		_check(progress.refresh_catalog().get("reason") == "CATALOG_SPECIALTY_SOURCE_MISSING" and FileAccess.get_file_as_bytes(duplicate) == original,
			"duplicate publication under another identity cannot contribute XP")
		var evidence: String = output.path_join("duplicate-specialty.json")
		_check(DirAccess.rename_absolute(duplicate, evidence) == OK, "preserve the rejected duplicate as separate evidence")
	_check(TransactionReceipt.same(expected, progress.refresh_catalog()), "restoring exact source bytes recovers the original projection")


func _check_archive(path: String, run_id: String) -> void:
	app.return_to_title()
	if not await _new_trip("scavenge"):
		return
	var progress: ProductionProgress = app.progress_session
	var new_camp: Dictionary = app.camp_snapshot()
	var archived: String = app.progress_path + SpecializationProgress.ARCHIVE_PREFIX + run_id
	var preserved: String = output.path_join("retained-specialty.json")
	var expected: Dictionary = progress.refresh_catalog()
	_check(DirAccess.dir_exists_absolute(archived) and expected.error == OK and expected.specialties.scavenge == 2
		and OpeningBuild.eligible(new_camp) == [OpeningBuild.PLANS.scavenge.unlock_id],
		"normal next registration freezes the prior XP and preserves the exact old bound journal")
	if FileAccess.file_exists(preserved) or DirAccess.rename_absolute(path, preserved) != OK:
		_check(false, "the isolated probe retains the archived specialty file before simulating loss")
		return
	var blocked: Dictionary = progress.refresh_catalog()
	_check(blocked.get("reason") == "CATALOG_SPECIALTY_RECORD_MISSING" and not FileAccess.file_exists(path)
		and progress.inspect().get("state") == "CAMP" and OpeningBuild.eligible(app.camp_snapshot()) == OpeningBuild.eligible(new_camp),
		"missing archived XP blocks profile replacement and preserves the existing frozen journey")
	var restore: Error = DirAccess.copy_absolute(preserved, path)
	_check(restore == OK and TransactionReceipt.same(expected, progress.refresh_catalog()),
		"restoring the retained exact record returns the same cross-run projection")
	_write("archive-loss.json", {"reason":blocked.get("reason", ""), "archive":archived.get_file(),
		"event_hash":FileAccess.get_sha256(path), "frozen":OpeningBuild.eligible(new_camp)})


func _store(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "isolated fault fixture can open its own specialty record")
		return false
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	var same: bool = error == OK and FileAccess.get_file_as_bytes(path) == bytes
	_check(same, "isolated fault fixture writes exact requested bytes")
	return same


func _event_path(run_id: String) -> String:
	return (app.progress_path + ".catalog").path_join("specialty-" + run_id + ".json")


func _check_isolated(phase: String) -> bool:
	var path: String = app.progress_path.replace("\\", "/").simplify_path().to_lower()
	var root_path: String = ProjectSettings.globalize_path("res://.local/m47-run-replay-01/").replace("\\", "/").to_lower()
	var valid: bool = output.get_file() == phase and path.begins_with(root_path) \
		and app.progress_session._writer.owns(app.progress_path) and ProgressWriter._unlinked(path)
	_check(valid, "directed fault harness requires its own M47 isolated path and session writer")
	return valid
