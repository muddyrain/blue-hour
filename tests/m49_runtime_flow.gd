extends "res://tests/m48_campaign_flow.gd"
## Original Windows-bound camps; native widget input, with only I/O faults directed.
## No source mutation, synthetic balances, or artificial worker delay is used.

var runtime_case: String = ""
var runtime_fault: String = ""
var runtime_bank_fault: bool = false
var runtime_frames: Array[Dictionary] = []
var runtime_probes: Dictionary = {}
var runtime_evidence: Dictionary = {}
var runtime_close_requested: bool = false
var runtime_wait_captured: bool = false
var runtime_active_freeze_saved: bool = false


func _initialize() -> void:
	super()
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_observe_runtime_frame)


func _observe_commit_paint() -> void:
	# PNG encoding is deliberately outside all measured operation intervals.
	pass


func _observe_runtime_frame() -> void:
	if not is_instance_valid(app) or not is_instance_valid(viewport):
		return
	var startup: bool = app.get("_startup_pending") == true
	if not startup and app.get("_progress_busy") != true:
		return
	var request_id: int = 0 if startup else int(app.get("_progress_request_id"))
	var now: int = Time.get_ticks_usec()
	var kind: String = "startup" if startup else String(app.get("_progress_operation"))
	runtime_frames.append({"stamp_usec":now, "request_id":request_id, "operation":kind,
		"since_request_usec":now - int(app.get("_progress_started_usec"))})
	if "--runtime-capture-wait" in OS.get_cmdline_user_args() and kind == "commit_result" \
			and not runtime_wait_captured and now - int(app.get("_progress_started_usec")) >= 100000:
		runtime_wait_captured = true
		viewport.get_texture().get_image().save_png(output.path_join("return-wait-native.png"))
		_write("wait-capture-scope.json", {"scope":"NATIVE_T3_FAULT_EVIDENCE_NOT_PERFORMANCE_SAMPLE", "PNG_encoding_in_frames":true})
	if runtime_case == "close-continue" and kind == "continue" and not runtime_close_requested:
		runtime_close_requested = true
		app.get_window().close_requested.emit()
		_write("runtime-close-request.json", {"pid":OS.get_process_id(), "request_id":request_id,
			"pending":app._progress_busy, "exit_intent":app._safe_exit_requested,
			"scope":"DIRECTED_NATIVE_WINDOW_CLOSE_SIGNAL_NOT_PHYSICAL_OS_INPUT"})
	if runtime_case == "close-edit" and kind == "edit" and not runtime_close_requested:
		var worker: Thread = app.get("_progress_worker")
		if worker != null and worker.is_alive():
			runtime_close_requested = true
			app.get_window().close_requested.emit()
			_write("runtime-close-request.json", {"pid":OS.get_process_id(), "request_id":request_id,
				"worker_alive":worker.is_alive(), "pending":app._progress_busy, "exit_intent":app._safe_exit_requested,
				"scope":"DIRECTED_NATIVE_WINDOW_CLOSE_SIGNAL_DURING_REAL_EDIT_WORKER"})
	var active_kind: String = "begin" if runtime_case == "close-begin" else "claim" if runtime_case == "close-claim" else ""
	if not active_kind.is_empty() and kind == active_kind and not runtime_close_requested:
		var worker: Thread = app.get("_progress_worker")
		if worker != null and worker.is_alive():
			# This is an observed real worker, with no test sleep or source injection.
			runtime_close_requested = true
			app.get_window().close_requested.emit()
			_write("runtime-close-request.json", {"pid":OS.get_process_id(), "case":runtime_case,
				"request_id":request_id, "operation":kind, "worker_alive_observed":true,
				"pending":app._progress_busy, "exit_intent":app._safe_exit_requested,
				"scope":"DIRECTED_NATIVE_WINDOW_CLOSE_SIGNAL_DURING_REAL_WORKER_NOT_PHYSICAL_OS_INPUT"})
	if not active_kind.is_empty() and kind == "suspend" and runtime_close_requested and not runtime_active_freeze_saved:
		var frozen: Dictionary = app.get("_frozen_world")
		if not frozen.is_empty():
			runtime_active_freeze_saved = true
			_write("runtime-active-freeze.json", {"pid":OS.get_process_id(), "case":runtime_case,
				"request_id":request_id, "world_hash":SurvivalContracts.fingerprint(frozen),
				"world_hash_algorithm":"SurvivalContracts.fingerprint",
				"world_exact_hash":RecordEncoding.fingerprint(frozen), "world_exact_hash_algorithm":RecordEncoding.VERSION,
				"action_hash":RecordEncoding.fingerprint(frozen.generated),
				"elapsed_exact":RecordEncoding.stringify({"elapsed":frozen.sim.elapsed}),
				"scope":"MAIN_OWNED_REAL_FROZEN_WORLD_BEFORE_AUTOMATIC_SAFE_EXIT_SUSPEND"})
	if runtime_probes.has(request_id):
		return
	var began: int = Time.get_ticks_usec()
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	viewport.push_input(event, true)
	var handled: bool = viewport.is_input_handled()
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)
	runtime_probes[request_id] = {"operation":kind, "handled":handled,
		"processing_usec":Time.get_ticks_usec() - began, "scope":"NATIVE_VIEWPORT_KEY_EVENT_NOT_PHYSICAL_INPUT"}


