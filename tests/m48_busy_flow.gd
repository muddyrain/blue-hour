extends "res://tests/m48_campaign_flow.gd"
## Real recovered camp; directed duplicate dispatch while the native wait frame is visible.
func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	var before: Dictionary = app.camp_snapshot()
	var request: Dictionary = EconomyBuildV1.request(before,"build","workshop","",String(before.profile_id)+":edit:"+RunSave.new_profile_id())
	var expected: Dictionary = CampEdit.propose(before,request)
	_check(not expected.is_empty(),"genuine confirmed camp qualifies for the busy-state build")
	if expected.is_empty(): return
	app.open_supplies()
	last_tap_usec = Time.get_ticks_usec()
	app.confirm_economy_edit(request)
	_check(app._camp_commit_busy and TransactionReceipt.same(before,app.camp_snapshot()),"pending operation exposes the unchanged confirmed camp")
	app.confirm_economy_edit(request)
	app._leave_supplies_for(&"camp")
	_check(app.supply_panel.visible and app._camp_commit_busy,"duplicate dispatch and back cannot replace an in-flight operation")
	await RenderingServer.frame_post_draw
	_check(app._camp_commit_busy and app.supply_panel._status.text.contains("正在保存"),"a real native waiting frame renders before durable work")
	var first_paint_usec: int = Time.get_ticks_usec()-last_tap_usec
	for index: int in range(30):
		if not app._camp_commit_busy: break
		await _frame()
	_check(not app._camp_commit_busy and not app._progress_blocked and TransactionReceipt.same(expected,app.camp_snapshot()),"one original proposal is acknowledged after the waiting frame")
	var head: Dictionary = app.progress_session._transaction.recover()
	_check(head.error == OK and head.receipt.phase == "EDIT_COMMITTED" and app.camp_snapshot().journey.campaign.economy.edits.size() == before.journey.campaign.economy.edits.size()+1,"duplicate input produces exactly one durable build and debit")
	_write("busy.json",{"scope":"REAL_CAMP_DIRECTED_DUPLICATE_DISPATCH_NATIVE_WAIT_FRAME","first_paint_usec_including_capture":first_paint_usec,"request":request,"before":RecordEncoding.fingerprint(before),"after":RecordEncoding.fingerprint(app.camp_snapshot()),"receipt":head.hash,"feedback":feedback_paints})
	await _tap(app.supply_panel.back_button)

	app.open_loadout()
	var loadout_before: Dictionary = app.camp_snapshot()
	var investment: Dictionary = {"kind":"build_invest","member_id":0,"value":BuildState.investment_value(loadout_before,"next_slot")}
	var loadout_expected: Dictionary = CampEdit.propose(loadout_before,investment)
	_check(not loadout_expected.is_empty(),"real funds support an independent slot investment")
	if loadout_expected.is_empty(): return
	last_tap_usec = Time.get_ticks_usec()
	app.invest_build(investment.value)
	_check(app._camp_commit_busy,"loadout investment enters the rendered wait phase")
	app.equip_build_item(0,"")
	_check(TransactionReceipt.same(loadout_before,app.camp_snapshot()),"another legal passive change cannot overtake the frozen purchase")
	await RenderingServer.frame_post_draw
	for index: int in range(30):
		if not app._camp_commit_busy: break
		await _frame()
	_check(not app._camp_commit_busy and not app._progress_blocked and TransactionReceipt.same(loadout_expected,app.camp_snapshot()),"slot purchase commits exactly once while its original passive stays equipped")
	_write("busy-loadout.json",{"scope":"REAL_CAMP_DIRECTED_CROSS_EDIT_REENTRY","before":RecordEncoding.fingerprint(loadout_before),"after":RecordEncoding.fingerprint(app.camp_snapshot()),"request":investment,"feedback":feedback_paints})
	await _tap(app.loadout_panel.back_button)
