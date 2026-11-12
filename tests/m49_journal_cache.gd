extends SceneTree
## Isolated legal receipt copies test pure proofs, never player state or capacity campaigns.

const PAD_BYTES: int = 3_200_000
const PARALLEL_WORKERS: int = 3
const PARALLEL_ITERATIONS: int = 32
const PARALLEL_SNAPSHOTS: int = 8
var output: String = ""
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var parallel_evidence: Dictionary = {}


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks.append({"pass":ok, "label":label})
	if not ok:
		failures.append(label)
		printerr("M49_JOURNAL_CACHE_FAIL ", label)


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	output = OS.get_user_data_dir().path_join("m49-journal-cache-evidence")
	if DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await app._new_game("scavenge", {"version":CatalogProgress.VERSION, "unlock":""},
		{"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	var transaction: RunTransaction = app.progress_session._transaction
	_check(transaction != null and not app._progress_blocked, "ordinary isolated registration supplies authentic source receipts")
	if transaction != null:
		var source: ReceiptJournal = transaction._journal
		var initial: Dictionary = source.read_all()
		var before: Dictionary = TransactionReceipt.camp(initial.receipt)
		var identity: String = before.profile_id + ":edit:" + RunSave.new_profile_id()
		var ready: Dictionary = transaction.prepare_edit(initial.hash, identity,
			{"kind":"rename", "member_id":1, "value":"M49缓存复验"})
		_check(ready.error == OK and transaction.commit_edit(identity).error == OK,
			"a normal business edit creates a legal multi-generation chain")
		var original: Dictionary = source.read_all()
		_check(original.error == OK, "source chain authenticates before pure-cache copies")
		if original.error == OK:
			var manifest: Dictionary = _manifest(source.directory)
			var first: String = source.directory.path_join("00000001/record.json")
			var root_bytes: PackedByteArray = FileAccess.get_file_as_bytes(first)
			var left: ReceiptJournal = ReceiptJournal.new(output.path_join("left"))
			var right: ReceiptJournal = ReceiptJournal.new(output.path_join("right"))
			_copy(source.directory, left.directory, manifest)
			_copy(source.directory, right.directory, manifest)
			_cross_directory(left, right, original)
			_source_negatives(left, original)
			_eviction(left, root_bytes)
			await _parallel_cases(source, manifest, original, root_bytes)
			_check(_manifest(source.directory) == manifest, "all negative and capacity tests preserve the registered source bytes")
	app.audio.shutdown()
	app.queue_free()
	await process_frame
	var report: Dictionary = {"pid":OS.get_process_id(), "checks":checks, "failures":failures,
		"profiles":profiles, "parallel":parallel_evidence, "prefix_budget":ReceiptJournal.MAX_PREFIX_BYTES,
		"record_budget":ReceiptJournal.MAX_CACHED_BYTES,
		"scope":"DIRECTED_PURE_CACHE_AND_LEGAL_OUTER_WHITESPACE; NOT_ARCHIVE_CAMPAIGNS"}
	_write(output.path_join("report.json"), JSON.stringify(report, "\t").to_utf8_buffer())
	print("M49_JOURNAL_CACHE ", JSON.stringify({"checks":checks.size(), "failures":failures, "output":output}))
	quit(0 if failures.is_empty() else 1)


func _cross_directory(left: ReceiptJournal, right: ReceiptJournal, original: Dictionary) -> void:
	left._replace_prefix({})
	_check(left.read_all().error == OK and right.read_all().error == OK, "both real directories authenticate independently")
	var token: String = left.prefix_memo_token()
	var projection: Dictionary = {"rows":[{"value":7}], "discovery":{}}
	left.prefix_memo_put("pure-projection", projection, token)
	projection.rows[0].value = -1
	var read: Dictionary = _measure(left, "cross-directory-return")
	_check(read.error == OK and read.hash == original.hash
		and profiles.back().metadata.get("journal_prefix_hits", 0) == 1,
		"returning from another directory retains only the fully witnessed chain proof")
	_check(int(profiles.back().metadata.get("journal_record_bytes_reads", 0)) == int(original.receipt.revision),
		"a retained directory proof still enumerates and rereads every complete record")
	_check(left.prefix_memo_token() == token and left.prefix_memo_get("pure-projection", token).value.rows[0].value == 7,
		"complete identical rereads retain the projection token and isolate the put argument")
	var result: Dictionary = left.prefix_memo_get("pure-projection", token)
	result.value.rows[0].value = -8
	_check(left.prefix_memo_get("pure-projection", token).value.rows[0].value == 7,
		"returned projection dictionaries cannot poison later results")
	_check(left.prefix_memo_get("pure-projection", "stale-token").is_empty(), "a different request generation cannot read an old proof")
	left.prefix_memo_put("pure-projection", {"rows":[]}, "stale-token")
	_check(left.prefix_memo_get("pure-projection", token).value.rows[0].value == 7,
		"a stale producer cannot overwrite the current pure projection")
	var cached: Dictionary = left._prefix_snapshot().memo["pure-projection"]
	var damaged: PackedByteArray = cached.raw.duplicate()
	damaged[0] ^= 1
	cached.raw = damaged
	_check(left.prefix_memo_get("pure-projection", token).is_empty(),
		"damaged private projection bytes fall back before native decoding")
	left.prefix_memo_put("pure-projection", {"rows":[{"value":7}]}, token)
	_check(not left.prefix_memo_get("pure-projection", token).is_empty(), "a recomputed successful projection replaces damaged cache bytes")
	var held: Array[int] = []
	for index: int in range(10):
		_check(right.read_all().error == OK and left.read_all().error == OK, "continuous cross-directory refresh %d authenticates" % index)
		held.append(ReceiptJournal._prefix_bytes)
	_check(held.min() == held.max() and _accounting(),
		"ten refreshes hold a stable charged working set within the unchanged global budgets")
	var path: String = left.directory.path_join("00000001/record.json")
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var changed_bytes: PackedByteArray = original_bytes.duplicate()
	changed_bytes.append(32)
	_write(path, changed_bytes)
	_check(left.read_all().error == OK and left.prefix_memo_token() != token
		and left.prefix_memo_get("pure-projection", token).is_empty(),
		"even legal same-payload byte changes receive a new full-chain proof and invalidate old projections")
	_write(path, original_bytes)
	_check(left.read_all().error == OK, "legal changed-byte test restores the exact source")


func _source_negatives(reader: ReceiptJournal, original: Dictionary) -> void:
	var path: String = reader.directory.path_join("00000001/record.json")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var changed: PackedByteArray = bytes.duplicate()
	changed[0] ^= 1
	_write(path, changed)
	_check(reader.read_all().error != OK, "a warm multi-directory cache rejects a same-length changed byte")
	_write(path, bytes.slice(0, bytes.size() / 2))
	_check(reader.read_all().error != OK, "a warm cache rejects a truncated record")
	_write(path, bytes)
	var generation: String = reader.directory.path_join("00000002")
	var retained: String = output.path_join("retained-generation")
	_check(DirAccess.rename_absolute(generation, retained) == OK, "retain the original second generation outside the journal")
	_check(reader.read_all().error != OK, "a retained prefix never hides a missing generation")
	_check(DirAccess.rename_absolute(retained, generation) == OK, "restore the original generation directory")
	var unknown: String = reader.directory.path_join("unknown-generation")
	DirAccess.make_dir_absolute(unknown)
	_check(reader.read_all().error != OK, "a retained prefix rejects an unknown generation directory")
	DirAccess.remove_absolute(unknown)
	var restored: Dictionary = reader.read_all()
	_check(restored.error == OK and restored.hash == original.hash,
		"all source negatives restore the complete original chain without altered identities")


func _eviction(reader: ReceiptJournal, original: PackedByteArray) -> void:
	_check(original.size() < PAD_BYTES, "registration fits the bounded legal transport capacity fixture")
	if original.size() >= PAD_BYTES:
		return
	var padded: PackedByteArray = original.duplicate()
	padded.append_array(" ".repeat(PAD_BYTES - original.size()).to_utf8_buffer())
	var token: String = reader.prefix_memo_token()
	reader.prefix_memo_put("evicted-projection", {"value":9}, token)
	for index: int in range(22):
		var capacity: ReceiptJournal = ReceiptJournal.new(output.path_join("capacity-%02d" % index))
		_write(capacity.directory.path_join("00000001/record.json"), padded)
		_check(capacity.read_all().error == OK and _accounting(),
			"complete legal source %d fits one shared global prefix budget" % index)
	_check(ReceiptJournal._prefix_bytes <= ReceiptJournal.MAX_PREFIX_BYTES
		and ReceiptJournal._verified_prefixes.size() < 22
		and reader.prefix_memo_get("evicted-projection", token).is_empty(),
		"global byte pressure evicts whole old directory proofs and their projections")
	var reloaded: Dictionary = _measure(reader, "evicted-directory-reload")
	_check(reloaded.error == OK and profiles.back().metadata.get("journal_prefix_misses", 0) == 1
		and int(profiles.back().metadata.get("journal_record_bytes_reads", 0)) == int(reloaded.receipt.revision),
		"an evicted directory fully reauthenticates all original generations on return")
	reader._replace_prefix({})
	_check(ReceiptJournal._prefix_bytes == 0 and ReceiptJournal._verified_prefixes.is_empty() and _accounting(),
		"trusted clearing releases all directory proofs and recharges orphan record bytes")


func _accounting() -> bool:
	var prefix_bytes: int = 0
	for prefix: Dictionary in ReceiptJournal._verified_prefixes.values():
		prefix_bytes += int(prefix.charge)
	var record_bytes: int = 0
	var active: Dictionary = ReceiptJournal._verified_prefix
	for entry: Dictionary in ReceiptJournal._record_cache.values():
		var payload: int = entry.dto.size() if entry.has("dto") else int(entry.decoded_bytes)
		record_bytes += (0 if entry.raw_shared else entry.raw.size()) + payload + ReceiptJournal.CACHE_METADATA_BYTES
		if entry.raw_shared:
			var original: PackedByteArray = active.raw_index.get(entry.raw_identity, PackedByteArray())
			if not is_same(original, entry.raw) or entry.shared_generation != ReceiptJournal._prefix_generation:
				return false
	return prefix_bytes == ReceiptJournal._prefix_bytes and prefix_bytes <= ReceiptJournal.MAX_PREFIX_BYTES \
		and record_bytes == ReceiptJournal._cached_bytes and record_bytes <= ReceiptJournal.MAX_CACHED_BYTES \
		and ReceiptJournal._record_cache.size() <= ReceiptJournal.MAX_CACHED_RECORDS


func _parallel_cases(source: ReceiptJournal, manifest: Dictionary, expected: Dictionary, root_bytes: PackedByteArray) -> void:
	var gate: Semaphore = Semaphore.new()
	var workers: Array[Thread] = []
	var directories: Array[String] = []
	var witnesses: Array[Dictionary] = []
	var root_row: Dictionary = source._read_record(source.directory.path_join("00000001/record.json"))
	_check(root_row.error == OK, "parallel fixtures start from an authenticated ordinary registration")
	if root_row.error != OK:
		return
	for worker_index: int in range(PARALLEL_WORKERS):
		var folder: String = output.path_join("parallel-%d" % worker_index)
		var journal_path: String = folder.path_join("journal")
		_copy(source.directory, journal_path, manifest)
		var reader: ReceiptJournal = ReceiptJournal.new(journal_path)
		_check(reader.read_all().error == OK, "independent read-only journal %d authenticates before parallel use" % worker_index)
		directories.append(journal_path)
		var records: Array[String] = []
		for index: int in range(PARALLEL_ITERATIONS):
			# Distinct legal transport bytes create real cache insertions between
			# the other readers' snapshot/planning and publication boundaries.
			var padded: PackedByteArray = root_bytes.duplicate()
			padded.append_array(" ".repeat(65_536 + worker_index * PARALLEL_ITERATIONS + index).to_utf8_buffer())
			var path: String = folder.path_join("records/%02d.json" % index)
			_write(path, padded)
			records.append(path)
		var worker: Thread = Thread.new()
		var error: Error = worker.start(_parallel_reader.bind(journal_path, expected.hash, root_row.hash, records, gate))
		_check(error == OK, "bounded cache reader %d starts without a second session writer" % worker_index)
		if error == OK:
			workers.append(worker)
	for worker: Thread in workers:
		gate.post()
	while true:
		var running: bool = false
		for worker: Thread in workers:
			running = running or worker.is_alive()
		if not running:
			break
		if witnesses.size() < PARALLEL_SNAPSHOTS:
			witnesses.append(_snapshot_witness())
		await process_frame
	var results: Array[Dictionary] = []
	for worker: Thread in workers:
		var result: Variant = worker.wait_to_finish()
		_check(result is Dictionary and result.get("error", ERR_SCRIPT_FAILED) == OK
			and int(result.get("iterations", 0)) == PARALLEL_ITERATIONS
			and int(result.get("thread_id", 0)) != OS.get_main_thread_id(),
			"each joined reader preserves all original heads and complete source checks")
		if result is Dictionary:
			results.append(result)
	var immutable: bool = true
	for snapshot: Dictionary in witnesses:
		for record: Dictionary in snapshot.records:
			if _entry_witness(record.entry) != record.values:
				immutable = false
	_check(immutable, "published record entries remain immutable after lock-free shallow snapshots")
	_check(_accounting(), "parallel publication and LRU touches preserve exact byte charges and live raw aliases")
	for path: String in directories:
		_check(_manifest(path) == manifest, "parallel readers preserve every copied journal source byte")
	parallel_evidence = {"workers":results, "snapshot_count":witnesses.size(), "immutable_snapshots":immutable,
		"record_charged_bytes":ReceiptJournal._cached_bytes, "prefix_charged_bytes":ReceiptJournal._prefix_bytes,
		"scope":"THREE_READ_ONLY_JOURNALS_32_ITERATIONS_EACH; NO_GAMEPLAY_OR_SECOND_WRITER"}


static func _parallel_reader(path: String, expected_head: String, expected_root: String, records: Array[String], gate: Semaphore) -> Dictionary:
	gate.wait()
	var reader: ReceiptJournal = ReceiptJournal.new(path)
	for index: int in range(PARALLEL_ITERATIONS):
		var history: Dictionary = reader.read_all()
		if history.error != OK or history.get("hash", "") != expected_head:
			return {"error":ERR_INVALID_DATA, "iterations":index, "reason":"PARALLEL_HISTORY", "result":history}
		var row: Dictionary = reader._read_record(records[index])
		if row.error != OK or row.get("hash", "") != expected_root:
			return {"error":ERR_INVALID_DATA, "iterations":index, "reason":"PARALLEL_RECORD", "result":row}
	return {"error":OK, "iterations":PARALLEL_ITERATIONS, "thread_id":OS.get_thread_caller_id(), "directory":path}


func _snapshot_witness() -> Dictionary:
	var state: Dictionary = ReceiptJournal.new(output)._prefix_state()
	var records: Array[Dictionary] = []
	for entry: Dictionary in state.records.values():
		records.append({"entry":entry, "values":_entry_witness(entry)})
	return {"records":records, "generation":state.generation}


func _entry_witness(entry: Dictionary) -> Array:
	return [entry.serial, entry.raw_shared, entry.shared_generation, entry.cache_bytes, entry.raw_identity]


func _measure(reader: ReceiptJournal, label: String) -> Dictionary:
	FreezeProfile.enabled = true
	FreezeProfile.start({"fixture":label})
	var result: Dictionary = reader.read_all()
	FreezeProfile.finish()
	profiles.append(FreezeProfile.latest.duplicate(true))
	return result


func _manifest(folder: String) -> Dictionary:
	var result: Dictionary = {}
	for generation: String in DirAccess.get_directories_at(folder):
		var name: String = generation.path_join("record.json")
		result[name] = FileAccess.get_sha256(folder.path_join(name))
	return result


func _copy(source: String, target: String, manifest: Dictionary) -> void:
	for name: String in manifest:
		_write(target.path_join(name), FileAccess.get_file_as_bytes(source.path_join(name)))


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()