func _frame() -> void:
	await super._frame()
	if not is_instance_valid(app):
		return
	var deadline: int = Time.get_ticks_msec() + 900000
	while (app.get("_progress_busy") == true or app.get("_camp_commit_busy") == true) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(app.get("_progress_busy") != true, "original serial progress operation reaches its real completion boundary")


func _journey() -> void:
	_check(false, "M49 runtime cases require --flow-resume from an original Windows-bound M48 camp")


func _resume() -> void:
	runtime_case = _argument("--runtime-case=")
	runtime_fault = _argument("--runtime-fault=")
	if runtime_case == "writer-contender":
		var state: Dictionary = app._progress_view
		_check(state.get("error", OK) != OK and state.get("reason") == "PROGRESS_WRITER_BUSY"
			and app._progress_blocked, "a second native process is denied the original progress writer")
		_write("writer-contender.json", {"pid":OS.get_process_id(), "profile_path":app.progress_path,
			"state":state, "scope":"SECOND_NATIVE_PROCESS_ORIGINAL_WINDOWS_BOUND_SLOT"})
		return
	if runtime_case == "close-claim":
		await _runtime_close_claim()
		return
	if runtime_case == "close-active-readback":
		await _runtime_active_readback()
		return
	if runtime_case == "close-continue":
		var state: Dictionary = app.progress_session.inspect()
		_check(state.get("state") == "SUSPENDED", "close-during-continue begins with a complete real suspended world")
		_write("runtime-close-proof.json", {"pid":OS.get_process_id(), "state":state.state,
			"head":state.hash, "world_hash":state.receipt.envelope.world_hash, "profile_path":app.progress_path,
			"root_id":state.receipt.root_id, "camp_hash":RecordEncoding.fingerprint(state.receipt.base),
			"world_hash_algorithm":"SurvivalContracts.fingerprint",
			"world_exact_hash":RecordEncoding.fingerprint(state.receipt.envelope.world), "world_exact_hash_algorithm":RecordEncoding.VERSION})
		app._hunger_consented = true
		app.continue_game()
		for index: int in range(54000):
			await process_frame
		_check(false, "busy window close normally exits after verification without claiming the world")
		return
	if runtime_case == "suspend-readback":
		var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_argument("--runtime-proof=")))
		var state: Dictionary = app.progress_session.inspect()
		_check(prior.pid != OS.get_process_id() and prior.profile_path == app.progress_path
			and state.get("state") == "SUSPENDED" and state.get("hash") == prior.head,
			"independent process still offers the exact unconsumed suspended world after close")
		await _tap(app._continue_button)
		if app._hunger_confirmation.visible:
			await _tap(app._hunger_confirmation.get_ok_button())
		var world: Expedition = app.expedition
		var actual: Dictionary = SortieSnapshot.capture(world) if world != null else {}
		var actual_hash: String = SurvivalContracts.fingerprint(actual)
		var actual_exact_hash: String = RecordEncoding.fingerprint(actual)
		var expected_exact_hash: String = prior.get("world_exact_hash", RecordEncoding.fingerprint(state.receipt.envelope.world))
		_check(world != null and actual_hash == prior.world_hash and actual_exact_hash == expected_exact_hash,
			"normal continue restores the exact original world instead of an unfinished-action block")
		_write("suspend-readback-restored.json", {"pid":OS.get_process_id(), "source_pid":prior.pid,
			"profile_path":app.progress_path, "head_before_continue":state.hash, "root_id":state.receipt.root_id,
			"camp_hash":RecordEncoding.fingerprint(state.receipt.base), "world_hash":actual_hash,
			"world_hash_algorithm":"SurvivalContracts.fingerprint", "world_exact_hash":actual_exact_hash,
			"world_exact_hash_algorithm":RecordEncoding.VERSION, "expected_business_hash":prior.world_hash,
			"expected_exact_hash":expected_exact_hash, "world_exists":world != null})
		if world == null or actual_hash != prior.world_hash or actual_exact_hash != expected_exact_hash:
			var diagnostic: Dictionary = {"pid":OS.get_process_id(), "scope":"RESTORE_HANDSHAKE_DIAGNOSTIC_NO_STATE_CHANGE",
				"profile_path":app.progress_path, "expected_business_hash":prior.world_hash, "actual_business_hash":actual_hash,
				"expected_exact_hash":expected_exact_hash, "actual_exact_hash":actual_exact_hash,
				"business_algorithm":"SurvivalContracts.fingerprint", "exact_algorithm":RecordEncoding.VERSION,
				"expected":state.get("receipt", {}).get("envelope", {}).get("world", {}), "actual":actual,
				"world_exists":world != null, "app_phase":app.phase, "progress_busy":app.get("_progress_busy"),
				"last_worker_timing":app.get("_progress_last_timing")}
			if world != null:
				diagnostic.world_status = {"is_paused":world.is_paused, "suspend_sealed":world.suspend_sealed,
					"physics_processing":world.is_physics_processing(), "processing":world.is_processing(),
					"elapsed":world.elapsed, "phase":world.phase, "field_join_error":world.field_join_error,
					"bus_stage":world.bus_view.stage if world.bus_view != null else "NONE",
					"pause_menu_visible":app.pause_menu.root.visible}
			var encoded: String = RecordEncoding.stringify(diagnostic)
			var file: FileAccess = FileAccess.open(output.path_join("suspend-readback-capture-diagnostic.json"), FileAccess.WRITE)
			file.store_string(encoded)
			file.close()
		if world != null:
			app.open_pause_menu()
			app.suspend_sortie()
			await _frame()
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(not app._progress_blocked and EconomyBuildV1.enabled(app.camp_snapshot()), "native cold process continues the authentic M48 camp")
	if app._progress_blocked:
		return
	match runtime_case:
		"edit": await _runtime_edit()
		"unstarted-edit-retry": await _runtime_unstarted_retry()
		"close-edit": await _runtime_close_edit()
		"close-begin": await _runtime_close_begin()
		"close-edit-readback": _runtime_close_edit_readback()
		"return": await _runtime_return()
		"readback": _runtime_readback()
		"writer-owner": await _runtime_writer_owner()
		"catalog":
			await _tap(app.camp_scene.footer_buttons[&"specialties"])
			_check(app._equipment_catalog.visible and app._catalog_view.get("error") == OK,
				"normal specialties hotspot publishes the completely verified catalog")
			await _shot("long-history-catalog")
			app._close_equipment_catalog()
		_:
			_check(false, "known M49 runtime scenario")
	_write("runtime-frames.json", {"pid":OS.get_process_id(), "frames":runtime_frames, "probes":runtime_probes,
		"last_worker_timing":app._progress_last_timing, "scope":"NATIVE_BACKGROUND_APPLICATION_FRAMES_NOT_MONITOR_FPS"})


