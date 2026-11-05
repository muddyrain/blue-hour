extends "res://tests/task_flow.gd"
## Impossible event identities must be rejected in both computation and retained results.
func _journey() -> void:
	await _tap(app._home_button); await _tap(app._new_game_confirmation.get_ok_button())
	await _menu(); await _start("airdrop")
	var world: Expedition = app.expedition
	world.request_search(&"cash")
	await _advance(world,func() -> bool:return world.search_site(&"cash").searched)
	await _finish(world,false)
	var packet: Dictionary = app.progress_session.packet.duplicate(true)
	_check(not packet.is_empty() and FrozenSettlement.input_problem(packet.input).is_empty(),"actual airdrop result input remains valid")
	for kind: String in ["outside","duplicate"]:
		var bad: Dictionary = packet.input.duplicate(true)
		var first: int = int(bad.report.task_event.resolutions[0].enemy_id)
		bad.report.task_event.resolutions[1].enemy_id=999999 if kind=="outside" else first
		_check(not FrozenSettlement.input_problem(bad).is_empty() and not FrozenSettlement.compute(bad).error.is_empty(),"frozen result refuses impossible event identity "+kind)
		var receipt: Dictionary = app.progress_session._transaction.recover().receipt.duplicate(true)
		receipt.envelope.result.battle.task_event=bad.report.task_event.duplicate(true)
		receipt.envelope.result_hash=SurvivalContracts.fingerprint(receipt.envelope.result)
		_check(TransactionReceipt.problem(receipt).contains("TASK_EVENT_ENEMY"),"rehashed retained result refuses impossible event identity "+kind)
	for kind: String in ["missing","malformed"]:
		var receipt: Dictionary = app.progress_session._transaction.recover().receipt.duplicate(true)
		if kind=="missing": receipt.envelope.result.battle.site_facts={}
		else: receipt.envelope.result.battle.site_facts.cash={}
		receipt.envelope.result_hash=SurvivalContracts.fingerprint(receipt.envelope.result)
		_check(TransactionReceipt.problem(receipt).contains("SITE_"),"malformed site facts reject before summary projection "+kind)
	_write("result-input.json",{"encoded":RecordEncoding.stringify(packet.input),"spawn_count":packet.input.report.xp_inputs.spawn_count})
