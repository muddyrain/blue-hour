extends "res://tests/m48_campaign_flow.gd"
## Real recovered materials and path-bound isolated profiles. Only fault hooks are directed.

var fault_case: String = ""
var fault_point: String = ""
var fault_bank_active: bool = false
var fault_proof: Dictionary = {}


func _journey() -> void:
	_check(false, "fault phases require --flow-resume from the real common camp")


func _resume() -> void:
	fault_case = _argument("--flow-case=")
	fault_point = _argument("--flow-fault=")
	var readback_path: String = _argument("--flow-fault-readback=")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(not app._progress_blocked and EconomyBuildV1.enabled(app.camp_snapshot()), "cold process opens an authentic M48 isolated camp")
	if app._progress_blocked:
		return
	if not readback_path.is_empty():
		_cold_readback(readback_path)
		return
	_check(fault_case in ["sell", "build", "craft", "upgrade_weapon", "enhance", "return-auto"], "known targeted M48 operation")
	_check(fault_point in ["before_camp_write", "after_record_publish"], "known durable fault boundary")
	if fault_case not in ["sell", "build", "craft", "upgrade_weapon", "enhance", "return-auto"] or fault_point not in ["before_camp_write", "after_record_publish"]:
		return
	var common: Dictionary = _read("setup/common.json")
	_check(common.get("camp") == RecordEncoding.fingerprint(app.camp_snapshot()), "fault phase begins from the unchanged common camp and original bound path")
	route.assign(common.get("route", []))
	var request: Dictionary = await _prepare_case()
	if fault_case == "return-auto":
		await _return_auto()
	elif not request.is_empty():
		_fault_edit(request)
	_negative_camp_checks()
	fault_proof.route = route
	_write_exact("fault.json", fault_proof)


func _prepare_case() -> Dictionary:
	var camp: Dictionary = app.camp_snapshot()
	match fault_case:
		"sell":
			for item: Dictionary in camp.weapons:
				if WeaponInventory.owner(camp, item.instance_id) == 0:
					return _economy_request("sell", item.instance_id)
			_check(false, "real recovered idle weapon exists for sale fault")
		"build":
			if await _fund("build", "workshop"): return _economy_request("build", "workshop")
		"craft", "upgrade_weapon":
			if not await _fund("build", "workshop") or not await _economy("build", "workshop"): return {}
			if fault_case == "craft":
				if await _fund("craft", "carbine"): return _economy_request("craft", "carbine")
			else:
				var identity: String = await _craft_gun("carbine")
				if not identity.is_empty() and await _fund("upgrade_weapon", identity): return _economy_request("upgrade_weapon", identity)
		"enhance":
			for attempt: int in range(12):
				camp = app.camp_snapshot()
				var item_id: String = String(camp.journey.build.owned[0])
				if BuildState.investment_offer(camp, item_id).available:
					return {"kind":"build_invest", "member_id":0, "value":BuildState.investment_value(camp, item_id)}
				if not await _gather(): return {}
			_check(false, "normal resources can fund an owned passive enhancement")
	return {}


func _economy_request(op: String, target_id: String, choice: String = "") -> Dictionary:
	var camp: Dictionary = app.camp_snapshot()
	return EconomyBuildV1.request(camp, op, target_id, choice, String(camp.profile_id) + ":edit:" + RunSave.new_profile_id())


