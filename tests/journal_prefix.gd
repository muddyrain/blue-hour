extends SceneTree
## Isolated transaction fixtures; trailing JSON whitespace grows the raw working set without fake game rewards.

const PAD_BYTES: int = 3_200_000
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var metrics: Array[Dictionary] = []
var output: String

func _initialize() -> void:
	root.unfocusable = true
	call_deferred("_run")

func expect(ok: bool, label: String) -> void:
	rows.append({"pass":ok, "label":label})
	if not ok:
		failures.append(label)
		printerr("JOURNAL_PREFIX_FAIL ", label)

func _run() -> void:
	if "/.local/" not in OS.get_user_data_dir().replace("\\", "/"):
		quit(2)
		return
	output = OS.get_user_data_dir().path_join("journal-prefix-evidence")
	if DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._new_game()
	var transaction: RunTransaction = app.progress_session._transaction
	if transaction == null:
		expect(false, "ordinary isolated fixture registers a transaction")
		_finish()
		return
	var journal: ReceiptJournal = transaction._journal
	for index: int in range(5):
		var head: Dictionary = journal.read_all()
		if head.error != OK:
			expect(false, "fixture head authenticates before rename")
			break
		var before: Dictionary = TransactionReceipt.camp(head.receipt)
		var identity: String = before.profile_id + ":edit:" + RunSave.new_profile_id()
		var request: Dictionary = {"kind":"rename", "member_id":1, "value":"前缀验收%d" % index}
		var ready: Dictionary = transaction.prepare_edit(head.hash, identity, request)
		var committed: Dictionary = transaction.commit_edit(identity) if ready.error == OK else ready
		expect(committed.error == OK and committed.receipt.phase == "EDIT_COMMITTED", "normal rename edit forms a valid immutable generation pair")
		if committed.error != OK: break
	var original: Dictionary = journal.read_all()
	if original.error != OK:
		expect(false, "complete fixture authenticates before raw growth")
		_finish()
		return
	var count: int = int(original.receipt.revision)
	var total: int = 0
	for index: int in range(1, count + 1):
		var path: String = journal.directory.path_join("%08d/record.json" % index)
		var text: String = FileAccess.get_file_as_string(path)
		var bytes: int = text.to_utf8_buffer().size()
		expect(bytes < PAD_BYTES, "unmodified fixture record fits the bounded growth sample")
		if bytes >= PAD_BYTES: break
		_write(path, text + " ".repeat(PAD_BYTES - bytes))
		total += PAD_BYTES
	expect(total > ReceiptJournal.MAX_CACHED_BYTES and total < ReceiptJournal.MAX_TOTAL_BYTES,
		"real source byte working set exceeds the old decoded-cache budget within unchanged journal limits")
	var cold: Dictionary = _read_profile(journal, "grown-cold")
	expect(cold.error == OK and cold.hash == original.hash, "complete first scan authenticates the larger valid source bytes")
	var warm: Dictionary = _read_profile(ReceiptJournal.new(journal.directory), "grown-warm")
	var warm_meta: Dictionary = metrics.back().get("metadata", {})
	expect(warm.error == OK and warm.hash == original.hash and TransactionReceipt.same(warm.receipt, cold.receipt), "coordinator recreation reuses only the fully witnessed prefix result")
	expect(int(warm_meta.get("journal_prefix_reused_records", 0)) == count and int(warm_meta.get("record_cache_misses", 0)) == 0,
		"warm scan avoids historical decode even above the old cache working set")
	expect(int(warm_meta.get("journal_record_bytes_reads", 0)) == count,
		"warm scan still rereads every full real record")
	warm.receipt.base.cash += 100
	warm.hashes[1] = "0".repeat(64)
	warm.identities.append("caller-poison")
	warm.claimed_event["caller-poison"] = true
	var isolated: Dictionary = journal.read_all()
	expect(isolated.error == OK and isolated.hash == cold.hash and TransactionReceipt.same(isolated.receipt, cold.receipt)
		and isolated.hashes == cold.hashes and isolated.identities == cold.identities and not isolated.claimed_event.has("caller-poison"),
		"returned receipt, revision hashes, identities, and claimed state cannot mutate the private boundary")
	var owned_prefix: Dictionary = journal._prefix_snapshot()
	journal._replace_prefix({})
	var orphan_charged: bool = true
	for entry: Dictionary in ReceiptJournal._record_cache.values():
		if entry.raw_shared or int(entry.cache_bytes) < entry.raw.size() + ReceiptJournal.CACHE_METADATA_BYTES:
			orphan_charged = false
	expect(journal._prefix_snapshot().is_empty() and orphan_charged and ReceiptJournal._cached_bytes <= ReceiptJournal.MAX_CACHED_BYTES,
		"controlled prefix clearing reprices every remaining real raw witness within the same budget")
	journal._replace_prefix(owned_prefix)
	var rebound: bool = true
	for entry: Dictionary in ReceiptJournal._record_cache.values():
		var alias: bool = false
		for original_raw: PackedByteArray in owned_prefix.raw_records:
			if is_same(entry.raw, original_raw) and entry.raw == original_raw: alias = true
		if not entry.raw_shared or not alias: rebound = false
	expect(rebound, "trusted prefix restoration rebinds the actual PackedByteArray aliases before sharing raw charges")
	_single_record_cases(journal)
	_directory_cases(journal)
	var first: String = journal.directory.path_join("00000001/record.json")
	var preserved: String = FileAccess.get_file_as_string(first)
	_write(first, "x" + preserved.substr(1))
	var changed: Dictionary = _read_profile(journal, "same-length-corruption")
	expect(changed.error != OK and int(metrics.back().metadata.get("journal_prefix_fallbacks", 0)) == 1,
		"same-length byte corruption invalidates the prefix before complete reauthentication")
	_write(first, preserved)
	expect(journal.read_all().error == OK, "restoring the exact original bytes restores the valid chain")
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(preserved)).payload
	decoded.base.cash += 1
	_write(first, RecordEncoding.stringify(decoded))
	expect(journal.read_all().error != OK, "rehashed earlier semantic tampering is rejected with an unchanged latest generation")
	_write(first, preserved)
	var base: Dictionary = journal.read_all()
	expect(base.error == OK, "original prefix remains intact after negative source fixtures")
	_tail_cases(journal, base)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--prefix-claimed-journal="):
			_claimed_case(arg.trim_prefix("--prefix-claimed-journal="))
	app.audio.shutdown()
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	_finish()

