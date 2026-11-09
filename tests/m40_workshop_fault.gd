extends "res://tests/campaign_flow.gd"
## Each failure starts from the same confirmed workshop camp with one toolbox.
## Use --flow-resume and sibling fault-write, fault-publish, fault-recover outputs.

func _journey() -> void:
	_check(false, "workshop fault proof requires the confirmed common camp")


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked, "normal Continue opened a confirmed camp")
	if not app.camp_scene.is_visible_in_tree() or app._progress_blocked:
		return
	match output.get_file():
		"fault-write":
			await _fault_edit(false)
		"fault-publish":
			await _fault_edit(true)
		"fault-recover":
			_recover_publish()
		_:
			_check(false, "recognized workshop fault stage")


func _fault_edit(lose_ack: bool) -> void:
	var before: Dictionary = app.camp_snapshot()
	var item: Dictionary = WeaponInventory.for_member(before, 1)
	var identity: String = item.get("instance_id", "")
	var mod: String = WorkshopV1.QUICK if lose_ack else WorkshopV1.EXTENDED
	var prior: Dictionary = app.progress_session._transaction.recover()
	_check(prior.error == OK and before.day == 4 and WorkshopV1.tools(before) == 1
		and WorkshopV1.mod_problem(before, identity, mod).is_empty(), "common day-four camp has exactly one available toolbox and the original ready carbine")
	if prior.error != OK or WorkshopV1.tools(before) != 1 or not WorkshopV1.mod_problem(before, identity, mod).is_empty():
		return
	_negative_cases(before, identity)
	await _tap(app.camp_scene.hotspots[&"weapons"])
	var panel: LoadoutPanel = app.loadout_panel
	if not _select_instance(panel, identity):
		return
	await _tap(panel.workshop_buttons[mod])
	_check(panel.workshop_confirmation.visible and panel.workshop_confirmation.dialog_text.contains("8 币"),
		"original workshop confirmation shows the fixed cost")
	var injected: Dictionary = {"publications":0, "failures":0}
	app.progress_session.fault_hook = func(point: String) -> Error:
		if point == "after_record_publish":
			injected.publications += 1
		if (lose_ack and point == "after_record_publish" and injected.publications == 2) \
				or (not lose_ack and point == "before_camp_write"):
			injected.failures += 1
			return ERR_CANT_CREATE
		return OK
	await _tap(panel.workshop_confirmation.get_ok_button())
	app.progress_session.fault_hook = Callable()
	var edit_id: String = app.progress_session._pending_edit
	var durable: Dictionary = app.progress_session._transaction.recover()
	var request: Dictionary = {"kind":mod, "member_id":0, "value":identity}
	_check(injected.failures == 1 and not edit_id.is_empty() and app._progress_blocked and app._progress_dirty,
		"the injected error leaves one unresolved edit and blocks other changes")
	_check(TransactionReceipt.same(before, app.camp_snapshot()) and panel.power_panel.retry_button.is_visible_in_tree(),
		"visible resources and instance remain unchanged until acknowledgement")
	_check(durable.error == OK and durable.receipt.transaction_id == edit_id
		and TransactionReceipt.same(durable.receipt.rules.request, request), "durable edit identity matches the retained request")
	if durable.error != OK:
		return
	var disk: Dictionary = app.progress_session._transaction._save.read_transaction_exact()
	_check(disk.error == OK, "durable camp remains readable")
	if disk.error != OK:
		return
	if lose_ack:
		_check(injected.publications == 2 and durable.state == "CAMP_EDITED" and durable.receipt.phase == "EDIT_COMMITTED"
			and int(durable.receipt.revision) == int(prior.receipt.revision) + 2, "ACK was lost only after the committed receipt became durable")
		_check(_one_install(before, disk.data, identity, mod)
			and TransactionReceipt.same(disk.data, TransactionReceipt.camp(durable.receipt)), "disk already contains exactly one debit and installation")
		_write("lost-edit-ack.json", _proof(before, disk.data, identity, mod, durable))
		return

	_check(injected.publications == 1 and durable.state == "EDIT_READY" and durable.receipt.phase == "EDIT_READY"
		and int(durable.receipt.revision) == int(prior.receipt.revision) + 1, "pre-write failure leaves only the prepared receipt")
	_check(TransactionReceipt.same(before, disk.data), "pre-write failure leaves camp bytes at the confirmed base")
	app.install_workshop_mod(identity, WorkshopV1.QUICK)
	_check(app.progress_session._pending_edit == edit_id and TransactionReceipt.same(before, app.camp_snapshot())
		and panel.workshop_buttons[WorkshopV1.QUICK].disabled, "alternate plan cannot replace or bypass the pending edit")
	await _tap(panel.power_panel.retry_button)
	var after: Dictionary = app.camp_snapshot()
	var committed: Dictionary = app.progress_session._transaction.recover()
	_check(committed.error == OK and committed.receipt.phase == "EDIT_COMMITTED"
		and committed.receipt.transaction_id == edit_id and int(committed.receipt.revision) == int(durable.receipt.revision) + 1
		and not app._progress_blocked and not app._progress_dirty, "normal retry commits the original request ID once")
	_check(_one_install(before, after, identity, mod), "retry debits exactly one toolbox and 8 coins, with no item provenance change")
	if committed.error != OK:
		return
	_repeat_commit(committed, edit_id, after)
	_reject_forged_edit(committed.receipt)
	_write("retry-edit.json", _proof(before, after, identity, mod, committed))
	await _transfer(panel, identity, mod)