func _fault_edit(request: Dictionary) -> void:
	var before: Dictionary = app.camp_snapshot()
	var expected: Dictionary = CampEdit.propose(before, request)
	_check(not expected.is_empty(), "normal business proposal exists before injecting " + fault_case)
	if expected.is_empty(): return
	var progress: ProductionProgress = app.progress_session
	var injected: Dictionary = {"publishes":0, "failures":0}
	progress.fault_hook = func(point: String) -> Error:
		if point == "after_record_publish": injected.publishes += 1
		if point == fault_point and (point != "after_record_publish" or injected.publishes == 2):
			injected.failures += 1
			return ERR_CANT_CREATE
		return OK
	var failed: Dictionary = progress.edit(before, request)
	progress.fault_hook = Callable()
	var identity: String = progress._pending_edit
	var exposed: bool = app._accept_transaction(failed, true)
	var durable: Dictionary = progress._transaction.recover()
	var disk: Dictionary = progress._transaction._save.read_transaction_exact()
	var phase: String = "EDIT_READY" if fault_point == "before_camp_write" else "EDIT_COMMITTED"
	_check(injected.failures == 1 and failed.error != OK and not exposed and app._progress_blocked and app._progress_dirty,
		"injected fault reports a real pending edit without showing partial changes")
	_check(durable.get("receipt", {}).get("phase") == phase and disk.get("error") == OK and TransactionReceipt.same(disk.get("data", {}), before if fault_point == "before_camp_write" else expected),
		"disk and journal retain the exact expected fault phase")
	_check(TransactionReceipt.same(app.camp_snapshot(), before), "UI still exposes the original confirmed camp after the failed acknowledgment")
	var retried: Dictionary = progress.retry()
	_check(app._accept_transaction(retried, true), "retry acknowledges the original operation")
	var committed: Dictionary = progress._transaction.recover()
	var repeated: Dictionary = progress._transaction.commit_edit(identity)
	var journal: ReceiptJournal = ReceiptJournal.new(progress._transaction._journal.directory)
	var independently_read: Dictionary = journal.read_all()
	_check(committed.error == OK and repeated.error == OK and independently_read.error == OK and committed.hash == repeated.hash and committed.hash == independently_read.hash and committed.receipt.transaction_id == identity,
		"repeated confirmation and fresh journal object preserve the one edit receipt")
	_check(TransactionReceipt.same(expected, app.camp_snapshot()) and TransactionReceipt.same(expected, TransactionReceipt.camp(independently_read.receipt)),
		"money, tools, instances, facilities, and enhancement match the one pure proposal")
	var stale: Dictionary = progress.edit(before, request)
	_check(stale.error != OK and TransactionReceipt.same(expected, app.camp_snapshot()), "repeating a stale preview cannot debit or credit again")
	fault_proof = {"case":fault_case, "point":fault_point, "pid":OS.get_process_id(), "request":request, "edit_id":identity,
		"before":before, "expected":expected, "failed":_receipt_evidence(failed), "durable_after_failure":_receipt_evidence(durable), "disk_after_failure":_disk_evidence(disk),
		"receipt_hash":committed.hash, "camp_hash":RecordEncoding.fingerprint(expected), "independent_journal_hash":independently_read.hash,
		"journal_directory":progress._transaction._journal.directory, "profile_path":app.progress_path, "fault_count":injected.failures}


func _return_auto() -> void:
	for facility: String in ["supply", "workshop", "planning"]:
		if not await _fund("build", facility) or not await _economy("build", facility): return
	var world: Expedition = await _ordinary_supply()
	if world == null: return
	await _collect(world, 5)
	fault_bank_active = true
	await _finish_outing(world)
	fault_bank_active = false


func _bank(world: Expedition) -> Dictionary:
	if not fault_bank_active: return await super._bank(world)
	await _extract(world)
	var progress: ProductionProgress = app.progress_session
	var pending: Dictionary = progress._transaction.recover()
	_check(pending.get("receipt", {}).get("phase") == "RESULT_READY", "real outing is ready before automatic effects can be claimed")
	if pending.get("receipt", {}).get("phase") != "RESULT_READY": return {}
	var expected: Dictionary = pending.receipt.envelope.result.camp
	var token: Dictionary = RunTransaction.token_for(pending.receipt)
	var before: Dictionary = app.camp_snapshot()
	var injected: Dictionary = {"failures":0}
	progress.fault_hook = func(point: String) -> Error:
		if point == fault_point:
			injected.failures += 1
			return ERR_CANT_CREATE
		return OK
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	progress.fault_hook = Callable()
	var durable: Dictionary = progress._transaction.recover()
	var disk: Dictionary = progress._transaction._save.read_transaction_exact()
	_check(injected.failures == 1 and app._progress_blocked and disk.error == OK and TransactionReceipt.same(disk.data, before if fault_point == "before_camp_write" else expected),
		"automatic effects retain exact prewrite or committed disk state after injected fault")
	_check(TransactionReceipt.same(app.camp_snapshot(), before), "failed automatic-effect acknowledgment exposes no partial camp")
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var committed: Dictionary = progress._transaction.recover()
	var repeated: Dictionary = progress._transaction.commit(token)
	var journal: ReceiptJournal = ReceiptJournal.new(progress._transaction._journal.directory)
	var replay: Dictionary = journal.read_all()
	_check(committed.error == OK and committed.receipt.phase == "COMMITTED" and repeated.error == OK and replay.error == OK and committed.hash == repeated.hash and committed.hash == replay.hash and TransactionReceipt.same(expected, app.camp_snapshot()),
		"automatic food, repairs, and planning are committed exactly once across retry and replay")
	_check(EconomyBuildV1.result_problem(committed.receipt).is_empty(), "automatic results independently reconstruct from departure state and original report")
	fault_proof = {"case":fault_case, "point":fault_point, "pid":OS.get_process_id(), "before":before, "expected":expected,
		"ready_receipt":_receipt_evidence(pending), "durable_after_failure":_receipt_evidence(durable), "disk_after_failure":_disk_evidence(disk), "receipt_hash":committed.hash,
		"camp_hash":RecordEncoding.fingerprint(expected), "independent_journal_hash":replay.hash,
		"journal_directory":progress._transaction._journal.directory, "profile_path":app.progress_path, "fault_count":injected.failures}
	return committed