func _single_record_cases(journal: ReceiptJournal) -> void:
	var path: String = journal.directory.path_join("00000001/record.json")
	var preserved: String = FileAccess.get_file_as_string(path)
	var source_hash: String = FileAccess.get_sha256(path)
	ReceiptJournal._record_cache.clear()
	ReceiptJournal._cached_bytes = 0
	var row: Dictionary = _read_record_profile(journal, path, "single-witnessed-record")
	var profile: Dictionary = metrics.back()
	expect(row.error == OK and int(profile.metadata.get("record_prefix_shape_hits", 0)) == 1
		and int(profile.metadata.get("journal_record_bytes_reads", 0)) == 1,
		"independent record read witnesses complete real bytes against an authenticated prefix")
	expect(int(profile.stages.get("exact.unpack", {}).get("calls", 0)) == 1 and int(profile.stages.get("receipt.problem", {}).get("calls", 0)) == 0,
		"independent record read still checks ExactJSON while reusing only the pure shape proof")
	var outer: Dictionary = JSON.parse_string(preserved)
	outer.sha256 = "0".repeat(64)
	_write(path, JSON.stringify(outer, "", true, true))
	ReceiptJournal._record_cache.clear()
	ReceiptJournal._cached_bytes = 0
	var wrong_hash: Dictionary = _read_record_profile(journal, path, "single-invalid-transport-hash")
	expect(wrong_hash.error != OK and int(metrics.back().stages.get("exact.unpack", {}).get("calls", 0)) == 1,
		"independent record tampering cannot bypass ExactJSON integrity")
	var changed: Dictionary = RecordEncoding.unpack(JSON.parse_string(preserved)).payload
	changed.base.cash = -1 # Structurally invalid even before chain/binding checks.
	_write(path, RecordEncoding.stringify(changed))
	ReceiptJournal._record_cache.clear()
	ReceiptJournal._cached_bytes = 0
	var invalid: Dictionary = _read_record_profile(journal, path, "single-rehashed-source-change")
	expect(invalid.error != OK and int(metrics.back().metadata.get("record_prefix_shape_hits", 0)) == 0
		and int(metrics.back().stages.get("receipt.problem", {}).get("calls", 0)) == 1,
		"new or rehashed bytes receive complete original receipt validation")
	_write(path, preserved)
	expect(FileAccess.get_sha256(path) == source_hash and journal.read_all().error == OK,
		"single-record negatives restore the exact original source")

