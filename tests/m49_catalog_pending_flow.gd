extends "res://tests/m49_comparison_flow.gd"
## Real Continue from an authentic frozen READY; only the catalog source fault is directed.
## Independent verification uses --catalog-readback=<absolute Exact proof path>.


func _journey() -> void:
	_check(false, "catalog-pending proof requires --flow-resume and an original Windows-bound progress slot")


func _resume() -> void:
	var proof_path: String = _catalog_argument("--catalog-readback=")
	if not proof_path.is_empty():
		await _catalog_readback(proof_path)
		return
	await _catalog_fault_and_retry()


func _catalog_argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _catalog_continue() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())


func _catalog_fault_and_retry() -> void:
	var slot: String = ProjectSettings.globalize_path(app.progress_path).replace("\\", "/").simplify_path()
	_check(DisplayServer.get_name() != "headless" and "/.local/m49/" in slot,
		"catalog fault is restricted to a genuine native task-owned isolated slot")
	if DisplayServer.get_name() == "headless" or "/.local/m49/" not in slot:
		return
	var ready: Dictionary = app.progress_session.inspect()
	_check(ready.error == OK and ready.get("state") == "RECOVERY_READY" and ready.get("receipt", {}).get("phase") == "RESULT_READY",
		"startup has fully authenticated the original frozen RESULT_READY before the catalog fault")
	if ready.error != OK or ready.get("receipt", {}).get("phase") != "RESULT_READY":
		return
	var before: Dictionary = ready.receipt.base.duplicate(true)
	var expected: Dictionary = ready.receipt.envelope.result.camp.duplicate(true)
	var original_sources: Dictionary = _catalog_sources(slot)
	var folder: String = slot + ".catalog"
	var fault_path: String = folder.path_join(SpecializationProgress.RECORD_PREFIX + String(before.profile_id) + ".json")
	_check(not FileAccess.file_exists(fault_path) and not DirAccess.dir_exists_absolute(fault_path) and ProgressWriter._unlinked(fault_path),
		"the task creates one new catalog file and never overwrites an existing source")
	if FileAccess.file_exists(fault_path) or DirAccess.dir_exists_absolute(fault_path) or not ProgressWriter._unlinked(fault_path):
		return
	var invalid_text: String = JSON.stringify({"m49_catalog_pending_probe":true, "pid":OS.get_process_id()}, "", true, true) + "\n"
	_check(DirAccess.make_dir_recursive_absolute(folder) == OK, "task-owned catalog fault directory is available")
	var file: FileAccess = FileAccess.open(fault_path, FileAccess.WRITE)
	_check(file != null, "one task-owned invalid catalog record is created after startup verification")
	if file == null:
		return
	file.store_string(invalid_text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	var fault_sha: String = FileAccess.get_sha256(fault_path)
	_check(write_error == OK and FileAccess.get_file_as_string(fault_path) == invalid_text
		and JSON.parse_string(invalid_text) is Dictionary, "fault bytes round-trip as JSON but contain no authenticated catalog event")
	var injected_sources: Dictionary = _catalog_sources(slot)
	_check(TransactionReceipt.same(original_sources.journal, injected_sources.journal)
		and original_sources.camp == injected_sources.camp and original_sources.binding == injected_sources.binding,
		"catalog-only injection preserves every original journal camp and binding byte")
	# No token, result page, settlement, or gameplay state is manually wired here.
	await _catalog_continue()
	var pending: Dictionary = app._progress_view.duplicate(true)
	var acknowledged: Dictionary = app.progress_session.inspect()
	var disk: Dictionary = app.progress_session._transaction._save.read_transaction_exact()
	var pending_sources: Dictionary = _catalog_sources(slot)
	var pending_message: String = app._progress_message
	var retry: Button = app._retry_button
	var is_pending: bool = pending.get("state") == "CATALOG_PENDING" and pending.get("camp_saved", false) and pending.get("error", OK) != OK
	_check(is_pending and app._progress_blocked and app._progress_dirty and app._catalog_view.get("error", OK) != OK,
		"normal Continue durably saves the camp while reporting actual catalog synchronization failure")
	_check(pending.get("reason") == "CATALOG_SYNC:CATALOG_EVENT_HASH",
		"the original catalog byte and transport validator rejects the exact injected unauthenticated event")
	_check(acknowledged.error == OK and acknowledged.receipt.phase == "COMMITTED"
		and acknowledged.receipt.transaction_id == ready.receipt.transaction_id
		and int(acknowledged.receipt.revision) == int(ready.receipt.revision) + 1
		and acknowledged.hash == pending.get("hash"), "one original READY becomes one real COMMITTED ACK before catalog synchronization")
	_check(disk.error == OK and TransactionReceipt.same(disk.get("data", {}), expected)
		and TransactionReceipt.same(app.camp_snapshot(), expected), "disk and displayed balances show the acknowledged complete expected camp")
	_check(retry.is_visible_in_tree() and not retry.disabled and app._progress_message.contains("营地已保存")
		and app._progress_message.contains("核验未完成"),
		"pending screen distinguishes saved camp from incomplete catalog and exposes its real retry control")
	var camp_label: String = app.get_node("Interface/Screen/Title/Camp").text
	_check(camp_label.contains("营地已保存") and not camp_label.contains("存档未加载")
		and not app._camp_backdrop._names.text.contains("名册尚未载入"),
		"acknowledged pending-sync camp and roster never claim that the saved data was not loaded")
	await _shot("catalog-pending-real-retry")
	var reset: Button = app.get_node("Interface/Screen/Title/Reset")
	if reset.is_visible_in_tree() and not reset.disabled:
		await _tap(reset)
		_check(not app._new_game_confirmation.visible and app._progress_blocked
			and app._progress_dirty, "actual new-journey input cannot consume unverified catalog qualifications")
	var pending_evidence: Dictionary = {"scope":"NORMAL_CONTINUE_FROZEN_READY_WITH_DIRECTED_CATALOG_SOURCE_FAULT",
		"pid":OS.get_process_id(), "profile_path":app.progress_path, "before":before, "expected":expected,
		"ready":_catalog_receipt(ready), "pending":_catalog_receipt(pending), "acknowledged":_catalog_receipt(acknowledged),
		"disk_after_ack":{"error":disk.error, "data":disk.get("data", {})},
		"fault":{"path":fault_path, "sha256":fault_sha, "bytes":invalid_text.to_utf8_buffer().size(), "text":invalid_text},
		"sources_before":original_sources, "sources_pending":pending_sources,
		"displayed_camp_hash":RecordEncoding.fingerprint(app.camp_snapshot()), "message":pending_message,
		"message_after_new_journey_attempt":app._progress_message,
		"retry_visible":retry.is_visible_in_tree(), "retry_enabled":not retry.disabled}
	_catalog_write_exact("catalog-pending-before-retry.json", pending_evidence)
	var removed: bool = _catalog_remove_created(fault_path, fault_sha)
	_check(removed, "only the exact task-created invalid catalog file is removed before retry")
	if not removed or not is_pending or not retry.is_visible_in_tree() or retry.disabled:
		return
	await _tap(retry)
	var final: Dictionary = app.progress_session.inspect()
	var final_camp: Dictionary = app.camp_snapshot()
	_check(final.error == OK and not app._progress_blocked and not app._progress_dirty and not app._requires_continue
		and app.camp_scene.is_visible_in_tree() and app._catalog_view.get("error", FAILED) == OK,
		"actual retry completes full catalog authentication and restores the confirmed ordinary camp")
	_check(final.hash == acknowledged.hash and int(final.receipt.revision) == int(acknowledged.receipt.revision)
		and TransactionReceipt.same(final_camp, expected) and TransactionReceipt.same(final.camp, expected),
		"catalog retry changes no acknowledged journal head reward ration date settlement or camp field")
	await _shot("catalog-resynced-confirmed")
	var final_sources: Dictionary = _catalog_sources(slot)
	_check(TransactionReceipt.same(pending_sources.journal, final_sources.journal)
		and pending_sources.camp == final_sources.camp and pending_sources.binding == final_sources.binding,
		"real catalog retry preserves every acknowledged journal camp and binding byte")
	var proof: Dictionary = pending_evidence.duplicate(true)
	proof.final = _catalog_receipt(final)
	proof.final_camp = final_camp
	proof.final_catalog = app._catalog_view.duplicate(true)
	proof.sources_final = final_sources
	proof.before_counters = _catalog_counters(before)
	proof.expected_counters = _catalog_counters(expected)
	proof.final_counters = _catalog_counters(final_camp)
	proof.expected_camp_hash = RecordEncoding.fingerprint(expected)
	proof.committed_hash = final.hash
	proof.fault_removed = not FileAccess.file_exists(fault_path)
	proof.branch_provenance = "normal native title Continue and original hunger consent -> ProductionProgress.activate -> original transaction.commit ACK -> refresh_catalog fails -> _catalog_pending -> Main._accept_transaction -> visible retry -> save_camp -> same session.retry/activate -> complete authenticated catalog; no manual token or result wiring"
	_catalog_write_exact("catalog-pending-proof.json", proof)


func _catalog_readback(source: String) -> void:
	source = source.replace("\\", "/").simplify_path()
	var local: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	_check(source.is_absolute_path() and source.begins_with(local) and FileAccess.file_exists(source),
		"independent catalog readback uses the retained isolated Exact proof")
	if not source.is_absolute_path() or not source.begins_with(local) or not FileAccess.file_exists(source):
		return
	var raw: String = FileAccess.get_file_as_string(source)
	var parsed: Variant = JSON.parse_string(raw)
	var decoded: Dictionary = RecordEncoding.unpack(parsed) if parsed is Dictionary else {"error":ERR_PARSE_ERROR}
	_check(decoded.get("error") == OK, "full original catalog fault retry proof authenticates")
	if decoded.get("error") != OK:
		return
	var proof: Dictionary = decoded.payload
	_check(int(proof.pid) != OS.get_process_id() and proof.profile_path == app.progress_path,
		"a different native PID reopens the identical original Windows binding")
	await _catalog_continue()
	var final: Dictionary = app.progress_session.inspect()
	var actual: Dictionary = app.camp_snapshot()
	_check(final.error == OK and final.receipt.phase == "COMMITTED" and final.hash == proof.committed_hash
		and final.receipt.root_id == proof.final.receipt.root_id,
		"independent process authenticates the exact same one committed result and root")
	_check(TransactionReceipt.same(actual, proof.expected) and RecordEncoding.fingerprint(actual) == proof.expected_camp_hash
		and TransactionReceipt.same(_catalog_counters(actual), proof.expected_counters),
		"independent Continue preserves every expected resource instance ration date and settlement counter")
	_check(not app._progress_blocked and not app._progress_dirty and app._catalog_view.get("error", FAILED) == OK
		and not FileAccess.file_exists(proof.fault.path), "cold original pipeline completes full catalog authentication with the task fault absent")
	_catalog_write_exact("catalog-readback.json", {"scope":"INDEPENDENT_NATIVE_PID_ORIGINAL_BOUND_PATH_FULL_CATALOG_READBACK",
		"pid":OS.get_process_id(), "source_pid":proof.pid, "source":source, "profile_path":app.progress_path,
		"state":_catalog_receipt(final), "camp":actual, "camp_hash":RecordEncoding.fingerprint(actual),
		"catalog":app._catalog_view.duplicate(true), "counters":_catalog_counters(actual),
		"sources":_catalog_sources(ProjectSettings.globalize_path(app.progress_path))})


func _catalog_remove_created(path: String, expected_sha: String) -> bool:
	var slot: String = ProjectSettings.globalize_path(app.progress_path).replace("\\", "/").simplify_path()
	if path.get_base_dir() != slot + ".catalog" or not ProgressWriter._unlinked(path) \
			or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != expected_sha:
		return false
	return DirAccess.remove_absolute(path) == OK


func _catalog_sources(slot: String) -> Dictionary:
	var journal: Dictionary = {}
	var directory: String = slot + ".txn/journal"
	if DirAccess.dir_exists_absolute(directory):
		for generation: String in DirAccess.get_directories_at(directory):
			var path: String = directory.path_join(generation).path_join("record.json")
			if FileAccess.file_exists(path):
				journal[generation] = FileAccess.get_sha256(path)
	var catalog: Dictionary = {}
	if DirAccess.dir_exists_absolute(slot + ".catalog"):
		for name: String in DirAccess.get_files_at(slot + ".catalog"):
			catalog[name] = FileAccess.get_sha256((slot + ".catalog").path_join(name))
	return {"camp":_catalog_file_sha(slot), "backup":_catalog_file_sha(slot + ".bak"),
		"binding":_catalog_file_sha(slot + ".txn/binding.json"), "journal":journal, "catalog":catalog}


func _catalog_file_sha(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "ABSENT"


func _catalog_receipt(state: Dictionary) -> Dictionary:
	return {"error":state.get("error", FAILED), "state":state.get("state", ""), "reason":state.get("reason", ""),
		"camp_saved":state.get("camp_saved", false), "hash":state.get("hash", ""),
		"receipt":state.get("receipt", {}), "camp":state.get("camp", {})}


func _catalog_counters(camp: Dictionary) -> Dictionary:
	return {"day":camp.day, "cash":camp.cash, "food":camp.food, "settled_sorties":camp.settled_sorties,
		"profile_id":camp.profile_id, "root_id":camp.journey.root_id, "last_settlement_id":camp.last_settlement_id,
		"camp_spending":camp.camp_spending, "active_member_ids":camp.journey.active_member_ids.duplicate()}


func _catalog_write_exact(name: String, value: Dictionary) -> void:
	var encoded: String = RecordEncoding.stringify(value)
	_check(not encoded.is_empty(), "full catalog evidence encodes with exact numbers: " + name)
	if encoded.is_empty():
		return
	var file: FileAccess = FileAccess.open(output.path_join(name), FileAccess.WRITE)
	_check(file != null, "catalog evidence file opens: " + name)
	if file == null:
		return
	file.store_string(encoded)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	_check(error == OK and FileAccess.get_file_as_string(output.path_join(name)) == encoded,
		"full catalog evidence preserves its exact serialized bytes: " + name)