func _runtime_write_active_proof(before: Dictionary, state: Dictionary, action: Dictionary, world_hash: String = "") -> bool:
	var proof: Dictionary = {"pid":OS.get_process_id(), "case":runtime_case, "profile_path":app.progress_path,
		"before_camp":before, "before_camp_hash":RecordEncoding.fingerprint(before), "before_head":state.hash,
		"before_revision":state.receipt.revision, "action":action, "action_hash":RecordEncoding.fingerprint(action),
		"world_hash":world_hash, "world_hash_algorithm":"SurvivalContracts.fingerprint",
		"world_exact_hash":RecordEncoding.fingerprint(state.receipt.envelope.world) if not world_hash.is_empty() else "",
		"world_exact_hash_algorithm":RecordEncoding.VERSION, "freeze_path":output.path_join("runtime-active-freeze.json"),
		"scope":"ORIGINAL_BOUND_CAMP_AND_REAL_SELECTED_ACTION_BEFORE_BUSY_CLOSE"}
	var encoded: String = RecordEncoding.stringify(proof)
	_check(not encoded.is_empty(), "busy active-close proof preserves the complete original camp and action exactly")
	if encoded.is_empty():
		return false
	var file: FileAccess = FileAccess.open(output.path_join("runtime-active-proof.json"), FileAccess.WRITE)
	_check(file != null, "busy active-close proof is retained before input dispatch")
	if file == null:
		return false
	file.store_string(encoded)
	file.close()
	return true