func _cold_readback(path: String) -> void:
	_check(path.is_absolute_path() and "/.local/" in path, "readback proof is an isolated local artifact")
	if not path.is_absolute_path() or "/.local/" not in path: return
	var parser: JSON = JSON.new()
	var parsed: bool = parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary
	_check(parsed, "exact fault proof contains a complete JSON packet")
	if not parsed: return
	var decoded: Dictionary = RecordEncoding.unpack(parser.data)
	_check(decoded.get("error") == OK, "exact fault proof decodes")
	if decoded.get("error") != OK: return
	var prior: Dictionary = decoded.payload
	var committed: Dictionary = app.progress_session._transaction.recover()
	var journal: ReceiptJournal = ReceiptJournal.new(app.progress_session._transaction._journal.directory)
	var replay: Dictionary = journal.read_all()
	_check(int(prior.pid) != OS.get_process_id() and committed.error == OK and replay.error == OK and committed.hash == prior.receipt_hash and replay.hash == prior.independent_journal_hash,
		"independent PID restores the original one receipt after the fault")
	_check(RecordEncoding.fingerprint(app.camp_snapshot()) == prior.camp_hash and TransactionReceipt.same(prior.expected, app.camp_snapshot()),
		"cold process preserves all exact balances, instances, facilities, and training")
	_write_exact("readback.json", {"prior_pid":prior.pid, "pid":OS.get_process_id(), "receipt_hash":committed.hash, "camp_hash":RecordEncoding.fingerprint(app.camp_snapshot())})


