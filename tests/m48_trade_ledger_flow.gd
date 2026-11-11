extends "res://tests/m48_campaign_flow.gd"
## Normal UI edits only, starting from the original restored common profile.
## --flow-resume --trade-common=/absolute/repo/.local/.../setup/common.json
## Independent PID: --flow-resume --trade-readback=/absolute/.../trade-proof.json
## Exact proof stores each complete resulting camp once; the preceding row is its before-state.

var trade_steps: Array[Dictionary] = []
var trade_origin: Dictionary = {}
var trade_crafted: String = ""
var trade_repaired: String = ""
var trade_manifest: Dictionary = {}


func _journey() -> void:
	_check(false, "trade ledger requires --flow-resume at the original bound common camp")


func _resume() -> void:
	var readback_path: String = _argument("--trade-readback=")
	var prior: Dictionary = {}
	if not readback_path.is_empty():
		prior = _read_trade_exact(readback_path)
		if prior.is_empty(): return
		trade_manifest = _source_manifest(String(prior.profile_path), String(prior.journal_directory))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(not app._progress_blocked and not app._progress_dirty and app.expedition == null
		and EconomyBuildV1.enabled(app.camp_snapshot()), "cold normal Continue opens a confirmed M48 camp")
	if app._progress_blocked or app._progress_dirty or app.expedition != null: return
	if not readback_path.is_empty():
		_cold_trade_readback(prior, readback_path)
		return
	var common_path: String = _argument("--trade-common=")
	if common_path.is_empty(): common_path = output.get_base_dir().path_join("setup/common.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(common_path)) if FileAccess.file_exists(common_path) else null
	_check(common_path.is_absolute_path() and "/.local/" in common_path and parsed is Dictionary
		and parsed.get("camp") == RecordEncoding.fingerprint(app.camp_snapshot()), "trade route starts at the exact retained common camp")
	if not parsed is Dictionary or parsed.get("camp") != RecordEncoding.fingerprint(app.camp_snapshot()): return
	trade_origin = app.camp_snapshot().duplicate(true)
	_check(trade_origin.cash == 72 and EconomyBuildV1.tools(trade_origin) == 4
		and EconomyBuildV1.level(trade_origin, "workshop") == 0, "actual common sources provide 72 cash and four unspent tools before construction")
	for item: Dictionary in trade_origin.weapons:
		if item.condition == "damaged" and WeaponInventory.owner(trade_origin, item.instance_id) == 0 \
				and item.weapon_id in ["fire_axe_v1", "rescue_hammer_v1", CombatEquipment.HAMMER_ID]:
			trade_repaired = item.instance_id
			break
	_check(not trade_repaired.is_empty(), "common camp retains a genuinely recovered damaged idle weapon")
	if trade_repaired.is_empty(): return
	if not await _trade_economy("build", "workshop"): return
	if not await _trade_economy("craft", "carbine"): return
	var created: Array = app.camp_snapshot().weapons.filter(func(item: Dictionary) -> bool:
		return EconomyBuildV1.crafted(item) and WeaponInventory.find(trade_origin, item.instance_id).is_empty())
	_check(created.size() == 1, "ordinary crafting produces exactly one new stable idle instance")
	if created.size() != 1: return
	trade_crafted = String(created[0].instance_id)
	if not await _trade_economy("basic_component", trade_crafted, "quick_v1"): return
	if not await _trade_economy("basic_component", trade_crafted, "reach_v1"): return
	_check(EconomyBuildV1.tools(app.camp_snapshot()) == 0, "building, crafting, install and replacement consume precisely the four real tools")
	if not await _trade_economy("sell", trade_crafted): return
	if not await _trade_repair(): return
	if not await _trade_economy("sell", trade_repaired): return
	var final: Dictionary = app.camp_snapshot()
	var transaction: RunTransaction = app.progress_session._transaction
	var confirmed: Dictionary = transaction.recover()
	var proof: Dictionary = {"kind":"M48_TRADE_LEDGER_V1", "pid":OS.get_process_id(),
		"scope":"normal native viewport UI; no resource, actor or world mutation",
		"common_source":common_path, "initial":trade_origin, "steps":trade_steps,
		"crafted_id":trade_crafted, "repaired_id":trade_repaired,
		"final_hash":RecordEncoding.fingerprint(final), "receipt_hash":confirmed.get("hash", ""),
		"profile_path":transaction._save.path, "journal_directory":transaction._journal.directory,
		"final_manifest":_source_manifest(transaction._save.path, transaction._journal.directory)}
	_audit_trade(proof, final)
	_write_trade_exact("trade-proof.json", proof)
	app.open_supplies()
	await _shot("trade-final-resource-ledger")
	await _tap(app.supply_panel.back_button)
	_check(_source_manifest(transaction._save.path, transaction._journal.directory) == proof.final_manifest,
		"viewing the final complete ledger does not mutate any authoritative source bytes")


func _trade_economy(op: String, target_id: String, choice: String = "") -> bool:
	var before: Dictionary = app.camp_snapshot().duplicate(true)
	var quote: Dictionary = EconomyBuildV1.offer(before, op, target_id, choice)
	if not await _economy(op, target_id, choice): return false
	return await _record_trade(before, quote, op, target_id, choice)


func _trade_repair() -> bool:
	var before: Dictionary = app.camp_snapshot().duplicate(true)
	var item: Dictionary = WeaponInventory.find(before, trade_repaired)
	var quote: Dictionary = WeaponInventory.repair_offer(before, item)
	quote.tools = 0
	quote.summary = "normal paid repair of the exact recovered idle instance"
	app.open_loadout(true)
	var armory: CampArmoryView = app.loadout_panel.armory
	armory.show_workshop(trade_repaired)
	await _hold(2)
	_check(item.get("condition") == "damaged" and not armory.repair_button.disabled,
		"normal workshop displays a paid repair for the real damaged idle weapon")
	if item.get("condition") != "damaged" or armory.repair_button.disabled: return false
	await _tap(armory.repair_button)
	_check(armory.confirmation.visible and int(armory._request.get("quote", -1)) == int(quote.cost),
		"visible paid repair preview uses the independently recomputed workshop discount")
	await _shot("trade-paid-repair-preview")
	await _tap(armory.confirmation.get_ok_button())
	await _tap(app.loadout_panel.back_button)
	return await _record_trade(before, quote, "repair", trade_repaired, "")


func _record_trade(before: Dictionary, quote: Dictionary, op: String, target_id: String, choice: String) -> bool:
	var after: Dictionary = app.camp_snapshot().duplicate(true)
	var transaction: RunTransaction = app.progress_session._transaction
	var receipt: Dictionary = transaction.recover()
	_check(receipt.error == OK and receipt.receipt.phase == "EDIT_COMMITTED"
		and not app._progress_blocked and not app._progress_dirty, "confirmed UI operation has a complete durable edit receipt: " + op)
	if receipt.error != OK or receipt.receipt.phase != "EDIT_COMMITTED": return false
	var request: Dictionary = receipt.receipt.rules.request.duplicate(true)
	var proposed: Dictionary = CampEdit.propose(before, request)
	_check(not proposed.is_empty() and RecordEncoding.fingerprint(proposed) == RecordEncoding.fingerprint(after),
		"original business replay reconstructs the complete actual result: " + op)
	_check(int(before.cash) - int(after.cash) == int(quote.cost)
		and before.food == after.food and before.day == after.day and before.settled_sorties == after.settled_sorties,
		"exact quote changes cash once while food and return counters stay fixed: " + op)
	var consumed: Array[String] = []
	for unit: Dictionary in EconomyBuildV1.state(after).tools:
		for old: Dictionary in EconomyBuildV1.state(before).tools:
			if old.id == unit.id and old.spent.is_empty() and not unit.spent.is_empty():
				consumed.append(unit.id)
				_check(unit.spent == receipt.receipt.transaction_id, "real consumed tool binds to this one confirmed operation")
	_check(consumed.size() == int(quote.get("tools", 0)), "actual per-unit tool consumption matches the quote: " + op)
	var sources_before: Dictionary = _source_manifest(transaction._save.path, transaction._journal.directory)
	var repeated: Dictionary = transaction.commit_edit(receipt.receipt.transaction_id)
	var rejected: Dictionary = app.progress_session.edit(before, request)
	_check(repeated.error == OK and repeated.hash == receipt.hash and rejected.error != OK
		and CampEdit.propose(after, request).is_empty(), "same acknowledgment and stale request cannot repeat the trade: " + op)
	_check(RecordEncoding.fingerprint(app.camp_snapshot()) == RecordEncoding.fingerprint(after)
		and _source_manifest(transaction._save.path, transaction._journal.directory) == sources_before,
		"retry and rejected old preview preserve complete camp and source bytes: " + op)
	app.open_loadout(true)
	await _hold(2)
	await _tap(app.loadout_panel.back_button)
	_check(RecordEncoding.fingerprint(app.camp_snapshot()) == RecordEncoding.fingerprint(after)
		and _source_manifest(transaction._save.path, transaction._journal.directory) == sources_before,
		"reopening ordinary management cannot grant or spend again: " + op)
	trade_steps.append({"index":trade_steps.size(), "op":op, "target":target_id, "choice":choice,
		"request":request, "quote":quote, "before_hash":RecordEncoding.fingerprint(before),
		"after_hash":RecordEncoding.fingerprint(after), "camp":after,
		"cash_before":before.cash, "cash_after":after.cash,
		"tools_before":EconomyBuildV1.tools(before), "tools_after":EconomyBuildV1.tools(after),
		"consumed_tool_ids":consumed, "receipt_hash":receipt.hash,
		"revision":receipt.receipt.revision, "transaction_id":receipt.receipt.transaction_id,
		"repeat_receipt_hash":repeated.get("hash", ""), "stale_request_error":rejected.error,
		"source_manifest":sources_before})
	_write_trade_exact("trade-progress.json", {"initial":trade_origin, "steps":trade_steps})
	return not app._progress_blocked and not app._progress_dirty


func _audit_trade(proof: Dictionary, final: Dictionary) -> void:
	var previous: Dictionary = proof.initial
	var total_cost: int = 0
	var revenue: int = 0
	var consumed: Array[String] = []
	var operations: Array[String] = []
	for step: Dictionary in proof.steps:
		operations.append(step.op)
		_check(step.before_hash == RecordEncoding.fingerprint(previous)
			and step.after_hash == RecordEncoding.fingerprint(step.camp)
			and RecordEncoding.fingerprint(CampEdit.propose(previous, step.request)) == step.after_hash,
			"complete archived step replays from the exact preceding camp: " + step.op)
		var cost: int = int(step.quote.cost)
		if cost > 0: total_cost += cost
		else: revenue -= cost
		for id: String in step.consumed_tool_ids:
			_check(id not in consumed, "one recovered tool appears in only one of build/craft/install/replace")
			consumed.append(id)
		previous = step.camp
	_check(operations == ["build", "craft", "basic_component", "basic_component", "sell", "repair", "sell"],
		"normal composite route covers craft-sale, repair-sale and actual component replacement")
	_check(proof.steps.size() == 7 and consumed.size() == 4 and EconomyBuildV1.tools(final) == 0,
		"all four real tools have exactly one irreversible consumer")
	_check(int(final.cash) == int(proof.initial.cash) - total_cost + revenue
		and int(final.camp_spending) - int(proof.initial.camp_spending) == total_cost
		and final.food == proof.initial.food and final.day == proof.initial.day,
		"complete confirmed cash flow equals purchases plus paid repair minus both true sale proceeds")
	var ledger: Dictionary = EconomyBuildV1.state(final)
	var sold: Array = ledger.sold.filter(func(row: Dictionary) -> bool:
		return row.instance.instance_id in [proof.crafted_id, proof.repaired_id])
	_check(sold.size() == 2, "both sold identities remain in immutable instance history")
	for row: Dictionary in sold:
		_check(row.price == EconomyBuildV1.sale_price(row.instance), "sold history retains the exact recomputed final instance price")
		_check(WeaponInventory.find(final, row.instance.instance_id).is_empty(), "sold instance is absent from active stock")
		if row.instance.instance_id == proof.crafted_id:
			_check(row.price == 3 and row.instance.economy.basic == "reach_v1" and row.instance.affixes == ["reach_v1"],
				"crafted sale returns only the level-one base price and preserves the final replacement component")
		else:
			_check(row.instance.condition == "ready", "paid repair is preserved in the subsequently sold original instance")
	for index: int in range(proof.steps.size()):
		var step: Dictionary = proof.steps[index]
		if step.op == "basic_component":
			var edits_for_id: Array = ledger.edits.filter(func(edit: Dictionary) -> bool: return edit.id == step.transaction_id)
			_check(edits_for_id.size() == 1 and edits_for_id[0].cost == 8 and edits_for_id[0].tools.size() == 1,
				"each replaced component retains its original consumed cash and tool receipt")
	_check(RecordEncoding.fingerprint(previous) == proof.final_hash and RecordEncoding.fingerprint(final) == proof.final_hash,
		"complete trade history converges on the one confirmed final fingerprint")
	_sold_operation_checks(final, String(proof.crafted_id))
	_sold_operation_checks(final, String(proof.repaired_id))


func _sold_operation_checks(camp: Dictionary, identity: String) -> void:
	_check(not WeaponInventory.equip(camp, 1, identity).has("data")
		and not WeaponInventory.repair(camp, identity).has("data"), "sold identity cannot be equipped or repaired")
	for op: String in ["sell", "upgrade_weapon", "basic_component", "combat_component", "magazine"]:
		var choice: String = "quick_v1" if op == "basic_component" else "pierce_v1" if op == "combat_component" else WorkshopV1.EXTENDED if op == "magazine" else ""
		var request: Dictionary = EconomyBuildV1.request(camp, op, identity, choice,
			String(camp.profile_id) + ":edit:" + RunSave.new_profile_id())
		_check(not EconomyBuildV1.offer(camp, op, identity, choice).available and CampEdit.propose(camp, request).is_empty(),
			"sold identity cannot enter a new economy operation: " + op)


func _cold_trade_readback(proof: Dictionary, source: String) -> void:
	var transaction: RunTransaction = app.progress_session._transaction
	var current: Dictionary = transaction.recover()
	var independent: Dictionary = ReceiptJournal.new(transaction._journal.directory).read_all()
	var final: Dictionary = app.camp_snapshot()
	_check(int(proof.pid) != OS.get_process_id() and transaction._save.path == proof.profile_path
		and transaction._journal.directory == proof.journal_directory, "independent PID restores the original path-bound trade profile")
	_check(current.error == OK and independent.error == OK and current.hash == proof.receipt_hash
		and independent.hash == proof.receipt_hash and RecordEncoding.fingerprint(final) == proof.final_hash,
		"cold readback authenticates the same complete final camp and journal receipt")
	_audit_trade(proof, final)
	for step: Dictionary in proof.steps:
		var record: Dictionary = transaction._journal._read_record(transaction._journal.directory.path_join("%08d/record.json" % int(step.revision)))
		_check(record.error == OK and record.hash == step.receipt_hash
			and RecordEncoding.fingerprint(TransactionReceipt.camp(record.receipt)) == step.after_hash
			and TransactionReceipt.same(record.receipt.rules.request, step.request),
			"cold read verifies the actual immutable committed receipt for " + step.op)
	_check(_source_manifest(transaction._save.path, transaction._journal.directory) == proof.final_manifest
		and trade_manifest == proof.final_manifest, "cold Continue and every validation preserve all original camp, backup, binding and journal bytes")
	_write_trade_exact("trade-readback.json", {"source":source, "prior_pid":proof.pid, "pid":OS.get_process_id(),
		"camp_hash":RecordEncoding.fingerprint(final), "receipt_hash":current.get("hash", ""),
		"manifest":_source_manifest(transaction._save.path, transaction._journal.directory)})


func _source_manifest(profile_path: String, journal_path: String) -> Dictionary:
	var result: Dictionary = {}
	for path: String in [profile_path, profile_path + ".bak", profile_path + ".txn/binding.json"]:
		if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	if DirAccess.dir_exists_absolute(journal_path):
		var folders: PackedStringArray = DirAccess.get_directories_at(journal_path)
		folders.sort()
		for folder: String in folders:
			var path: String = journal_path.path_join(folder).path_join("record.json")
			if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	return result


func _read_trade_exact(path: String) -> Dictionary:
	_check(path.is_absolute_path() and "/.local/" in path and FileAccess.file_exists(path), "trade proof is an existing isolated exact artifact")
	if not path.is_absolute_path() or "/.local/" not in path or not FileAccess.file_exists(path): return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		_check(false, "exact trade proof JSON parses")
		return {}
	var decoded: Dictionary = RecordEncoding.unpack(parser.data)
	_check(decoded.error == OK and decoded.get("payload", {}).get("kind") == "M48_TRADE_LEDGER_V1", "exact complete trade proof authenticates")
	if decoded.error != OK or decoded.get("payload", {}).get("kind") != "M48_TRADE_LEDGER_V1": return {}
	var proof: Dictionary = decoded.payload
	for key: String in ["profile_path", "journal_directory"]:
		if not proof.get(key) is String or not String(proof[key]).is_absolute_path() or "/.local/" not in String(proof[key]):
			_check(false, "trade proof source paths remain inside isolated profiles")
			return {}
	return proof


func _write_trade_exact(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output.path_join(name), FileAccess.WRITE)
	if file == null:
		_check(false, "trade evidence output is writable")
		return
	file.store_string(RecordEncoding.stringify(value))
	file.close()
