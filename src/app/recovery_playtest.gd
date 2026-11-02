class_name RecoveryPlaytest
extends ExitPlaytest
## Explicit isolated process proof; viewport intentions, never OS input.

var checkpoint: String = "search"
var expected_path: String = ""
var captured: Dictionary = {}
var replay_tokens: Array[Dictionary] = []


func _run() -> void:
	if not output_dir.is_absolute_path() or "/.local/" not in output_dir.replace("\\","/").to_lower() or FileAccess.file_exists(output_dir.path_join("report.json")):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--recovery-case="): mode = arg.trim_prefix("--recovery-case=")
		if arg.begins_with("--recovery-point="): checkpoint = arg.trim_prefix("--recovery-point=")
		if arg.begins_with("--recovery-expected="): expected_path = arg.trim_prefix("--recovery-expected=")
		if arg == "--recovery-map=market": _map = 1
		if arg.begins_with("--recovery-fault="): _fault_point = arg.trim_prefix("--recovery-fault=")
		if arg.begins_with("--recovery-barrier="): _barrier = arg.trim_prefix("--recovery-barrier=")
	app.progress_session.fault_hook = _fault
	var requested_fault: String = _fault_point
	var requested_barrier: String = _barrier
	_fault_point = ""
	_barrier = ""
	await _settle()
	# Wait for the first native frame/window setup before the single-click probe.
	await get_tree().create_timer(0.3).timeout
	print("BH_FIRST_INPUT ", {"ticks":Time.get_ticks_msec(),"focused":DisplayServer.window_is_focused(),"visible":app._continue_button.is_visible_in_tree(),"disabled":app._continue_button.disabled,"rect":str(app._continue_button.get_global_rect())})
	if mode == "blocked":
		_expect(app._progress_blocked and not app._requires_continue,"fresh process blocks consumed/corrupt/foreign snapshot without old camp")
		await _capture("blocked.png")
	elif mode == "camp":
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
		var state: Dictionary = app.progress_session.inspect()
		_expect(state.get("state") == "CAMP" and app.settled_sorties == 1,"new PID continues committed camp exactly once")
		var bytes: String = _digest()
		for record: String in DirAccess.get_directories_at(app.progress_path+".txn/journal"):
			var path: String = (app.progress_path+".txn/journal").path_join(record).path_join("record.json")
			if not FileAccess.file_exists(path): continue
			var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)).payload
			if payload.phase == "SUSPEND_READY":
				_expect(app.progress_session._transaction.claim_suspend(RunTransaction.token_for(payload),payload.envelope.world_hash,payload.envelope.previous_head).error != OK,"committed camp rejects old snapshot generation "+record)
		_expect(bytes == _digest(),"old snapshot attempts leave committed camp and head byte stable")
		await _capture("camp-reopened.png")
	elif mode == "ended":
		await _tap(app._continue_button)
		_expect(app.progress_session.inspect().get("state") == "ENDED" and app._battle_meta.get("state") == "FAILED","fresh process retains final death and terminal journey")
		var state: Dictionary = app.progress_session.inspect()
		var bytes: String = _digest()
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		var replayed: Dictionary = app.progress_session._transaction.suspend(RunTransaction.token_for(state.receipt),old)
		_expect(replayed.error != OK and _digest() == bytes,"pre-final-death snapshot cannot rewind committed FAILED or change a byte")
		await _capture("terminal-reopened.png")
	elif mode in ["save","fault","death-save","death-first"]:
		if mode in ["death-save","death-first"]:
			await _tap(app._home_button)
		else:
			await _enter()
		_initial = app.camp_snapshot()
		if mode in ["death-save","death-first"]:
			_expect(_initial.food == 12 and _initial.crew.all(func(row: Dictionary) -> bool: return row.health == 4),"explicit labelled4HP/12food drill only, never ordinary start")
		else:
			_expect(_initial.food == 2 and _initial.crew.all(func(row: Dictionary) -> bool: return row.health == 200),"ordinary200HP/2food starter, no near-enemy seed")
		await _open_map(_map)
		var world: Expedition = app.expedition
		if world == null:
			_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"failures":_failures,"checks":_checks})
			app.audio.shutdown()
			get_tree().quit(1)
			return
		if mode == "death-save":
			await _ui_checks(world)
			world.request_search(&"cash")
			for frame: int in range(3600):
				if world.searched and world.kills > 0: break
				await _step(world)
			world.request_bus_action()
			await _tap(world.drill_panel.buttons[0])
			for frame: int in range(180):
				if world.survivors[0].permanent_death: break
				await _step(world)
			_expect(world.survivors[0].permanent_death and world.survivors[0].health == 0 and world.survivors[1].member_id == 2,"real enemy lethal gate confirmed ID1 death; original ID2 remains")
			await _capture("confirmed-death.png")
		world.request_search(&"cash")
		if checkpoint != "start":
			for frame: int in range(3600):
				if world.search_progress > 4 and not world.enemies.is_empty(): break
				await _step(world)
		if checkpoint in ["engine","boarding"]:
			for frame: int in range(3600):
				if world.elapsed >= world.tuning.bus_ready_seconds: break
				await _step(world)
			world.request_bus_action()
			if checkpoint == "boarding":
				for frame: int in range(180):
					if world.phase == Expedition.Phase.BOARDING: break
					await _step(world)
				world.request_bus_gather()
		await _key_battle(KEY_ESCAPE)
		_expect(world.is_paused and app.pause_menu.buttons[4].visible,"Esc freezes real scene and exposes explicit safe suspend")
		await _layout("suspend")
		await _frozen(world,checkpoint)
		for index: int in range(2): await _key_battle(KEY_TAB)
		_expect(get_viewport().gui_get_focus_owner() == app.pause_menu.buttons[4],"Tab reaches prioritized safe suspend action without leaking to HUD")
		captured = SortieSnapshot.capture(world)
		_write(output_dir.path_join("snapshot.json"),captured)
		var original: String = FileAccess.get_sha256(app.progress_path)
		await _capture("before-suspend.png")
		if mode == "fault": _fault_point = requested_fault
		_barrier = requested_barrier
		_handshake = not _barrier.is_empty()
		await _key_battle(KEY_ENTER)
		if mode in ["save","death-save","death-first"]:
			_expect(app.expedition == null and app.phase == app.Phase.TITLE and app._requires_continue,"only acknowledged suspend returns home and offers same sortie")
			var state: Dictionary = app.progress_session.inspect()
			_expect(state.error == OK and state.get("state") == "SUSPENDED" and TransactionReceipt.same(captured,state.get("receipt",{}).get("envelope",{}).get("world",{})),"journal readback preserves entire authoritative world")
			_expect(FileAccess.get_sha256(app.progress_path) == original,"suspend gives no camp economy/day/HP rollback")
			var after: String = _digest()
			await _key_battle(KEY_ENTER)
			_expect(after == _digest() and app.expedition == null,"repeated confirmation cannot save twice or consume the fresh snapshot")
			await _capture("saved-home.png")
		else:
			_expect(app.expedition == world and world.is_paused and world.suspend_sealed and "未保存成功" in app.pause_menu.body.text,"write failure remains paused in original real scene and states failure")
			var frozen: String = SurvivalContracts.fingerprint(SortieSnapshot.capture(world))
			world.toggle_pause()
			for frame: int in range(30): await _step(world)
			_expect(frozen == SurvivalContracts.fingerprint(SortieSnapshot.capture(world)),"failed publication cannot advance world behind a replayable anchor")
			await _capture("write-failed.png")
			if not requested_barrier.is_empty():
				_write(output_dir.path_join("failed.json"),{"pid":OS.get_process_id(),"message":app.pause_menu.body.text})
				for frame: int in range(1800):
					if FileAccess.file_exists(output_dir.path_join("unlock")): break
					await get_tree().create_timer(0.03).timeout
			_barrier = ""
			_fault_point = ""
			await _tap(app.pause_menu.buttons[0])
			_expect(not world.suspend_sealed and not app.pause_menu.root.visible,"same live owner safely consumes published anchor before continuing")
	elif mode in ["resume","death-resume","resuspend","death-resuspend","safe-quit"]:
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible: await _tap(app._hunger_confirmation.get_ok_button())
		_expect(app.expedition != null,"first Continue restores original world in new process")
		if app.expedition != null:
			var world: Expedition = app.expedition
			world.set_physics_process(false)
			var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
			captured = SortieSnapshot.capture(world)
			_write(output_dir.path_join("restored.json"),captured)
			_expect(TransactionReceipt.same(captured,expected),"all captured actual actors/timers/search/queue/director/camera/growth equal across PIDs")
			var log: Dictionary = ReceiptJournal.new(app.progress_path+".txn/journal").read_all()
			for record: String in DirAccess.get_directories_at(app.progress_path+".txn/journal"):
				var path: String = (app.progress_path+".txn/journal").path_join(record).path_join("record.json")
				if not FileAccess.file_exists(path): continue
				var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)).payload
				if payload.phase == "SUSPEND_READY": replay_tokens.append({"token":RunTransaction.token_for(payload),"hash":payload.envelope.world_hash,"generation":payload.envelope.previous_head})
			_expect(log.error == OK and log.receipt.phase == "RESUME_CLAIMED","consumption durably precedes first resumed step")
			var repeated: Dictionary = app.progress_session.claim_world(log.receipt.envelope.world_hash)
			_expect(repeated.error != OK,"same snapshot cannot be consumed twice even within original process")
			await _capture("restored-paused.png")
			if mode == "death-resume":
				_expect(world.survivors[0].permanent_death and world.survivors[0].health == 0 and world.survivors[1].member_id == 2,"fresh process cannot revive ID1 or renumber sole ID2")
			await _tap(app.pause_menu.buttons[0])
			if world.is_paused: await _key_battle(KEY_SPACE)
			world.finished.connect(func(report: Dictionary) -> void: _reports.append(report.duplicate(true)))
			if mode in ["resuspend","death-resuspend","safe-quit"]:
				await _resuspend(world)
				return
			if mode == "death-resume":
				await _tap(world.drill_panel.buttons[1])
				for frame: int in range(180):
					if world.phase == Expedition.Phase.FINISHED: break
					await _step(world)
				_expect(world.phase == Expedition.Phase.FINISHED and app.progress_session.inspect().get("state") == "ENDED","last real death commits FAILED; consumed suspend cannot rewind terminal")
				await _capture("failed-terminal.png")
				_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"case":mode,"checks":_checks,"failures":_failures,"captured_hash":SurvivalContracts.fingerprint(captured),"camp":app.camp_snapshot(),"reports":_reports,"input_layer":"explicit4HP/near-enemy fixture, native viewport intentions, NOT OS"})
				app.audio.shutdown()
				OS.delay_msec(150)
				await _settle()
				get_tree().quit(0 if _failures == 0 else 1)
				return
			for frame: int in range(3600):
				if world.searched: break
				await _step(world)
			if _map == 1:
				world.request_search(&"food")
				for frame: int in range(3600):
					if world._food_site.searched: break
					await _step(world)
			for frame: int in range(1800):
				if world.elapsed >= world.tuning.bus_ready_seconds: break
				await _step(world)
			world.request_bus_action()
			for frame: int in range(180):
				if world.phase == Expedition.Phase.BOARDING: break
				await _step(world)
			world.request_bus_gather()
			for frame: int in range(3600):
				if world.phase == Expedition.Phase.FINISHED: break
				await _step(world)
			_expect(_reports.size() == 1 and _reports[0].evacuated and not app._pending_settlement.is_empty(),"resumed real search and bus produce exactly one original frozen result")
			_reject_replays("RESULT_READY")
			await _capture("bus-result.png")
			if not app._pending_settlement.is_empty():
				await _tap(app.get_node("Interface/Screen/Result/Continue"))
				var state: Dictionary = app.progress_session.inspect()
				_expect(state.error == OK and state.state in ["CAMP","ENDED"] and app.settled_sorties == 1,"exactly one result committed, not free camp or duplicated reward")
				var digest: String = _digest()
				app.progress_session.activate()
				_expect(digest == _digest(),"duplicate result activation is byte stable")
				_reject_replays("COMMITTED")
				await _capture("committed-camp.png")
	else:
		_expect(false,"known recovery case")
	_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"case":mode,"point":checkpoint,"checks":_checks,"failures":_failures,"captured_hash":SurvivalContracts.fingerprint(captured),"camp":app.camp_snapshot(),"reports":_reports,"display":DisplayServer.get_name(),"window_size":DisplayServer.window_get_size(),"input_layer":"native viewport intent/events, NOT OS; one simulation step per rendered frame"})
	app.audio.shutdown()
	OS.delay_msec(150)
	await _settle()
	get_tree().quit(0 if _failures == 0 else 1)