func _read_record_profile(journal: ReceiptJournal, path: String, label: String) -> Dictionary:
	FreezeProfile.enabled = true
	FreezeProfile.start({"fixture":label})
	var result: Dictionary = journal._read_record(path)
	FreezeProfile.finish()
	metrics.append(FreezeProfile.latest.duplicate(true))
	return result

func _directory_cases(journal: ReceiptJournal) -> void:
	journal.fault = func(point: String) -> Error: return ERR_CANT_OPEN if point == "before_directory_list" else OK
	expect(journal.read_all().error != OK, "warm prefix never bypasses a directory listing failure")
	journal.fault = Callable()
	var folder: String = journal.directory.path_join("00000001")
	var extra: String = folder.path_join("extra.bin")
	_write(extra, "unexpected")
	expect(journal.read_all().error != OK, "warm prefix rejects an added generation file")
	DirAccess.remove_absolute(extra)
	var moved: String = output.path_join("withheld-generation")
	expect(DirAccess.rename_absolute(folder, moved) == OK, "isolate a published generation for a missing-source negative")
	expect(journal.read_all().error != OK, "warm prefix rejects missing earlier generations")
	expect(DirAccess.rename_absolute(moved, folder) == OK, "restore the exact published generation")
	var stage: String = journal.directory.path_join(".stage-" + RunSave.new_profile_id())
	DirAccess.make_dir_absolute(stage)
	var staged: Dictionary = journal.read_all()
	expect(staged.error == OK and stage.get_file() in staged.unpublished, "current unpublished stages are enumerated independently of the cached prefix")
	_write(stage.path_join("extra.bin"), "invalid")
	expect(journal.read_all().error != OK, "warm prefix rejects illegal stage contents")
	DirAccess.remove_absolute(stage.path_join("extra.bin"))
	DirAccess.remove_absolute(stage)
	var access: DirAccess = DirAccess.open(folder)
	var link_error: Error = access.create_link(folder.path_join("record.json"), folder.path_join("linked-record"))
	if link_error == OK:
		expect(journal.read_all().error != OK, "warm prefix rejects a new symbolic link")
		DirAccess.remove_absolute(folder.path_join("linked-record"))
	else:
		rows.append({"pass":true, "label":"symbolic-link fixture unavailable on this platform", "status":"NOT_VERIFIED", "error":link_error})
	expect(journal.read_all().error == OK, "directory negatives leave the original complete source intact")

func _tail_cases(journal: ReceiptJournal, base: Dictionary) -> void:
	var before: Dictionary = TransactionReceipt.camp(base.receipt)
	var identity: String = before.profile_id + ":edit:" + RunSave.new_profile_id()
	var request: Dictionary = {"kind":"rename", "member_id":1, "value":"合法尾部"}
	var next: Dictionary = CampEdit.record(before, request, identity, base.receipt)
	expect(not next.is_empty(), "new tail is a real business proposal")
	if next.is_empty(): return
	next.previous_hash = base.hash
	var folder: String = journal.directory.path_join("%08d" % int(next.revision))
	var file: String = folder.path_join("record.json")
	_write(file, RecordEncoding.stringify(next))
	var tail: Dictionary = _read_profile(journal, "valid-new-tail")
	expect(tail.error == OK and tail.receipt.phase == "EDIT_READY" and int(metrics.back().metadata.get("journal_prefix_reused_records", 0)) == int(base.receipt.revision),
		"new tail is fully authenticated after the witnessed boundary")
	expect(int(metrics.back().stages.get("journal.decode_record", {}).get("calls", 0)) == 1, "only the new tail record is decoded")
	_remove_tail(folder)
	journal.read_all()
	var variants: Dictionary = {}
	var invalid: Dictionary = next.duplicate(true)
	invalid.previous_hash = "0".repeat(64)
	variants["chain hash"] = invalid
	invalid = next.duplicate(true)
	invalid.phase = "EDIT_COMMITTED"
	variants["illegal transition"] = invalid
	invalid = next.duplicate(true)
	invalid.rules.data_version = 999
	variants["unknown policy version"] = invalid
	invalid = CampEdit.record(before, request, base.identities[0], base.receipt)
	invalid.previous_hash = base.hash
	variants["previous transaction identity reuse"] = invalid
	for label: String in variants:
		_write(file, RecordEncoding.stringify(variants[label]))
		var rejected: Dictionary = _read_profile(journal, "invalid-tail-" + label)
		expect(rejected.error != OK and int(metrics.back().metadata.get("journal_prefix_reused_records", 0)) == int(base.receipt.revision), "original tail checks reject " + label + " after prefix reuse")
		_remove_tail(folder)
		journal.read_all()