func _recover_publish() -> void:
	var path: String = output.get_base_dir().path_join("fault-publish/lost-edit-ack.json")
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(expected is Dictionary and not expected.is_empty(), "the previous process recorded a committed edit with lost ACK")
	if not expected is Dictionary or expected.is_empty():
		return
	var after: Dictionary = app.camp_snapshot()
	var durable: Dictionary = app.progress_session._transaction.recover()
	_check(expected.pid != OS.get_process_id() and durable.error == OK and durable.receipt.phase == "EDIT_COMMITTED"
		and durable.receipt.transaction_id == expected.edit_id and durable.hash == expected.receipt_hash,
		"fresh process Continue acknowledges the same committed receipt without publishing a new edit")
	if durable.error != OK:
		return
	var before: Dictionary = durable.receipt.base
	var identity: String = expected.instance_id
	var mod: String = expected.mod
	_check(TransactionReceipt.legacy_fingerprint(after) == expected.camp_hash
		and TransactionReceipt.same(after, TransactionReceipt.camp(durable.receipt)) and _one_install(before, after, identity, mod),
		"recovered camp preserves the exact single installation, balance, tools and spending")
	_repeat_commit(durable, expected.edit_id, after)
	_reject_forged_edit(durable.receipt)
	_write("recovered-edit.json", _proof(before, after, identity, mod, durable))


func _negative_cases(camp: Dictionary, identity: String) -> void:
	var request: Dictionary = {"kind":WorkshopV1.EXTENDED, "member_id":0, "value":identity}
	var other: int = camp.weapons.find_custom(func(item: Dictionary) -> bool: return item.weapon_id == "long_rifle")
	_check(other >= 0 and WorkshopV1.mod_problem(camp, camp.weapons[other].instance_id, WorkshopV1.EXTENDED) == "请选择一把卡宾枪",
		"owned long rifle does not accept this modification")
	var poor: Dictionary = camp.duplicate(true)
	poor.cash = 7
	_check(WorkshopV1.mod_problem(poor, identity, WorkshopV1.EXTENDED) == "还差 1 币"
		and WorkshopV1.install(poor, identity, WorkshopV1.EXTENDED).is_empty(), "coins below eight cannot install")
	var empty: Dictionary = camp.duplicate(true)
	empty.journey.campaign.workshop.tools.clear()
	_check(WorkshopV1.mod_problem(empty, identity, WorkshopV1.EXTENDED) == "需要工具箱 ×1"
		and WorkshopV1.install(empty, identity, WorkshopV1.EXTENDED).is_empty(), "no toolbox cannot install")
	var damaged: Dictionary = camp.duplicate(true)
	WeaponInventory.find(damaged, identity).condition = "damaged"
	_check(WorkshopV1.mod_problem(damaged, identity, WorkshopV1.EXTENDED) == "先维修这把卡宾枪"
		and WorkshopV1.install(damaged, identity, WorkshopV1.EXTENDED).is_empty(), "damaged carbine cannot install")
	var old: Dictionary = camp.duplicate(true)
	old.journey.campaign.erase("workshop")
	_check(CampEdit.propose(old, request).is_empty(), "camp without the M40 marker rejects the edit")
	var forged: Dictionary = camp.duplicate(true)
	forged.journey.campaign.workshop.tools[0].site_id = "cash"
	_check(not TransactionReceipt.camp_problem(forged).is_empty() and CampEdit.propose(forged, request).is_empty(),
		"forged primary-site toolbox does not authorize a modification")
	var repeated: Dictionary = camp.duplicate(true)
	repeated.journey.campaign.workshop.tools.append(repeated.journey.campaign.workshop.tools[0].duplicate(true))
	_check(not TransactionReceipt.camp_problem(repeated).is_empty(), "same source cannot supply a second toolbox")


