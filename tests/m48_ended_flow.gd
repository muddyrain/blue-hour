extends "res://tests/m48_campaign_flow.gd"
## Read-only current-version reopening of the same bound, fully acknowledged journey.
func _resume() -> void:
	var proof_path: String = _argument("--ending-proof=")
	_check(proof_path.is_absolute_path() and "/.local/" in proof_path,"explicit original terminal proof stays isolated")
	if not proof_path.is_absolute_path() or "/.local/" not in proof_path: return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(proof_path))
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
	var camp: Dictionary = app.camp_snapshot()
	var before: Dictionary = app.progress_session.inspect()
	_check(not app._progress_blocked and before.state == "ENDED" and camp.journey.campaign.outcome == "VICTORY","current reader opens the real durable victory")
	_check(RecordEncoding.fingerprint(camp) == expected.get("final_camp"),"all confirmed resources facilities sources and ownership match the original complete campaign")
	_check(DailyActions.offers(camp).is_empty(),"ended journey has no new payable action candidates")
	var after: Dictionary = app.progress_session.inspect()
	_check(after.hash == before.hash,"read-only reopening does not publish another reward or receipt")
	await _shot("current-confirmed-victory")
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 90
	viewport.add_child(layer)
	var ledger: CampSupplyPanel = CampSupplyPanel.new()
	ledger.theme = app._screen.theme
	layer.add_child(ledger)
	ledger.refresh(camp,CampEconomy.rations(int(camp.day),camp.crew,int(camp.food),app.camp_rules),"已确认终局 · 实际资源与设施账本 · 只读",false)
	await _hold(4)
	_check(ledger.build_buttons.values().all(func(button: Button) -> bool: return button.disabled),"authentic ended ledger exposes no legal facility purchase")
	await _shot("actual-final-facility-ledger")
	_write("ended.json",{"scope":"AUTHENTIC_CONFIRMED_CAMP_READ_ONLY_LEDGER_WIDGET","pid":OS.get_process_id(),"original_proof":proof_path,"camp":RecordEncoding.fingerprint(camp),"receipt":before.hash,"value":camp})
	layer.queue_free()
	await _frame()
