extends "res://tests/m47_run_replay_flow.gd"
## Archive capacity fixtures use real registered roots and directed lethal damage.
## They are not twenty complete campaign victories or physical-input evidence.

var _archive_started: int = 0
var _archive_mode: String = ""
var _archive_target: int = 0
var _startup_ms: float = 0.0
var _startup_feedback: Dictionary = {}
var _startup_wait: Dictionary = {}
var _measured_returns: Array[Dictionary] = []
var _measure_return: bool = false


func _initialize() -> void:
	_archive_started = Time.get_ticks_usec()
	super()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--flow-output="): output = arg.trim_prefix("--flow-output=")
		if arg == "--flow-resume": resume = true
		if arg.begins_with("--archive-mode="): _archive_mode = arg.trim_prefix("--archive-mode=")
		if arg.begins_with("--archive-count="): _archive_target = int(arg.trim_prefix("--archive-count="))
	root.unfocusable = true
	root.gui_embed_subwindows = true
	if not output.is_absolute_path() or "/.local/" not in output \
			or "/.local/" not in OS.get_user_data_dir().replace("\\", "/") \
			or FileAccess.file_exists(output.path_join("report.json")) \
			or _archive_mode not in ["build", "measure", "diagnose"] or _archive_target not in [0, 5, 20]:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	app = load("res://src/app/main.tscn").instantiate()
	viewport.add_child(app)
	_playable_startup_contract = _detect_playable_startup_contract()
	if not await _await_archive_startup():
		quit(1)
		return
	_write("startup-ready.json", {"pid":OS.get_process_id(), "script_to_title_frame_ms":_startup_ms,
		"native":DisplayServer.get_name() != "headless", "pending":_playable_startup_pending(),
		"scope":"complete verification followed by the first observed ready-title frame; excludes external process launch",
		"feedback":"startup-feedback.json", "wait_frames":"startup-wait.json"})
	_check(app.progress_path == PlayableEntry.progress_path()
		and app.progress_session._writer.owns(app.progress_path) and ProgressWriter._unlinked(app.progress_path),
		"archive fixture owns only its isolated canonical path")
	if _archive_mode == "build":
		await _build_archives()
	elif _archive_mode == "measure":
		await _measure_archives()
	else:
		await _diagnose_archive()
	if DisplayServer.get_name() != "headless":
		_check(OS.has_feature("windows") or not focus_observations.has(true), "native archive fixture never receives desktop focus")
	_write("report.json", {"checks":rows, "failures":failures, "pid":OS.get_process_id(),
		"camp":app.camp_snapshot(), "path":app.progress_path, "root_focused":root.has_focus(),
		"native":DisplayServer.get_name() != "headless", "physical_input":"NOT_TESTED",
		"scope":"DIRECTED_ARCHIVE_SCALE", "archive_count":_archives().size(), "mode":_archive_mode,
		"startup_to_first_title_frame_ms":_startup_ms, "startup_feedback":_startup_feedback,
		"startup_wait":_startup_wait, "returns":_measured_returns})
	app.audio.shutdown()
	await create_timer(0.2).timeout
	app.queue_free()
	app = null
	await process_frame
	viewport.queue_free()
	viewport = null
	await process_frame
	quit(0 if failures == 0 else 1)