func _reject_forged_edit(receipt: Dictionary) -> void:
	var forged: Dictionary = receipt.duplicate(true)
	var installed: Dictionary = forged.envelope.result.journey.campaign.workshop.tools[0]
	installed.mod = WorkshopV1.QUICK if installed.mod == WorkshopV1.EXTENDED else WorkshopV1.EXTENDED
	forged.envelope.after_hash = SurvivalContracts.fingerprint(forged.envelope.result)
	_check(not TransactionReceipt.problem(forged).is_empty(), "rehashing a different modification cannot change the confirmed edit")


func _repeat_commit(committed: Dictionary, edit_id: String, after: Dictionary) -> void:
	var repeated: Dictionary = app.progress_session._transaction.commit_edit(edit_id)
	_check(repeated.error == OK and repeated.hash == committed.hash
		and TransactionReceipt.same(TransactionReceipt.camp(repeated.receipt), after)
		and TransactionReceipt.same(app.camp_snapshot(), after), "repeating the exact committed edit ID has no second effect")


func _transfer(panel: LoadoutPanel, identity: String, mod: String) -> void:
	var before: Dictionary = app.camp_snapshot()
	var other: Dictionary = WeaponInventory.for_member(before, 2)
	if other.is_empty() or not WeaponInventory._living(before, 2):
		return
	if not _select_instance(panel, identity):
		return
	await _tap(panel.equip_by_id[2])
	var after: Dictionary = app.camp_snapshot()
	_check(WeaponInventory.for_member(after, 2).instance_id == identity
		and WorkshopV1.mod_for(after, identity) == mod and WorkshopV1.mod_for(after, other.instance_id).is_empty()
		and after.cash == before.cash and WorkshopV1.tools(after) == WorkshopV1.tools(before)
		and after.camp_spending == before.camp_spending, "normal transfer moves the installed instance with no additional fee")
	_write("transferred-edit.json", {"instance_id":identity,"owner":WeaponInventory.owner(after, identity),
		"mod":WorkshopV1.mod_for(after, identity),"other_instance_id":other.instance_id,"other_mod":WorkshopV1.mod_for(after, other.instance_id)})


func _select_instance(panel: LoadoutPanel, identity: String) -> bool:
	for index: int in range(panel.items.item_count):
		if panel.items.get_item_metadata(index) == identity:
			panel.items.select(index)
			panel._select(index)
			return true
	_check(false, "loadout list exposes original carbine identity")
	return false


func _one_install(before: Dictionary, after: Dictionary, identity: String, mod: String) -> bool:
	return WorkshopV1.tools(before) == 1 and WorkshopV1.tools(after) == 0 \
		and after.cash == before.cash - 8 and after.camp_spending == before.camp_spending + 8 \
		and after.day == before.day and after.settled_sorties == before.settled_sorties \
		and WorkshopV1.mod_for(after, identity) == mod \
		and WorkshopV1.mod_problem(after, identity, mod) == "这把卡宾枪已改装" \
		and CampEdit.propose(after, {"kind":mod, "member_id":0, "value":identity}).is_empty() \
		and TransactionReceipt.same(WeaponInventory.find(before, identity), WeaponInventory.find(after, identity))


func _proof(before: Dictionary, after: Dictionary, identity: String, mod: String, durable: Dictionary) -> Dictionary:
	return {"pid":OS.get_process_id(),"edit_id":durable.receipt.transaction_id,"receipt_hash":durable.hash,
		"receipt_phase":durable.receipt.phase,"camp_hash":TransactionReceipt.legacy_fingerprint(after),
		"instance_id":identity,"mod":mod,"before_cash":before.cash,"after_cash":after.cash,
		"before_tools":WorkshopV1.tools(before),"after_tools":WorkshopV1.tools(after),
		"before_spending":before.camp_spending,"after_spending":after.camp_spending}