func _reject_persisted_suspends(stage: String) -> void:
	replay_tokens.clear()
	for folder: String in DirAccess.get_directories_at(app.progress_path+".txn/journal"):
		var file: String = (app.progress_path+".txn/journal").path_join(folder).path_join("record.json")
		if not FileAccess.file_exists(file): continue
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file)).payload
		if receipt.phase == "SUSPEND_READY":
			replay_tokens.append({"token":RunTransaction.token_for(receipt),"hash":receipt.envelope.world_hash,"generation":receipt.envelope.previous_head})
	_reject_replays(stage)


func _reject_replays(stage: String) -> void:
	var before: String = _digest()
	for old: Dictionary in replay_tokens:
		_expect(app.progress_session._transaction.claim_suspend(old.token,old.hash,old.generation).error != OK,stage+" refuses every old single-use suspend token")
	_expect(before == _digest(),stage+" replay attempt cannot change camp or journal bytes")


func _resuspend(world: Expedition) -> void:
	if mode == "death-resuspend":
		# The explicit near-enemy drill requires a visible actor, not an indoor worker.
		for frame: int in range(3600):
			if world.searched and world.kills > 0: break
			await _step(world)
		world.request_bus_action()
		await _tap(world.drill_panel.buttons[0])
		for frame: int in range(180):
			if world.survivors[0].permanent_death: break
			await _step(world)
		_expect(world.survivors[0].permanent_death and world.survivors[1].member_id == 2,"actual AI confirms death after consumed S1, original ID2 survives")
	else:
		var elapsed: float = world.elapsed
		for frame: int in range(900):
			if world.elapsed >= elapsed + 8.0: break
			await _step(world)
		_expect(world.elapsed >= elapsed + 8.0,"world really advances eight simulation seconds after S1 claim")
	_reject_replays("advanced world / confirmed death")
	await _key_battle(KEY_ESCAPE)
	await _layout("S2-priority")
	_expect(app.pause_menu.buttons[4].get_global_rect().position.y < app.pause_menu.buttons[2].get_global_rect().position.y,"safe suspend precedes dangerous exit visually")
	captured = SortieSnapshot.capture(world)
	_write(output_dir.path_join("snapshot.json"),captured)
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	_expect(SurvivalContracts.fingerprint(old) != SurvivalContracts.fingerprint(captured) and captured.sim.elapsed > old.sim.elapsed,"new S2 differs from S1 with latest time and world facts")
	await _capture("S2-menu.png")
	app.request_exit("quit" if mode == "safe-quit" else "home")
	await _settle()
	_expect(app.pause_menu.confirming and app.pause_menu.buttons[2].visible and "安全暂存" in app.pause_menu.buttons[2].text,"close route offers explicit acknowledged safety option")
	await _layout("safe-close")
	await _capture("safe-close.png")
	if mode == "safe-quit":
		_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"failures":_failures,"checks":_checks,"case":mode,"captured_hash":SurvivalContracts.fingerprint(captured)})
		await _tap(app.pause_menu.buttons[2])
		return
	await _tap(app.pause_menu.buttons[2])
	var state: Dictionary = app.progress_session.inspect()
	_expect(app.expedition == null and state.get("state") == "SUSPENDED" and TransactionReceipt.same(captured,state.receipt.envelope.world),"S2 ACK returns home with exact latest world")
	_reject_replays("S2_READY")
	await _capture("S2-saved-home.png")
	_write(output_dir.path_join("report.json"),{"pid":OS.get_process_id(),"failures":_failures,"checks":_checks,"case":mode,"captured_hash":SurvivalContracts.fingerprint(captured),"camp":app.camp_snapshot(),"window_size":DisplayServer.window_get_size(),"input_layer":"native viewport events, NOT OS"})
	app.audio.shutdown()
	await _settle()
	get_tree().quit(0 if _failures == 0 else 1)
