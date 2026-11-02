class_name TrainingPlaytest
extends TraitPlaytest
## Explicit original UI and transaction intentions. Natural food comes from the inherited real sortie.

var _trained: bool = false
var _training_before: Dictionary = {}
var _training_after: Dictionary = {}


func _task_path() -> String:
	if "/.local/p0-recovery-gen-01/" in output_dir.replace("\\","/"):
		return "/.local/p0-recovery-gen-01/"
	return "/.local/m5-training-01/"


func _trait_problem(data: Dictionary) -> String:
	return TrainingState.problem(data)


func _expect(value: bool, label: String) -> void:
	super._expect(value,label.replace("106","107"))


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-case="):
			camp_case = arg.trim_prefix("--camp-case=")
		if arg.begins_with("--camp-expected="):
			expected_path = arg.trim_prefix("--camp-expected=")
	if not output_dir.is_absolute_path() or _task_path() not in output_dir.replace("\\","/") or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	if camp_case not in ["train","train-ack","train-write","train-locked","kill-ready","kill-after-write","stale","cap","zero-food","effects-training"]:
		await super._run()
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _settle()
	await get_tree().create_timer(0.3).timeout
	await _enter()
	_initial = app.camp_snapshot()
	if camp_case=="effects-training":
		var digest: String = _digest()
		app.get_node("Interface/Screen").hide()
		var baseline: Dictionary = app.camp_snapshot()
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--training-baseline=") and _task_path() in arg.replace("\\","/"):
				baseline = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--training-baseline=")))
		var samples: Array[Dictionary] = await TrainingEffectProbe.run(get_tree(),baseline,_capture)
		_write(output_dir.path_join("training-causal.json"),{"samples":samples})
		_expect(samples.size()==8,"all three real purchase proposals produce paired actual-handler controls")
		for index: int in range(0,samples.size(),2):
			var before: Dictionary = samples[index]
			var after: Dictionary = samples[index+1]
			_expect(after.training_food==before.training_food-1 and after.training_progress==before.training_progress+1 and after.trait_level==TraitRules.level_for(int(after.training_progress)) and (before.natural_checkpoint or (before.trait_level==1 and after.trait_level==2)),"original purchase gives exactly one point/one-food and actual next level")
			_expect((after.interval<before.interval if before.member_id==1 and after.trait_level>before.trait_level else after.interval==before.interval) and (after.search_seconds<before.search_seconds if before.member_id==2 and after.trait_level>before.trait_level else after.search_seconds==before.search_seconds) and (after.path_seconds<before.path_seconds if before.member_id==3 and after.trait_level>before.trait_level else after.path_seconds==before.path_seconds),"only the trained member ability changes its real handler outcome")
			for row: Dictionary in [before,after]:
				_expect(row.path_clear and row.arrived and row.blocked_no_fire and row.down_no_fire and row.pause_freezes and row.cancel_no_reward and row.zero_defeat_diagnostic,"purchase preserves LOS/death/navigation/pause/cancel and diagnostic exclusion")
		_expect(digest==_digest() and TransactionReceipt.same(_initial,app.camp_snapshot()),"causal fixtures leave campaign memory and all disk bytes unchanged")
		app.get_node("Interface/Screen").show()
		await _finish_camp()
		return
	if camp_case in ["cap","zero-food"]:
		await _tap(app.camp_scene.hotspots[&"training"])
		await _tap(app.training_panel.member_buttons[1])
		_expect(app.training_panel.train_button.disabled,"no food / Lv5 disables purchase")
		var digest: String = _digest()
		app.training_panel._confirm()
		_expect(digest==_digest(),"disabled or unarmed confirmation cannot mutate disk")
		await _capture("training-refused.png")
		await _key_battle(KEY_ESCAPE)
	elif camp_case=="stale":
		await _tap(app.camp_scene.hotspots[&"training"])
		await _tap(app.training_panel.member_buttons[1])
		var old: Dictionary = app.training_panel._quote.request.duplicate(true)
		var result: Dictionary = app.progress_session.edit(app.camp_snapshot(),{"kind":"rename","member_id":2,"value":"旧预览已失效"})
		_expect(app._accept_transaction(result,true),"other valid camp edit uses original authority")
		var changed: Dictionary = app.camp_snapshot()
		app.confirm_training(old)
		_expect(TransactionReceipt.same(changed,app.camp_snapshot()) and not app._progress_blocked,"stale preview refuses without deducting or blocking valid camp")
		await _capture("stale-preview-refused.png")
		await _key_battle(KEY_ESCAPE)
	else:
		await _train_member(1)
	await _finish_camp()