func _await_archive_startup() -> bool:
	var native: bool = DisplayServer.get_name() != "headless"
	if native:
		await RenderingServer.frame_post_draw
	else:
		await _frame()
	var first_frame: int = Time.get_ticks_usec()
	var pending: bool = _playable_startup_pending()
	var overlay: Node = app.find_child("StartupVerification",true,false)
	var verification: Control = _startup_visible_control(overlay)
	if native and pending:
		_check(verification != null,"the first native pending frame contains the actual startup verification layer")
	var capture_started: int = Time.get_ticks_usec()
	var screenshot_error: Error = OK
	if native:
		screenshot_error = viewport.get_texture().get_image().save_png(output.path_join("startup-feedback.png"))
		_check(screenshot_error == OK,"first visible startup feedback is retained as a native screenshot")
	_startup_feedback = {"pid":OS.get_process_id(),"native":native,"pending":pending,
		"first_visible_frame_ms":(first_frame-_archive_started)/1000.0 if native else null,
		"script_to_first_observed_frame_usec":first_frame-_archive_started,
		"content_kind":"STARTUP_VERIFICATION_NOT_OPERABLE_TITLE" if pending else "READY_TITLE",
		"verification_node_found":overlay != null,"verification_control_visible":verification != null,
		"verification_rect":_startup_rect(verification.get_global_rect()) if verification != null else [],
		"screenshot":"startup-feedback.png" if native else "NOT_NATIVE",
		"screenshot_error":screenshot_error,"screenshot_capture_usec":Time.get_ticks_usec()-capture_started,
		"scope":"first native rendered feedback; pending feedback is never counted as an operable title"}
	_write("startup-feedback.json",_startup_feedback)
	var input_probe: Dictionary = {"status":"NOT_EXERCISED_NO_PENDING_NATIVE_FRAME"}
	if native and pending:
		input_probe = _probe_startup_enter()
	_write("startup-input-probe.json",input_probe)
	var gaps: Array[int] = []
	var previous: int = first_frame
	var largest: int = 0
	var pending_frames: int = int(pending and native)
	var observed_frames: int = int(native)
	var deadline: int = Time.get_ticks_msec()+900000
	var ready_frame: int = first_frame
	while _playable_startup_pending() and Time.get_ticks_msec() < deadline:
		await _frame()
		if native:
			await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		var gap: int = now-previous
		gaps.append(gap)
		largest = maxi(largest,gap)
		previous = now
		ready_frame = now
		if native:
			observed_frames += 1
			pending_frames += int(_playable_startup_pending())
	var complete: bool = not _playable_startup_pending()
	_startup_ms = (ready_frame-_archive_started)/1000.0
	_startup_wait = {"pid":OS.get_process_id(),"native":native,"initial_pending":pending,"complete":complete,
		"pending_native_frames":pending_frames,"observed_native_frames_including_ready":observed_frames,
		"observed_wait_intervals":gaps.size(),"max_frame_gap_usec":largest,"max_frame_gap_ms":largest/1000.0,
		"frame_gaps_usec":gaps,"verification_wait_wall_ms":(ready_frame-first_frame)/1000.0,
		"complete_script_to_title_frame_ms":_startup_ms,"timeout_seconds":900,"input_probe":"startup-input-probe.json",
		"scope":"actual rendered frame intervals while verification is pending, plus its ready frame; first interval includes screenshot/probe overhead; no simulated clock"}
	_write("startup-wait.json",_startup_wait)
	_check(complete,"complete native startup verification finishes before the title can be used")
	if complete:
		var title: Control = app.get_node("Interface/Screen/Title") as Control
		_check(title.is_visible_in_tree(),"the separately measured ready frame contains the ordinary title")
	return complete


func _startup_visible_control(node: Node) -> Control:
	if node == null: return null
	if node is Control and node.is_visible_in_tree() and node.size.x > 0.0 and node.size.y > 0.0:
		return node as Control
	for child: Node in node.get_children():
		var control: Control = _startup_visible_control(child)
		if control != null: return control
	return null


func _probe_startup_enter() -> Dictionary:
	# Read file witnesses only. Never call inspect/refresh or access the active writer.
	var before: Dictionary = _startup_source_witness()
	var pending_before: bool = _playable_startup_pending()
	var pressed_handled: bool = false
	for down: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = down
		viewport.push_input(event,true)
		if down: pressed_handled = viewport.is_input_handled()
	var after: Dictionary = _startup_source_witness()
	var dialog: Variant = app.get("_new_game_confirmation")
	var opened: bool = dialog is Window and dialog.visible
	var started: bool = app.get("expedition") != null
	_check(pending_before and pressed_handled and not opened and not started,
		"native Enter is consumed during verification without opening or starting a journey")
	_check(before == after,"pending Enter preserves the witnessed current save backup binding and generation names")
	return {"status":"NATIVE_PENDING_ENTER_PROBED","pending_before":pending_before,
		"pending_after":_playable_startup_pending(),"pressed_handled":pressed_handled,
		"new_game_dialog_opened":opened,"expedition_started":started,"before":before,"after":after,
		"scope":"read-only current slot witnesses around one native Enter; no progress-session/writer methods called"}


