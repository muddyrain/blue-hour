extends SceneTree
## Real registered/edit receipts exercise projection reuse after complete fresh source reads.

var rows: Array[Dictionary] = []
var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var output: String = ""


func _initialize() -> void:
	root.unfocusable = true
	_run.call_deferred()


func _run() -> void:
	var local_root: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(local_root):
		quit(2)
		return
	output = OS.get_user_data_dir().path_join("m49-catalog-evidence")
	if DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await app._new_game("scavenge", {"version":CatalogProgress.VERSION, "unlock":""},
		{"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	var progress: ProductionProgress = app.progress_session
	var transaction: RunTransaction = progress._transaction
	_check(transaction != null and not app._progress_blocked, "ordinary isolated registration succeeds")
	if transaction != null:
		var journal: ReceiptJournal = transaction._journal
		for index: int in range(3):
			var head: Dictionary = journal.read_all()
			if head.error != OK:
				_check(false, "complete real source authenticates before rename")
				break
			var identity: String = String(head.receipt.base.profile_id) + ":edit:" + RunSave.new_profile_id()
			var ready: Dictionary = transaction.prepare_edit(head.hash, identity,
				{"kind":"rename", "member_id":1, "value":"catalog-%d" % index})
			var committed: Dictionary = transaction.commit_edit(identity) if ready.error == OK else ready
			_check(committed.error == OK, "normal rename creates a legal immutable receipt pair: " + String(committed.get("reason", "OK")))
			if committed.error != OK:
				break
		var reader: CatalogProgress = CatalogProgress.new(progress._path)
		var first: Dictionary = _refresh(reader, "initial-complete-projection")
		_check(first.get("error") == OK, "complete projection derives from the real registered history")
		for index: int in range(10):
			var again: Dictionary = _refresh(reader, "fresh-source-refresh-%d" % index)
			var meta: Dictionary = profiles.back().metadata
			_check(TransactionReceipt.same(first, again), "repeated complete source refresh preserves the full projection")
			_check(int(meta.get("journal_record_bytes_reads", 0)) >= 7,
				"memo hit still rereads all seven actual source generations")
			_check(int(meta.get("catalog_projection_hits", 0)) >= 3,
				"unlock, discovery and specialty reuse only their witnessed pure projections")
		var history: Dictionary = reader._history(app.progress_path + ".txn")
		_check(not history.has("reason"), "original bound history is available for projection isolation checks")
		if not history.has("reason"):
			var projection: Dictionary = reader._specialty_projection(history)
			projection.discoveries["caller-poison"] = {"value":-1}
			projection.event["caller-poison"] = true
			var separate: Dictionary = reader._specialty_projection(history)
			_check(not separate.discoveries.has("caller-poison") and not separate.event.has("caller-poison"),
				"caller-owned projection dictionaries cannot poison the shared proof")
			var earlier: Dictionary = history.duplicate(false)
			earlier.through = 1
			_check(reader._projection_key(earlier, "specialty", "") != reader._projection_key(history, "specialty", ""),
				"an older acknowledged binding revision cannot use the newer projection")
			_check(reader._projection_key(history, "discovery", "a") != reader._projection_key(history, "discovery", "b"),
				"discovery proof includes the exact unlock dependency")
			var changed_hashes: Dictionary = history.duplicate(false)
			changed_hashes.hashes = history.hashes.duplicate()
			changed_hashes.hashes[1] = "0".repeat(64)
			_check(reader._projection_key(changed_hashes, "specialty", "") != reader._projection_key(history, "specialty", ""),
				"caller-altered history hashes cannot select a previously authenticated projection")
			var other_slot: CatalogProgress = CatalogProgress.new(progress._path + ".other")
			_check(other_slot._projection_key(history, "specialty", "") != reader._projection_key(history, "specialty", ""),
				"a projection from another progress slot has a different pure context")
		_negative_sources(reader, journal, first)
	app.audio.shutdown()
	app.queue_free()
	await process_frame
	var report: Dictionary = {"pid":OS.get_process_id(), "rows":rows, "failures":failures,
		"profiles":profiles, "scope":"real-registration-and-edits; fresh-full-source-projection-memo"}
	_write(output.path_join("report.json"), JSON.stringify(report, "\t", true, true).to_utf8_buffer())
	print("M49_CATALOG_PROOF ", JSON.stringify({"checks":rows.size(), "failures":failures, "output":output}))
	quit(0 if failures.is_empty() else 1)


func _negative_sources(reader: CatalogProgress, journal: ReceiptJournal, expected: Dictionary) -> void:
	var root_file: String = journal.directory.path_join("00000001/record.json")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(root_file)
	var original_sha: String = FileAccess.get_sha256(root_file)
	_write(output.path_join("retained-root.bin"), original)
	_write(output.path_join("fault-target.json"), JSON.stringify({"target":root_file,
		"retained":output.path_join("retained-root.bin"), "sha256":original_sha}).to_utf8_buffer())
	var changed: PackedByteArray = original.duplicate()
	changed[0] ^= 1
	_write(root_file, changed)
	var corrupted: Dictionary = reader.refresh(Callable())
	var corrupt_preserved: bool = FileAccess.get_file_as_bytes(root_file) == changed
	_write(root_file, original)
	_check(corrupted.get("error") != OK and corrupt_preserved,
		"one changed byte is fully checked and rejected despite a prior projection memo")
	var final_folder: String = journal.directory.path_join("00000007")
	var final_file: String = final_folder.path_join("record.json")
	var final_raw: PackedByteArray = FileAccess.get_file_as_bytes(final_file)
	_write(output.path_join("retained-final.bin"), final_raw)
	_write(final_file, final_raw.slice(0, int(final_raw.size() / 2.0)))
	var truncated: Dictionary = reader.refresh(Callable())
	_write(final_file, final_raw)
	_check(truncated.get("error") != OK, "truncated actual source cannot use an old authenticated projection")
	var absent_folder: String = journal.directory.path_join("00000009")
	_check(DirAccess.make_dir_absolute(absent_folder) == OK, "unknown generation fixture is isolated")
	_write(absent_folder.path_join("record.json"), original)
	var unknown: Dictionary = reader.refresh(Callable())
	DirAccess.remove_absolute(absent_folder.path_join("record.json"))
	DirAccess.remove_absolute(absent_folder)
	_check(unknown.get("error") != OK, "fresh directory enumeration rejects an added generation gap")
	var retained_folder: String = output.path_join("retained-final-generation")
	var moved: Error = DirAccess.rename_absolute(final_folder, retained_folder)
	_check(moved == OK, "isolated final generation is retained before simulating loss")
	if moved == OK:
		var missing: Dictionary = reader.refresh(Callable())
		var restored: Error = DirAccess.rename_absolute(retained_folder, final_folder)
		_check(missing.get("error") != OK and restored == OK,
			"a deleted acknowledged generation is rejected and its original directory is restored")
	var recovered: Dictionary = reader.refresh(Callable())
	_check(FileAccess.get_sha256(root_file) == original_sha and FileAccess.get_file_as_bytes(final_file) == final_raw
		and TransactionReceipt.same(expected, recovered),
		"restoring exact original source bytes recovers the same complete projection")
	_write(output.path_join("source-negatives.json"), JSON.stringify({"corrupted":corrupted,
		"truncated":truncated, "unknown_generation":unknown, "original_sha256":original_sha,
		"restored_sha256":FileAccess.get_sha256(root_file), "recovered":recovered}, "\t", true, true).to_utf8_buffer())


func _refresh(reader: CatalogProgress, label: String) -> Dictionary:
	FreezeProfile.enabled = true
	FreezeProfile.start({"label":label})
	var result: Dictionary = reader.refresh(Callable())
	FreezeProfile.finish()
	profiles.append(FreezeProfile.latest.duplicate(true))
	return result


func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()


func _check(ok: bool, label: String) -> void:
	rows.append({"pass":ok, "label":label})
	if not ok:
		failures.append(label)
		printerr("M49_CATALOG_PROOF_FAIL ", label)