func _runtime_close_begin() -> void:
	if not await _open_cards():
		return
	var slot: int = _find_card(func(action: Dictionary) -> bool: return action.type == "supply" and not PumpStationAction.enabled(action))
	if slot < 0:
		slot = _find_card(func(action: Dictionary) -> bool: return not PumpStationAction.enabled(action))
	_check(slot >= 0, "real current camp exposes a legal ordinary card for begin-close")
	if slot < 0:
		return
	var before: Dictionary = app.camp_snapshot()
	var action: Dictionary = app.mission_select.daily_offers[slot].duplicate(true)
	var state: Dictionary = app.progress_session.inspect()
	_check(state.get("state") == "CAMP" and TransactionReceipt.same(state.camp, before),
		"begin-close starts from a completely confirmed original camp")
	if state.get("state") != "CAMP" or not _runtime_write_active_proof(before, state, action):
		return
	await _tap(app.mission_select.choices[slot])
	_check(app.mission_select.depart_button.is_visible_in_tree() and not app.mission_select.depart_button.disabled,
		"real card selection reaches the ordinary enabled departure confirmation")
	await _tap(app.mission_select.depart_button)
	await _runtime_await_active_exit()


func _runtime_close_claim() -> void:
	var state: Dictionary = app.progress_session.inspect()
	_check(state.get("state") == "SUSPENDED" and state.get("receipt", {}).get("phase") == "SUSPEND_READY",
		"claim-close starts from a genuine complete original SUSPEND_READY world")
	if state.get("state") != "SUSPENDED":
		return
	var receipt: Dictionary = state.receipt
	if not _runtime_write_active_proof(receipt.base, state, receipt.rules.mission.generated, receipt.envelope.world_hash):
		return
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	await _runtime_await_active_exit()


func _runtime_await_active_exit() -> void:
	if not runtime_close_requested:
		_check(false, "NOT_COVERED: no rendered native frame observed the real " + runtime_case + " worker alive; no close was fabricated")
		_write("runtime-active-not-covered.json", {"pid":OS.get_process_id(), "case":runtime_case,
			"coverage":"NOT_COVERED_WORKER_FINISHED_BEFORE_NATIVE_ALIVE_OBSERVATION", "source_injection":false})
		# A missed observation is not permission to leave an unprotected outing.
		if is_instance_valid(app.expedition):
			app.open_pause_menu()
			if app.pause_menu.root.visible and app.pause_menu.buttons[4].is_visible_in_tree():
				await _tap(app.pause_menu.buttons[4])
		return
	for index: int in range(600):
		await process_frame
	_check(false, "observed busy active close normally exits only after its automatic safe suspend")
	_write("runtime-active-exit-timeout.json", {"pid":OS.get_process_id(), "case":runtime_case,
		"close_requested":runtime_close_requested, "freeze_observed":runtime_active_freeze_saved,
		"progress_busy":app.get("_progress_busy"), "progress_blocked":app.get("_progress_blocked")})


func _runtime_active_readback() -> void:
	var path: String = _argument("--runtime-proof=")
	_check(path.is_absolute_path() and "/.local/" in path, "active-close readback names the retained local original proof")
	if not path.is_absolute_path() or "/.local/" not in path:
		return
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_check(decoded.get("error") == OK, "complete active-close proof authenticates without float loss")
	if decoded.get("error") != OK:
		return
	var proof: Dictionary = decoded.payload
	var freeze: Variant = JSON.parse_string(FileAccess.get_file_as_string(proof.freeze_path))
	_check(freeze is Dictionary and freeze.get("pid") == proof.pid, "automatic exit retained a same-process real frozen-world witness")
	if not freeze is Dictionary:
		return
	var state: Dictionary = app.progress_session.inspect()
	_check(proof.pid != OS.get_process_id() and proof.profile_path == app.progress_path,
		"independent native PID reopens exactly the same original Windows binding")
	_check(state.get("state") == "SUSPENDED" and state.get("receipt", {}).get("phase") == "SUSPEND_READY"
		and state.get("hash") != proof.before_head and int(state.get("receipt", {}).get("revision", 0)) > int(proof.before_revision),
		"busy begin or claim close publishes a new complete SUSPEND_READY instead of abandoning STARTED or RESUME_CLAIMED")
	if state.get("state") != "SUSPENDED":
		return
	var receipt: Dictionary = state.receipt
	var reopened_exact_hash: String = RecordEncoding.fingerprint(receipt.envelope.world)
	_check(TransactionReceipt.same(receipt.base, proof.before_camp) and int(receipt.base.day) == int(proof.before_camp.day)
		and int(receipt.base.food) == int(proof.before_camp.food),
		"automatic exit preserves the entire original camp without day progression food debit or settlement")
	_check(RecordEncoding.fingerprint(receipt.rules.mission.generated) == proof.action_hash
		and receipt.envelope.world_hash == freeze.world_hash and reopened_exact_hash == freeze.world_exact_hash
		and freeze.action_hash == proof.action_hash,
		"new suspend retains the exact originally selected action and the real automatic-exit world")
	if proof.case == "close-claim":
		_check(receipt.envelope.world_hash == proof.world_hash and reopened_exact_hash == proof.world_exact_hash,
			"claim-close re-suspends the complete original world fingerprint without simulation")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var world: Expedition = app.expedition
	var restored: Dictionary = SortieSnapshot.capture(world) if world != null else {}
	_check(world != null and SurvivalContracts.fingerprint(restored) == receipt.envelope.world_hash
		and RecordEncoding.fingerprint(restored) == reopened_exact_hash,
		"actual Continue restores the exact safe-exit world in the independent process")
	if world == null:
		return
	if not app.pause_menu.root.visible:
		app.open_pause_menu()
	_check(app.pause_menu.buttons[4].is_visible_in_tree() and not app.pause_menu.buttons[4].disabled,
		"the original safe-suspend button is genuinely available after active-close recovery")
	await _tap(app.pause_menu.buttons[4])
	var final: Dictionary = app.progress_session.inspect()
	_check(app.expedition == null and final.get("state") == "SUSPENDED"
		and final.receipt.envelope.world_hash == receipt.envelope.world_hash
		and RecordEncoding.fingerprint(final.receipt.envelope.world) == reopened_exact_hash
		and TransactionReceipt.same(final.receipt.base, proof.before_camp),
		"original safe-suspend confirms the recovered world again without a reward ration or date change")
	_write("runtime-active-readback.json", {"pid":OS.get_process_id(), "proof_pid":proof.pid, "source_case":proof.case,
		"profile_path":app.progress_path, "reopened_head":state.hash, "reopened_revision":receipt.revision,
		"world_hash":receipt.envelope.world_hash, "world_hash_algorithm":"SurvivalContracts.fingerprint",
		"world_exact_hash":reopened_exact_hash, "world_exact_hash_algorithm":RecordEncoding.VERSION,
		"camp_hash":RecordEncoding.fingerprint(receipt.base),
		"final_head":final.get("hash", ""), "final_revision":final.get("receipt", {}).get("revision", 0),
		"physical_input":"NOT_VERIFIED", "source_injection":false})