func _negative_camp_checks() -> void:
	var camp: Dictionary = app.camp_snapshot()
	var checks: Array[Dictionary] = []
	var bad: Dictionary = camp.duplicate(true)
	if not bad.journey.campaign.economy.tools.is_empty():
		bad.journey.campaign.economy.tools.append(bad.journey.campaign.economy.tools[0].duplicate(true))
		checks.append({"label":"duplicate recovered tool", "data":bad})
	bad = camp.duplicate(true)
	bad.journey.campaign.economy.tools.append({"id":"forged", "transaction_id":camp.last_settlement_id, "action_id":"0".repeat(64), "site_id":"cash", "ordinal":0, "spent":""})
	checks.append({"label":"unrecovered tool", "data":bad})
	for edit: Dictionary in camp.journey.campaign.economy.edits:
		if edit.op == "sell":
			bad = camp.duplicate(true)
			for row: Dictionary in bad.journey.campaign.economy.edits:
				if row.id == edit.id: row.cost -= 50
			checks.append({"label":"forged sale quote", "data":bad})
		if edit.tools.size() > 0:
			bad = camp.duplicate(true)
			for unit: Dictionary in bad.journey.campaign.economy.tools:
				if unit.id == edit.tools[0]: unit.spent = "forged-consumer"
			checks.append({"label":"tool consumed by another operation", "data":bad})
			break
	for item: Dictionary in camp.weapons:
		if EconomyBuildV1.crafted(item):
			bad = camp.duplicate(true)
			WeaponInventory.find(bad, item.instance_id).weapon_level = 5
			checks.append({"label":"cross-level without adjacent upgrades", "data":bad})
			bad = camp.duplicate(true)
			WeaponInventory.find(bad, item.instance_id).economy.edit_id = "forged"
			checks.append({"label":"forged craft origin", "data":bad})
			break
	if not camp.journey.campaign.economy.sold.is_empty():
		var sold: Dictionary = camp.journey.campaign.economy.sold[0].instance
		_check(CampEdit.propose(camp, {"kind":"equip", "member_id":1, "value":sold.instance_id}).is_empty(), "sold instance cannot equip")
		_check(CampEdit.propose(camp, {"kind":"repair", "member_id":0, "value":sold.instance_id}).is_empty(), "sold instance cannot repair")
		_check(CampEdit.propose(camp, _economy_request("sell", sold.instance_id)).is_empty(), "sold instance cannot sell again")
	for prior_return: Dictionary in camp.journey.campaign.economy.returns:
		if prior_return.planning.is_empty(): continue
		var absent: int = 0
		for identity: int in range(1, 6):
			if SurvivorRoster.member(camp.crew, identity).is_empty():
				absent = identity
				break
		if absent == 0: break
		bad = camp.duplicate(true)
		for forged_return: Dictionary in bad.journey.campaign.economy.returns:
			if forged_return.transaction_id != prior_return.transaction_id: continue
			var fake_before: Dictionary = {"id":TraitRules.IDS[TraitRules.role({"id":absent}) - 1], "level":1, "progress":0}
			var fake_after: Dictionary = fake_before.duplicate(true)
			fake_after.progress += int(forged_return.planning.points)
			fake_after.level = TraitRules.level_for(int(fake_after.progress))
			forged_return.planning = {"member_id":absent, "points":forged_return.planning.points, "before":fake_before, "after":fake_after}
			forged_return.planning_candidates = [{"member_id":absent, "trait":fake_before}]
		checks.append({"label":"planning for an unregistered historical target", "data":bad})
		break
	var mutation_index: int = 0
	for fixture: Dictionary in checks:
		var issue: String = SurvivalState.extended_problem(fixture.data)
		_check(not issue.is_empty(), "independent structural readback rejects " + fixture.label)
		fixture.issue = issue
		var invalid_path: String = output.path_join("negative-%02d/run.enemy-v1.json" % mutation_index)
		var store: RunSave = RunSave.new(invalid_path)
		store._enemy_format = true
		var write_error: Error = store._save_owned(fixture.data)
		_check(write_error != OK and not FileAccess.file_exists(invalid_path), "disk preflight rejects " + fixture.label)
		DirAccess.make_dir_recursive_absolute(invalid_path.get_base_dir())
		var file: FileAccess = FileAccess.open(invalid_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(fixture.data, "\t", true, true))
		file.close()
		var readback: Dictionary = store.read_transaction_exact()
		_check(readback.error != OK, "independent invalid file read rejects " + fixture.label)
		fixture.write_error = write_error
		fixture.read_error = readback.error
		fixture.read_reason = readback.get("reason", store.diagnostic)
		mutation_index += 1
	_write_exact("negative-camps.json", {"synthetic_mutations":true, "fixtures":checks})


func _write_exact(name: String, value: Dictionary) -> void:
	var packed: Dictionary = RecordEncoding.pack(value)
	_check(not packed.is_empty(), "exact evidence encodes a complete JSON value: " + name)
	if packed.is_empty(): return
	var file: FileAccess = FileAccess.open(output.path_join(name), FileAccess.WRITE)
	if file == null:
		_check(false, "exact evidence file is writable")
		return
	file.store_string(packed.text)
	file.close()


func _receipt_evidence(result: Dictionary) -> Dictionary:
	# Coordinator metadata contains integer-keyed lookup maps; the complete receipt is JSON.
	return {"error":result.get("error", ERR_FILE_CORRUPT), "reason":String(result.get("reason", "")),
		"hash":String(result.get("hash", "")), "receipt":result.get("receipt", {})}


func _disk_evidence(result: Dictionary) -> Dictionary:
	return {"error":result.get("error", ERR_FILE_CORRUPT), "reason":String(result.get("reason", "")),
		"data":result.get("data", {})}