func _claimed_case(source: String) -> void:
	expect(source.is_absolute_path() and "/.local/" in source, "claimed-source comparison uses an isolated original journal")
	if not source.is_absolute_path() or "/.local/" not in source: return
	var target: String = output.path_join("claimed/journal")
	var access: DirAccess = DirAccess.open(source)
	if access == null:
		expect(false, "claimed original journal is readable")
		return
	var generations: PackedStringArray = access.get_directories()
	generations.sort()
	var boundary: int = -1
	for index: int in range(generations.size()):
		if not generations[index].is_valid_int(): continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source.path_join(generations[index]).path_join("record.json"))
		var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(bytes.get_string_from_utf8()))
		if decoded.get("error") != OK: continue
		_write_bytes(target.path_join(generations[index]).path_join("record.json"), bytes)
		if decoded.payload.phase == "RESUME_CLAIMED":
			boundary = index
			break
	expect(boundary >= 0, "real original source contains a resume claim")
	if boundary < 0: return
	var journal: ReceiptJournal = ReceiptJournal.new(target)
	var claimed: Dictionary = journal.read_all()
	expect(claimed.error == OK and TransactionReceipt.same(claimed.claimed_event, TaskActions.claimed_event(claimed.receipt))
		and TransactionReceipt.same(claimed.claimed_recon, ReconKnowledge.claimed(claimed.receipt)) and TransactionReceipt.same(claimed.claimed_billboard, BillboardIntelV1.claimed(claimed.receipt)),
		"full authentication establishes the real claimed boundary state")
	var warm: Dictionary = journal.read_all()
	expect(warm.error == OK and TransactionReceipt.same(warm.claimed_event, claimed.claimed_event) and TransactionReceipt.same(warm.claimed_recon, claimed.claimed_recon) and TransactionReceipt.same(warm.claimed_billboard, claimed.claimed_billboard),
		"prefix reuse preserves all three real claimed histories")
	if boundary + 1 < generations.size():
		var next: String = generations[boundary + 1]
		_write_bytes(target.path_join(next).path_join("record.json"), FileAccess.get_file_as_bytes(source.path_join(next).path_join("record.json")))
		var extended: Dictionary = journal.read_all()
		expect(extended.error == OK, "original next generation remains valid across the cached claimed boundary")

func _read_profile(journal: ReceiptJournal, label: String) -> Dictionary:
	FreezeProfile.enabled = true
	FreezeProfile.start({"fixture":label})
	var result: Dictionary = journal.read_all()
	FreezeProfile.finish()
	metrics.append(FreezeProfile.latest.duplicate(true))
	return result

func _write(path: String, text: String) -> void:
	_write_bytes(path, text.to_utf8_buffer())

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()

func _remove_tail(folder: String) -> void:
	DirAccess.remove_absolute(folder.path_join("record.json"))
	DirAccess.remove_absolute(folder)

func _finish() -> void:
	_write(output.path_join("report.json"), JSON.stringify({"checks":rows, "failures":failures, "metrics":metrics}, "\t", true, true))
	print("JOURNAL_PREFIX " + JSON.stringify({"checks":rows.size(), "failures":failures, "evidence":output}))
	quit(0 if failures.is_empty() else 1)