func _runtime_writer_owner() -> void:
	var before: Dictionary = app.camp_snapshot()
	var committed: Dictionary = app.progress_session._transaction.recover()
	_write("writer-owner-ready.json", {"pid":OS.get_process_id(), "profile_path":app.progress_path,
		"camp_hash":RecordEncoding.fingerprint(before), "receipt_hash":committed.hash})
	var release_path: String = output.path_join("release-owner")
	var deadline: int = Time.get_ticks_msec() + 120000
	while not FileAccess.file_exists(release_path) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(FileAccess.file_exists(release_path), "test controller releases only its recorded writer owner")
	var after: Dictionary = app.progress_session._transaction.recover()
	_check(after.hash == committed.hash and TransactionReceipt.same(before, app.camp_snapshot()),
		"second-window lock competition cannot change the confirmed original camp")
	_write("writer-owner-released.json", {"pid":OS.get_process_id(), "receipt_hash":after.hash,
		"scope":"CONTROLLER_WAIT_NOT_GAMEPLAY_OR_PERFORMANCE_DELAY"})


func _runtime_unstarted_retry() -> void:
	var before: Dictionary = app.camp_snapshot()
	var choice: String = ""
	for item: String in before.journey.build.owned:
		if BuildState.investment_offer(before, item).available:
			choice = item
			break
	_check(not choice.is_empty(), "original confirmed camp can fund the retained retry request")
	if choice.is_empty():
		return
	var request: Dictionary = {"kind":"build_invest", "member_id":0, "value":BuildState.investment_value(before, choice)}
	var expected: Dictionary = CampEdit.propose(before, request)
	_check(not expected.is_empty(), "retained unstarted intent has a complete paid proposal")
	if expected.is_empty():
		return
	app.open_loadout()
	await _tap(app.loadout_panel.armory._nav[&"support"])
	var prior: Dictionary = app.progress_session._transaction.recover()
	# Exercise the recovery-controller state without a production fault hook.
	# OS thread exhaustion/start failure itself is explicitly NOT_INJECTED.
	app._unstarted_progress_payload = {"id":-1, "kind":"edit", "before":before.duplicate(true), "request":request.duplicate(true)}
	app._accept_transaction({"error":ERR_CANT_CREATE, "state":"BLOCKED", "reason":"PROGRESS_WORKER_START_FAILED", "camp":{}}, true)
	app.loadout_panel.refresh(app.camp_snapshot(), app._progress_message, true)
	_check(app.progress_session._pending_edit.is_empty() and TransactionReceipt.same(before, app.camp_snapshot()),
		"no session edit ran before the retained controller request is retried")
	await _tap(app.loadout_panel.armory._retry_button)
	var committed: Dictionary = app.progress_session._transaction.recover()
	_check(not app._progress_dirty and not app._progress_blocked and app._unstarted_progress_payload.is_empty()
		and TransactionReceipt.same(expected, app.camp_snapshot()) and committed.hash != prior.hash,
		"actual retry button redispatches the exact original paid request instead of acknowledging the old camp")
	_write("unstarted-retry.json", {"pid":OS.get_process_id(), "before":RecordEncoding.fingerprint(before),
		"expected":RecordEncoding.fingerprint(expected), "actual":RecordEncoding.fingerprint(app.camp_snapshot()),
		"before_head":prior.hash, "after_head":committed.hash, "request":request,
		"scope":"DIRECTED_CONTROLLER_STATE_RETRY_WITH_REAL_NATIVE_BUTTON",
		"actual_thread_start_failure":"NOT_INJECTED", "query_worker_exception":"NOT_INJECTED"})


