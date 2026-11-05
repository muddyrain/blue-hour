extends "res://tests/combat_flow.gd"
func _resume()->void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:await _tap(app._hunger_confirmation.get_ok_button())
	var w:Expedition=app.expedition
	_check(w!=null,"new PID resumes original acknowledged R1 suspend")
	if w==null:return
	w.set_physics_process(false);w.set_process(false)
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("green-toxic/checkpoint.json")))
	_check(OS.get_process_id()!=expected.pid and RecordEncoding.fingerprint(SortieSnapshot.capture(w))==expected.fingerprint,"new PID exactly restores post-death HP/actions/XP/heal/cooldown")
	var hp:float=w.survivors[1].health
	var xp:int=w.xp_inputs.events.size()
	var kills:int=w.kills
	var support:Dictionary=w.basic_support.snapshot()
	var deaths:Array=app.progress_session._transaction.recover().receipt.deaths.duplicate(true)
	if app.pause_menu.visible:await _tap(app.pause_menu.buttons[0])
	if w.is_paused:w.toggle_pause()
	w.step(0.0)
	_check(w.survivors[0].health==0 and w.survivors[0].permanent_death and w.combat.action(w.survivors[0]).remaining==0,"continued dead wielder has no latent swing")
	_check(w.survivors[1].health==hp and w.xp_inputs.events.size()==xp and w.kills==kills and TransactionReceipt.same(w.basic_support.snapshot(),support) and TransactionReceipt.same({"v":app.progress_session._transaction.recover().receipt.deaths},{"v":deaths}),"continue cannot duplicate hit/heal/XP/death/cooldown")
	_write("restored.json",{"pid":OS.get_process_id(),"source_pid":expected.pid,"hp":hp,"xp":xp,"kills":kills,"support":support,"deaths":deaths})