func _training_entry(scene: CampSceneView, label: String) -> void:
	var before: Dictionary = app.camp_snapshot()
	var digest: String = _digest()
	await _tap(scene.hotspots[&"training"])
	var panel: TrainingPanel = app.training_panel
	_expect(panel.visible and not scene.is_visible_in_tree(),"real campfire opens exclusive training view")
	panel.back_button.grab_focus()
	await _key_battle(KEY_TAB)
	_expect(get_viewport().gui_get_focus_owner()==panel.member_buttons.values()[0],"training Tab cycles from close to first actual living member")
	await _key_shift_tab()
	_expect(get_viewport().gui_get_focus_owner()==panel.back_button,"training Shift+Tab returns to close without reaching camp")
	for id: int in panel.member_buttons.keys():
		_expect(SurvivorRoster.member(before.crew,id).health>0,"training list filters confirmed dead identities")
		await _tap(panel.member_buttons[id])
		_expect(TraitRules.NAMES[id-1] in panel.detail.text,"training preview belongs to selected stable ID")
	await _capture(label+"-training.png")
	var calls: int = _navigation.size()
	await _click_at(scene.hotspots[&"bus"].get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	_expect(_navigation.size()==calls and app.expedition==null,"opaque training view never forwards wheel to bus")
	if not panel.train_button.disabled:
		panel.train_button.grab_focus()
		await _key_battle(KEY_SPACE)
		_expect(panel.confirmation.visible,"training requires explicit second confirmation")
		panel.train_button.pressed.emit()
		_expect(panel.confirmation.visible and digest==_digest(),"duplicate preview callback cannot purchase or stack confirmation")
		await _capture(label+"-training-confirm.png")
		await _key_battle(KEY_ESCAPE)
		_expect(panel.visible and not panel.confirmation.visible,"Esc cancels confirmation but keeps training view")
		panel.train_button.grab_focus()
		await _key_battle(KEY_ENTER)
		_expect(panel.confirmation.visible,"Enter opens one fresh confirmation without a purchase")
		await _key_battle(KEY_ESCAPE)
	await _key_battle(KEY_ESCAPE)
	_expect(scene.is_visible_in_tree() and not panel.visible and digest==_digest() and TransactionReceipt.same(before,app.camp_snapshot()),"training browsing/selection/confirm cancellation/Esc make zero writes")


func _train_member(id: int) -> void:
	_training_before = app.camp_snapshot()
	_write(output_dir.path_join("training-before.json"),_training_before)
	await _tap(app.camp_scene.hotspots[&"training"])
	var panel: TrainingPanel = app.training_panel
	# Inspect and cancel the other real survivor before selecting the purchase owner.
	var other: int = 1 if id!=1 else 2
	if panel.member_buttons.has(other):
		await _tap(panel.member_buttons[other])
		if not panel.train_button.disabled:
			var digest: String = _digest()
			await _tap(panel.train_button)
			await _tap(panel.confirmation.get_cancel_button())
			_expect(digest==_digest(),"other survivor confirmation cancels without a purchase")
	await _tap(panel.member_buttons[id])
	var quote: Dictionary = panel._quote.duplicate(true)
	_expect(not quote.is_empty(),"selected living survivor has a real one-food quote")
	if quote.is_empty():
		return
	_write(output_dir.path_join("training-preview.json"),quote)
	await _capture("training-before.png")
	await _tap(panel.train_button)
	await _capture("training-confirm.png")
	if camp_case=="train-write":
		app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point=="before_camp_write" else OK
	elif camp_case=="train-ack":
		app.progress_session.fault_hook = func(point: String) -> Error: return ERR_CANT_CREATE if point=="before_commit_receipt" else OK
	elif camp_case=="train-locked":
		app.progress_session.fault_hook = _lock_barrier
	elif camp_case in ["kill-ready","kill-after-write"]:
		app.progress_session.fault_hook = _kill_barrier
	panel.confirmation.get_ok_button().grab_focus()
	await _key_battle(KEY_ENTER if id==2 else KEY_SPACE)
	if camp_case in ["train-write","train-ack","train-locked"]:
		_expect(app._progress_blocked and TransactionReceipt.same(_training_before,app.camp_snapshot()) and panel.retry_button.visible,"failed write/ACK keeps original memory and explicit original-edit retry")
		await _capture("training-save-pending.png")
		if camp_case=="train-locked":
			_write(output_dir.path_join("unlock-request.json"),{"pid":OS.get_process_id()})
			for frame: int in range(500):
				if FileAccess.file_exists(output_dir.path_join("unlocked")):
					break
				await get_tree().create_timer(0.02).timeout
		app.progress_session.fault_hook = Callable()
		await _tap(panel.retry_button)
	_training_after = app.camp_snapshot()
	_expect(TransactionReceipt.same(_training_after,quote.after) and not app._progress_blocked,"saved after exactly equals confirmed atomic one-food/one-point proposal")
	var state: Dictionary = app.progress_session.inspect()
	_expect(state.receipt.phase=="EDIT_COMMITTED" and state.receipt.transaction_id==TrainingRules.intent_for(quote.request).edit_id,"original edit identity and ACK are durable")
	_write(output_dir.path_join("training-edit.json"),state.receipt)
	_write(output_dir.path_join("training-after.json"),_training_after)
	var digest: String = _digest()
	panel.confirmation.confirmed.emit()
	panel.confirmation.confirmed.emit()
	app.progress_session.edit(_training_before,quote.request)
	_expect(digest==_digest() and TransactionReceipt.same(_training_after,app.camp_snapshot()),"duplicate confirmation callbacks and old edit request never purchase twice")
	await _capture("training-after.png")
	await _key_battle(KEY_ESCAPE)
	_expect(app.camp_scene.is_visible_in_tree(),"Esc after training returns to authoritative camp")
	await _capture("camp-after-training.png")
	_reject_persisted_suspends("TRAINING_COMMITTED")


func _kill_barrier(point: String) -> Error:
	var target: String = "before_camp_write" if camp_case=="kill-ready" else "after_camp_write"
	if point!=target:
		return OK
	var state: Dictionary = app.progress_session.inspect()
	_write(output_dir.path_join("barrier.json"),{"pid":OS.get_process_id(),"point":point,"phase":state.receipt.phase,
		"camp":state.receipt.envelope.result,"before":_training_before,
		"before_hash":state.receipt.envelope.before_hash,"after_hash":state.receipt.envelope.after_hash,
		"main_sha256":FileAccess.get_sha256(app.progress_path)})
	for tick: int in range(3000):
		OS.delay_msec(10)
	return ERR_TIMEOUT


func _finish_camp() -> void:
	if camp_case in ["journey-train","journey-train-third"] and not _trained and not _reports.is_empty() and app.phase==app.Phase.TITLE and not app._progress_blocked:
		_trained = true
		await _train_member(3 if camp_case=="journey-train-third" else 2)
	await super._finish_camp()