func _runtime_close_edit() -> void:
	var before: Dictionary = app.camp_snapshot()
	var choice: String = ""
	for item: String in before.journey.build.owned:
		if BuildState.investment_offer(before, item).available:
			choice = item
			break
	_check(not choice.is_empty(), "original camp can pay for a real close-during-edit enhancement")
	if choice.is_empty():
		return
	var request: Dictionary = {"kind":"build_invest", "member_id":0, "value":BuildState.investment_value(before, choice)}
	var expected: Dictionary = CampEdit.propose(before, request)
	_check(not expected.is_empty(), "close-during-edit records the complete paid proposal before dispatch")
	if expected.is_empty():
		return
	var proof: Dictionary = {"pid":OS.get_process_id(), "profile_path":app.progress_path,
		"before":before, "expected":expected, "request":request, "camp_hash":RecordEncoding.fingerprint(expected)}
	var encoded: String = RecordEncoding.stringify(proof)
	_check(not encoded.is_empty(), "close-during-edit proof is complete and exact")
	var file: FileAccess = FileAccess.open(output.path_join("runtime-close-edit-proof.json"), FileAccess.WRITE)
	file.store_string(encoded)
	file.close()
	app.open_loadout()
	await _tap(app.loadout_panel.armory._nav[&"support"])
	var panel: BuildItemsPanel = app.loadout_panel.build_panel
	panel._upgrade_choice.select(panel._index_for(panel._upgrade_choice, choice))
	panel._refresh_upgrade()
	await _tap(panel._upgrade_button)
	await _tap(panel._confirmation.get_ok_button())
	if not runtime_close_requested:
		_check(false, "NOT_COVERED: real edit worker completed before any native rendered frame observed it alive")
		return
	for index: int in range(600):
		await process_frame
	_check(false, "busy edit close exits normally after the original operation reaches a safe boundary")


func _runtime_close_edit_readback() -> void:
	var path: String = _argument("--runtime-proof=")
	_check(path.is_absolute_path() and "/.local/" in path, "close-edit readback uses the retained isolated exact proof")
	if not path.is_absolute_path() or "/.local/" not in path:
		return
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_check(decoded.get("error") == OK, "close-edit retained proposal authenticates")
	if decoded.get("error") != OK:
		return
	var proof: Dictionary = decoded.payload
	var committed: Dictionary = app.progress_session._transaction.recover()
	_check(proof.pid != OS.get_process_id() and proof.profile_path == app.progress_path
		and RecordEncoding.fingerprint(app.camp_snapshot()) == proof.camp_hash,
		"cold native process recovers exactly one original paid edit after busy close")
	_check(committed.get("receipt", {}).get("phase") == "EDIT_COMMITTED", "busy close retains the acknowledged edit instead of reopening a second purchase")
	_write("runtime-close-edit-readback.json", {"pid":OS.get_process_id(), "receipt_hash":committed.hash,
		"camp_hash":RecordEncoding.fingerprint(app.camp_snapshot()), "proof_pid":proof.pid})