func _startup_source_witness() -> Dictionary:
	var slot: String = PlayableEntry.progress_path()
	var files: Dictionary = {}
	for path: String in [slot,slot+".bak",slot+".txn/binding.json"]:
		files[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	var generations: PackedStringArray = DirAccess.get_directories_at(slot+".txn/journal")
	generations.sort()
	return {"files":files,"generation_directories":Array(generations)}


func _startup_rect(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]


func _open_original_camp() -> bool:
	if not resume:
		return await _new_trip("scavenge")
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	var inspected: Dictionary = app.progress_session.inspect()
	if inspected.get("state") == "ENDED":
		return await _new_trip("scavenge")
	_check(inspected.get("state") == "CAMP" and app.camp_scene.is_visible_in_tree() and not app._progress_blocked,
		"cold continuation opens its exact current camp")
	return inspected.get("state") == "CAMP" and not app._progress_blocked


func _build_archives() -> void:
	if not await _open_original_camp():
		return
	var generated: Array[Dictionary] = []
	while _archives().size() < _archive_target:
		var before: Dictionary = app.camp_snapshot()
		var run_id: String = before.profile_id
		var root_id: String = before.journey.root_id
		var world: Expedition = await _ordinary_supply()
		if world == null:
			return
		# Explicit directed fixture: the genuine damage gate writes the permanent deaths.
		for actor: FieldActor in world.survivors:
			actor.take_damage(actor.health + 1.0)
		await _until(world, func() -> bool: return world.phase == Expedition.Phase.FINISHED)
		var terminal: Dictionary = app.progress_session.inspect()
		_check(terminal.get("state") == "ENDED" and terminal.get("receipt", {}).get("phase") == "COMMITTED"
			and terminal.receipt.base.profile_id == run_id and world.living_count() == 0,
			"directed damage reaches the original durable permanent-death terminal")
		if terminal.get("state") != "ENDED":
			return
		var terminal_hash: String = terminal.get("hash", "")
		if not await _new_trip("scavenge"):
			return
		var folder: String = app.progress_path + SpecializationProgress.ARCHIVE_PREFIX + run_id
		var history: Dictionary = CatalogProgress.new(app.progress_path)._history(folder)
		var valid: bool = not history.has("reason") and history.run_id == run_id and history.root_id == root_id \
			and history.tip.phase == "COMMITTED" and TransactionReceipt.camp(history.tip).get("journey", {}).get("state") == "FAILED"
		# The committed envelope, not the departure base, owns the terminal state.
		_check(valid and app.camp_snapshot().profile_id != run_id and app.camp_snapshot().journey.root_id != root_id,
			"normal replacement preserves one distinct authenticated archived root")
		generated.append({"run_id":run_id, "root_id":root_id, "seed":before.journey.seed,
			"earlier_confirmed_returns":before.settled_sorties, "terminal_hash":terminal_hash,
			"archive":folder, "binding_sha256":FileAccess.get_sha256(folder.path_join("binding.json")),
			"scope":"DIRECTED_LETHAL_DAMAGE"})
		_write("generated.json", {"target":_archive_target, "generated":generated, "count":_archives().size()})
		if not valid:
			return
	_check(_archives().size() == _archive_target, "requested archive count was produced through actual distinct roots")
	_verify_all_archives()


func _archives() -> Array[String]:
	var result: Array[String] = []
	var prefix: String = app.progress_path.get_file() + SpecializationProgress.ARCHIVE_PREFIX
	for folder: String in DirAccess.get_directories_at(app.progress_path.get_base_dir()):
		if folder.begins_with(prefix):
			result.append(app.progress_path.get_base_dir().path_join(folder))
	result.sort()
	return result


func _verify_all_archives() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var runs: Array[String] = []
	var roots: Array[String] = []
	var catalog: CatalogProgress = CatalogProgress.new(app.progress_path)
	for folder: String in _archives():
		var history: Dictionary = catalog._history(folder)
		var valid: bool = not history.has("reason")
		_check(valid, "full independent source validation: " + folder.get_file())
		if not valid:
			continue
		_check(history.run_id not in runs and history.root_id not in roots
			and history.tip.phase == "COMMITTED" and history.run_id != app.camp_snapshot().profile_id
			and TransactionReceipt.camp(history.tip).get("journey", {}).get("campaign", {}).get("outcome") == "DEFEAT",
			"archived run/root are unique and distinct from the live journey")
		runs.append(history.run_id)
		roots.append(history.root_id)
		records.append({"run_id":history.run_id, "root_id":history.root_id, "through":history.through,
			"root_hash":history.hashes.get(1), "head_hash":history.hashes.get(history.through), "outcome":"DEFEAT",
			"binding_sha256":FileAccess.get_sha256(folder.path_join("binding.json"))})
	var projection: Dictionary = app.progress_session.refresh_catalog()
	_check(projection.get("error") == OK, "all archived and live sources form a valid current specialty projection")
	_write("archive-manifest.json", {"archives":records, "count":records.size(), "projection":projection,
		"scope":"DIRECTED_ARCHIVE_SCALE_NOT_COMPLETE_CAMPAIGNS"})
	return records


func _measure_archives() -> void:
	_check(_archives().size() == _archive_target, "cold process starts with the requested exact archive count")
	var samples: Array[Dictionary] = []
	# New reader has no instance-level specialty verification memo. Main's own title load
	# already ran; process-cold title cost is captured separately before this read.
	var reader: CatalogProgress = CatalogProgress.new(app.progress_path)
	for index: int in range(4):
		var started: int = Time.get_ticks_usec()
		var projection: Dictionary = reader.refresh(Callable())
		var elapsed: float = (Time.get_ticks_usec() - started) / 1000.0
		_check(projection.get("error") == OK, "archive catalog raw sample remains fully source-valid")
		samples.append({"kind":"specialty_read", "temperature":"cold_reader" if index == 0 else "warm_reader",
			"iteration":index, "wall_ms":elapsed, "projection":projection})
	if not await _open_original_camp():
		return
	for index: int in range(4):
		var before: Dictionary = app.camp_snapshot()
		var request: Dictionary = {"kind":"rename", "member_id":1, "value":"计时%02d" % index}
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = app.progress_session.edit(before, request)
		var durable_at: int = Time.get_ticks_usec()
		var accepted: bool = app._accept_transaction(result, true)
		var completed_at: int = Time.get_ticks_usec()
		_check(accepted and SurvivorRoster.member(app.camp_snapshot().crew, 1).call_sign == request.value,
			"timed camp operation is a real durable edit with normal projection")
		samples.append({"kind":"camp_edit", "temperature":"first_in_process" if index == 0 else "warm_process",
			"iteration":index, "submit_ms":(durable_at - started) / 1000.0,
			"with_ui_projection_ms":(completed_at - started) / 1000.0,
			"before_hash":RecordEncoding.fingerprint(before), "receipt_hash":result.get("hash", ""), "request":request})
		if not accepted:
			break
	_measure_return = true
	for index: int in range(4):
		var world: Expedition = await _ordinary_supply()
		if world == null:
			break
		await _collect(world, 6)
		await _finish_outing(world)
		if app._progress_blocked or app.camp_snapshot().journey.state != "ACTIVE":
			break
	_measure_return = false
	_check(_measured_returns.size() == 4, "four actual source-valid return confirmations measured")
	_write("archive-timing.json", {"archive_count":_archive_target, "pid":OS.get_process_id(),
		"startup_to_first_title_frame_ms":_startup_ms, "samples":samples, "return_confirmations":_measured_returns,
		"native":DisplayServer.get_name() != "headless", "renderer":"gl_compatibility",
		"scope":"cold_reader_and_three_hot_reads; real_camp_edits; accelerated_simulation_with_wall_clock_confirmation_only",
		"title_scope":"script_initialization_through_main_load_and_first_title_frame; excludes_external_process_creation"})
	_verify_all_archives()


func _bank(world: Expedition) -> Dictionary:
	if not _measure_return:
		return await super._bank(world)
	await _extract(world)
	var before: Dictionary = app.camp_snapshot()
	var pending: Dictionary = app.progress_session.inspect()
	_check(pending.get("receipt", {}).get("phase") == "RESULT_READY" and not app._pending_settlement.is_empty(),
		"timed real return has the original pending result before confirmation")
	if app._pending_settlement.is_empty():
		return {}
	var token: Dictionary = app.progress_session.token.duplicate(true)
	var started: int = Time.get_ticks_usec()
	# The result button calls precisely this normal callback. Time excludes simulated movement.
	app.return_to_title()
	var ended: int = Time.get_ticks_usec()
	var committed: Dictionary = app.progress_session.inspect()
	var repeated: Dictionary = app.progress_session._transaction.commit(token)
	_check(committed.get("receipt", {}).get("phase") == "COMMITTED" and repeated.get("error") == OK
		and repeated.get("hash") == committed.get("hash") and not app._progress_blocked,
		"timed confirmation and retry retain one original committed receipt")
	_measured_returns.append({"iteration":_measured_returns.size(),
		"temperature":"first_in_process" if _measured_returns.is_empty() else "warm_process",
		"confirmation_ms":(ended - started) / 1000.0, "day":before.day,
		"action_id":world.supply.generated.id, "map_size":world.supply.generated.layout["size"],
		"map_type":world.supply.generated.layout.topology, "simulated_seconds":world.elapsed,
		"pending_hash":pending.get("hash", ""), "committed_hash":committed.get("hash", "")})
	return committed


func _diagnose_archive() -> void:
	_check(_archives().size() == _archive_target and _archive_target > 0, "diagnosis uses the actual nonempty archived sample")
	if _archives().is_empty() or not await _open_original_camp():
		return
	var target: String = _archives()[0].path_join("journal/00000001/record.json")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(target)
	var original_hash: String = FileAccess.get_sha256(target)
	var retained: String = output.path_join("retained-archive-root-record.bin")
	var stored: bool = _store_archive_bytes(retained, original)
	_check(stored and not original.is_empty() and ProgressWriter._unlinked(target), "original archived source bytes are retained before fault injection")
	if not stored or original.is_empty() or not ProgressWriter._unlinked(target):
		return
	_write("fault-target.json", {"target":target, "sha256":original_hash, "retained":retained})
	var before: Dictionary = app.progress_session.refresh_catalog()
	var live_hash: String = app.progress_session.inspect().get("hash", "")
	var corrupt: PackedByteArray = "[]\n".to_utf8_buffer()
	_store_archive_bytes(output.path_join("corrupt-archive-root-record.bin"), corrupt)
	if not _store_archive_bytes(target, corrupt):
		return
	var bad_started: int = Time.get_ticks_usec()
	var blocked: Dictionary = app.progress_session.refresh_catalog()
	var bad_ms: float = (Time.get_ticks_usec() - bad_started) / 1000.0
	var untouched: bool = FileAccess.get_file_as_bytes(target) == corrupt
	# No await between injection, diagnostic and restoration.
	var restored: bool = _store_archive_bytes(target, original) and FileAccess.get_sha256(target) == original_hash
	_check(blocked.get("error") != OK and String(blocked.get("reason", "")).begins_with("CATALOG_HISTORY_")
		and untouched, "corrupt archived source is rejected with a specific diagnostic and remains untouched")
	var after: Dictionary = app.progress_session.refresh_catalog()
	_check(restored and TransactionReceipt.same(before, after)
		and app.progress_session.inspect().get("hash", "") == live_hash,
		"restoring the retained exact source restores the same projection and live journey")
	_write("archive-corruption.json", {"target":target, "original_sha256":original_hash,
		"corrupt_sha256":corrupt.get_string_from_utf8().sha256_text(), "blocked":blocked, "diagnostic_ms":bad_ms,
		"corrupt_preserved":untouched, "restored":restored, "live_hash":live_hash, "projection":after})
	_verify_all_archives()


func _store_archive_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK and FileAccess.get_file_as_bytes(path) == bytes