func _runtime_edit() -> void:
	_check(runtime_fault in ["before_camp_write", "after_record_publish"], "known original edit failure boundary")
	var before: Dictionary = app.camp_snapshot()
	var choice: String = ""
	for item: String in before.journey.build.owned:
		if BuildState.investment_offer(before, item).available:
			choice = item
			break
	_check(not choice.is_empty(), "genuine camp can pay for an owned passive enhancement")
	if choice.is_empty():
		return
	var request: Dictionary = {"kind":"build_invest", "member_id":0, "value":BuildState.investment_value(before, choice)}
	var expected: Dictionary = CampEdit.propose(before, request)
	_check(not expected.is_empty(), "paid M48 enhancement has a complete original proposal")
	if expected.is_empty():
		return
	app.open_loadout()
	await _tap(app.loadout_panel.armory._nav[&"support"])
	var panel: BuildItemsPanel = app.loadout_panel.build_panel
	panel._upgrade_choice.select(panel._index_for(panel._upgrade_choice, choice))
	panel._refresh_upgrade()
	await _tap(panel._upgrade_button)
	_check(panel._confirmation.visible, "real enhancement preview requires an explicit confirmation")
	var observations: Dictionary = {"publishes":0, "failures":0}
	app.progress_session.fault_hook = func(point: String) -> Error:
		if point == "after_record_publish": observations.publishes += 1
		if point == runtime_fault and (point != "after_record_publish" or observations.publishes == 2):
			observations.failures += 1
			return ERR_CANT_CREATE
		return OK
	await _tap(panel._confirmation.get_ok_button())
	app.progress_session.fault_hook = Callable()
	var progress: ProductionProgress = app.progress_session
	var identity: String = progress._pending_edit
	var failed: Dictionary = progress._transaction.recover()
	var disk: Dictionary = progress._transaction._save.read_transaction_exact()
	_check(observations.failures == 1 and app._progress_dirty and app._progress_blocked and not identity.is_empty(),
		"one directed I/O failure retains the original enhancement for retry")
	_check(TransactionReceipt.same(before, app.camp_snapshot()) and TransactionReceipt.same(progress._pending_edit_request, request),
		"failed acknowledgment preserves displayed balances and exact original request")
	_check(failed.receipt.phase == ("EDIT_READY" if runtime_fault == "before_camp_write" else "EDIT_COMMITTED")
		and disk.error == OK and TransactionReceipt.same(disk.data, before if runtime_fault == "before_camp_write" else expected),
		"real disk and journal expose the exact prewrite or lost-ACK phase")
	await _shot("paid-edit-failure-retry")
	await _tap(app.loadout_panel.armory._retry_button)
	var committed: Dictionary = progress._transaction.recover()
	var repeated: Dictionary = progress._transaction.commit_edit(identity)
	_check(not app._progress_dirty and not app._progress_blocked and TransactionReceipt.same(expected, app.camp_snapshot())
		and committed.hash == repeated.get("hash"), "actual retry button confirms exactly one enhancement and debit")
	await _shot("paid-edit-confirmed")
	_runtime_proof(before, expected, request, failed, disk, committed, observations)


func _runtime_return() -> void:
	liquidate_surplus = true
	prefer_compact_funding = true
	_check(runtime_fault in ["before_camp_write", "after_record_publish"], "known original return failure boundary")
	if EconomyBuildV1.level(app.camp_snapshot(), "supply") == 0:
		if not await _fund("build", "supply") or not await _economy("build", "supply"):
			return
	var world: Expedition = await _ordinary_supply()
	if world == null:
		return
	# The funding outings above gather only necessary resources. The fault outing
	# deliberately takes nothing, leaving real storage room for the facility grant.
	runtime_bank_fault = true
	await _finish_outing(world)
	runtime_bank_fault = false


func _collect(world: Expedition, desired_food: int) -> void:
	await super._collect(world, mini(desired_food, 2) if runtime_case == "return" else desired_food)


func _extract(world: Expedition) -> void:
	await _until(world, func() -> bool: return world.elapsed >= world.tuning.bus_ready_seconds)
	world.request_bus_action()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.BOARDING)
	world.request_bus_gather()
	await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
	# Finish now authenticates on the serial worker before the original bus
	# departure animation starts. Fixed frame counts cannot stand in for that ACK.
	await _frame()
	for index: int in range(1500):
		if not world.bus_view.running():
			break
		world.step(STEP)
		if index % 30 == 0:
			await _frame()
	var gathered: Vector2i = world.bus_view.final_boarding
	_check(app.phase == app.Phase.RESULT and gathered.x == gathered.y and gathered.y == world.living_count(),
		"actual bus completes departure after full result authentication")
	await _hold(3)


func _bank(world: Expedition) -> Dictionary:
	if not runtime_bank_fault:
		return await super._bank(world)
	await _extract(world)
	var progress: ProductionProgress = app.progress_session
	var ready: Dictionary = progress._transaction.recover()
	_check(ready.get("receipt", {}).get("phase") == "RESULT_READY", "real bus departure has a fully frozen result before confirmation")
	if ready.get("receipt", {}).get("phase") != "RESULT_READY":
		return {}
	var before: Dictionary = app.camp_snapshot()
	var expected: Dictionary = ready.receipt.envelope.result.camp
	var token: Dictionary = RunTransaction.token_for(ready.receipt)
	_check(int(expected.last_day.get("facility_food", 0)) > 0, "return includes genuine automatic facility food")
	_check(int(expected.last_day.get("facility_stored", 0)) > 0,
		"automatic facility food actually enters storage instead of entirely overflowing")
	_check(world.food_loot == 0 and world.loot == 0 and world.weapon_loot.is_empty(),
		"directed zero-loot fault outing uses only the original bus wait gathering and departure")
	var observations: Dictionary = {"failures":0}
	progress.fault_hook = func(point: String) -> Error:
		if point == runtime_fault:
			observations.failures += 1
			return ERR_CANT_CREATE
		return OK
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	progress.fault_hook = Callable()
	var failed: Dictionary = progress._transaction.recover()
	var disk: Dictionary = progress._transaction._save.read_transaction_exact()
	_check(observations.failures == 1 and app._progress_blocked and app._progress_dirty
		and TransactionReceipt.same(before, app.camp_snapshot()), "failed return acknowledgment leaves the original displayed camp and real retry")
	_check(disk.error == OK and TransactionReceipt.same(disk.data, before if runtime_fault == "before_camp_write" else expected),
		"facility return preserves exact before-write or committed disk state")
	await _shot("facility-return-failure-retry")
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var committed: Dictionary = progress._transaction.recover()
	var repeated: Dictionary = progress._transaction.commit(token)
	_check(not app._progress_blocked and not app._progress_dirty and committed.hash == repeated.get("hash")
		and TransactionReceipt.same(expected, app.camp_snapshot()), "actual return retry preserves one food grant date resource and ability result")
	_check(EconomyBuildV1.result_problem(committed.receipt).is_empty(), "original complete M48 result contract still authenticates")
	await _shot("facility-return-confirmed")
	_runtime_proof(before, expected, token, failed, disk, committed, observations)
	return committed


func _runtime_proof(before: Dictionary, expected: Dictionary, request: Dictionary, failed: Dictionary,
		disk: Dictionary, committed: Dictionary, observations: Dictionary) -> void:
	runtime_evidence = {"pid":OS.get_process_id(), "case":runtime_case, "fault":runtime_fault,
		"profile_path":app.progress_path, "before":before, "expected":expected, "request":request,
		"failed":_runtime_receipt_evidence(failed),
		"disk_after_failure":{"error":disk.get("error", FAILED), "reason":disk.get("reason", ""), "data":disk.get("data", {})},
		"committed":_runtime_receipt_evidence(committed), "observations":observations,
		"camp_hash":RecordEncoding.fingerprint(expected), "receipt_hash":committed.hash,
		"scope":"DIRECTED_ZERO_LOOT_NORMAL_BUS_RETURN" if runtime_case == "return" else "NORMAL_BUSINESS_AND_WIDGET_RETRY_DIRECTED_IO_FAULT"}
	var encoded: String = RecordEncoding.stringify(runtime_evidence)
	_check(not encoded.is_empty(), "complete fault evidence encodes without float loss")
	var file: FileAccess = FileAccess.open(output.path_join("runtime-proof.json"), FileAccess.WRITE)
	file.store_string(encoded)
	file.close()


func _runtime_receipt_evidence(value: Dictionary) -> Dictionary:
	# Recovery also contains integer-keyed internal revision maps. The Exact JSON
	# contract intentionally accepts string keys only; retain the complete receipt
	# and scalar recovery verdict rather than passing those private maps to the codec.
	return {"error":value.get("error", FAILED), "reason":value.get("reason", ""),
		"state":value.get("state", ""), "hash":value.get("hash", ""),
		"receipt":value.get("receipt", {}), "confirmed_deaths":value.get("confirmed_deaths", [])}


func _runtime_readback() -> void:
	var path: String = _argument("--runtime-proof=")
	_check(path.is_absolute_path() and "/.local/" in path, "cold readback uses a retained local fault proof")
	if not path.is_absolute_path() or "/.local/" not in path:
		return
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_check(decoded.get("error") == OK, "retained exact fault evidence authenticates")
	if decoded.get("error") != OK:
		return
	var proof: Dictionary = decoded.payload
	var committed: Dictionary = app.progress_session._transaction.recover()
	_check(proof.pid != OS.get_process_id() and proof.profile_path == app.progress_path,
		"independent PID reopens the identical original Windows binding")
	_check(committed.hash == proof.receipt_hash and RecordEncoding.fingerprint(app.camp_snapshot()) == proof.camp_hash,
		"cold process preserves the one receipt and all money tools instances food repairs and specialty state")
	_write("runtime-readback.json", {"pid":OS.get_process_id(), "proof_pid":proof.pid, "receipt":committed.hash,
		"camp_hash":RecordEncoding.fingerprint(app.camp_snapshot()), "binding":app.progress_path})
