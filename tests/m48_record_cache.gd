extends SceneTree
## Real registration + 34 normal rename edits form 69 legal M48 records.
## LRU/budget cases vary only permitted outer JSON whitespace of one authentic record.
## No native DTO is accepted from disk; no rewards, source facts or world state are forged.

const EDITS: int = 34
const BUDGET_RAW_BYTES: int = 1_048_576
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var output: String


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	rows.append({"pass":ok, "label":label})
	if not ok:
		failures.append(label)
		printerr("M48_RECORD_CACHE_FAIL ", label)


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	output = OS.get_user_data_dir().path_join("m48-record-cache-evidence")
	if DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._new_game("scavenge", {"version":CatalogProgress.VERSION, "unlock":""},
		{"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	var transaction: RunTransaction = app.progress_session._transaction
	_check(transaction != null and not app._progress_blocked, "ordinary isolated M48 registration succeeds")
	if transaction != null:
		var journal: ReceiptJournal = transaction._journal
		for index: int in range(EDITS):
			var head: Dictionary = journal.read_all()
			if head.error != OK:
				_check(false, "normal history authenticates before rename")
				break
			var before: Dictionary = TransactionReceipt.camp(head.receipt)
			var identity: String = before.profile_id + ":edit:" + RunSave.new_profile_id()
			var prepared: Dictionary = transaction.prepare_edit(head.hash, identity,
				{"kind":"rename", "member_id":1, "value":"缓存验收%d" % index})
			var committed: Dictionary = transaction.commit_edit(identity) if prepared.error == OK else prepared
			_check(committed.error == OK, "normal rename/commit creates legal receipt pair %d" % index)
			if committed.error != OK: break
		var authenticated: Dictionary = journal.read_all()
		_check(authenticated.error == OK and authenticated.receipt.revision == EDITS * 2 + 1,
			"complete original source and transitions authenticate more than 64 legal new records")
		if authenticated.error == OK:
			var count: int = int(authenticated.receipt.revision)
			_working_set(journal, count)
			_shared_prefix_case(journal, count)
			var first: String = journal.directory.path_join("00000001/record.json")
			var original: String = FileAccess.get_file_as_string(first)
			_reread_cases(journal, first, original)
			_lru_case(journal, original)
			_budget_case(journal, original)
			_legacy_case(journal, original)
			_check(journal.read_all().error == OK and FileAccess.get_file_as_string(first) == original,
				"all source negatives restore the exact complete legal journal")
		_limits_case(journal)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--cache-real-journal="):
			_real_history(argument.trim_prefix("--cache-real-journal="))
	app.audio.shutdown()
	app.queue_free()
	await process_frame
	var report: Dictionary = {"scope":"real-normal-69-record-history; legal-transport-padding-capacity-fixtures",
		"checks":rows.size(), "failures":failures, "rows":rows, "profiles":profiles,
		"cache_budget_bytes":ReceiptJournal.MAX_CACHED_BYTES, "cache_entry_limit":ReceiptJournal.MAX_CACHED_RECORDS,
		"per_entry_metadata_reservation":ReceiptJournal.CACHE_METADATA_BYTES,
		"note":"cache-owned buffers/metadata; 64MiB prefix raw shared by alias; snapshots/transient buffers and process RSS are separate; native DTO never persisted"}
	_write(output.path_join("report.json"), JSON.stringify(report, "\t", true, true))
	print("M48_RECORD_CACHE ", JSON.stringify(report, "", true, true))
	quit(0 if failures.is_empty() else 1)


func _working_set(journal: ReceiptJournal, count: int) -> void:
	_reset_cache()
	_start("69-record-first-scan")
	var hashes: Array[String] = []
	for revision: int in range(1, count + 1):
		var result: Dictionary = journal._read_record(journal.directory.path_join("%08d/record.json" % revision))
		_check(result.error == OK, "fresh real source reads legal revision %d" % revision)
		hashes.append(result.get("hash", ""))
	_finish()
	_check(ReceiptJournal._record_cache.size() == count and count > 64, "native DTO cache retains the complete legal working set beyond 64 records")
	_start("69-record-warm-scan")
	for revision: int in range(1, count + 1):
		var result: Dictionary = journal._read_record(journal.directory.path_join("%08d/record.json" % revision))
		_check(result.error == OK and result.hash == hashes[revision - 1], "warm freshly read bytes restore exact revision %d" % revision)
	_finish()
	var profile: Dictionary = profiles.back().profile
	_check(int(profile.metadata.get("journal_record_bytes_reads", 0)) == count
		and int(profile.metadata.get("record_dto_cache_hits", 0)) == count,
		"every warm hit still rereads the complete physical source bytes")
	_check(int(profile.stages.get("exact.unpack", {}).get("calls", 0)) == 0
		and int(profile.stages.get("receipt.problem", {}).get("calls", 0)) == 0,
		"identical fully authenticated bytes reuse their exact decode and pure shape proof")
	_check(_accounting(), "real working set charges all retained raw/DTO buffers and explicit metadata")


func _shared_prefix_case(journal: ReceiptJournal, count: int) -> void:
	var originals: Dictionary = {}
	var padded_bytes: int = 0
	for revision: int in range(1, count + 1):
		var path: String = journal.directory.path_join("%08d/record.json" % revision)
		var text: String = FileAccess.get_file_as_string(path)
		originals[path] = text
		var padding: int = maxi(0, 520_000 - text.to_utf8_buffer().size())
		_write(path, text + " ".repeat(padding))
		padded_bytes += text.to_utf8_buffer().size() + padding
	_check(padded_bytes > ReceiptJournal.MAX_CACHED_BYTES and padded_bytes < ReceiptJournal.MAX_PREFIX_BYTES,
		"legal 69-record transport fixtures exceed 32MiB raw within the unchanged 64MiB journal limit")
	_check(journal.read_all().error == OK, "complete larger raw source chain authenticates before sharing")
	_reset_cache()
	for revision: int in range(1, count + 1):
		_check(journal._read_record(journal.directory.path_join("%08d/record.json" % revision)).error == OK,
			"larger complete source populates a witnessed native DTO %d" % revision)
	_check(ReceiptJournal._record_cache.size() == count and _accounting(),
		"all greater-than-32MiB raw witnesses coexist without duplicate raw buffers in the 32MiB DTO budget")
	var old_prefix: Dictionary = journal._prefix_snapshot()
	_start("fresh-prefix-alias-rebind")
	var fresh: Dictionary = journal.read_all()
	_finish()
	var new_prefix: Dictionary = journal._prefix_snapshot()
	_check(fresh.error == OK and not is_same(old_prefix.raw_records[0], new_prefix.raw_records[0]) and _accounting(),
		"same-content fresh file reads publish new raw objects and every cache alias rebinds to them")
	_check(int(profiles.back().profile.metadata.get("journal_record_bytes_reads", 0)) == count,
		"raw sharing retains all complete real file reads")
	var root_path: String = journal.directory.path_join("00000001/record.json")
	var shorter: String = output.path_join("authenticated-short-prefix")
	DirAccess.make_dir_recursive_absolute(shorter.path_join("00000001"))
	_write(shorter.path_join("00000001/record.json"), FileAccess.get_file_as_string(root_path))
	var short_reader: ReceiptJournal = ReceiptJournal.new(shorter)
	_check(short_reader.read_all().error == OK, "a separate legitimate registration-only prefix authenticates completely")
	var unshared: int = 0
	for entry: Dictionary in ReceiptJournal._record_cache.values():
		if not entry.raw_shared: unshared += 1
	_check(unshared > 0 and ReceiptJournal._record_cache.size() < count and _accounting(),
		"legal prefix shortening reprices every orphan raw and incrementally evicts to the old byte budget")
	var receipt: Dictionary = RecordEncoding.unpack(JSON.parse_string(String(originals[root_path]))).payload
	var wrong_binding: RunTransaction = RunTransaction.new(shorter, journal.directory.trim_suffix(".txn/journal"),
		receipt.base.profile_id, receipt.base.journey.root_id)
	_check(wrong_binding.recover().error != OK, "cross-directory pure byte reuse cannot replace canonical run binding")
	var order_before: Array = ReceiptJournal._record_cache.keys()
	short_reader._replace_prefix({})
	var order_after: Array = ReceiptJournal._record_cache.keys()
	_check(_accounting() and order_before.slice(order_before.size() - order_after.size()) == order_after,
		"clearing a prefix restores raw charges and preserves surviving LRU order")
	for entry: Dictionary in ReceiptJournal._record_cache.values():
		_check(not entry.raw_shared, "a cleared prefix leaves no zero-charged orphan raw")
	journal._replace_prefix(new_prefix)
	_check(_accounting(), "restoring a trusted complete prefix atomically rebinds only exact matching buffers")
	for path: String in originals: _write(path, originals[path])
	_check(journal.read_all().error == OK, "the original unpadded legal source bytes are restored exactly")
	for path: String in originals:
		_check(FileAccess.get_file_as_string(path) == originals[path], "source restoration retains original real bytes")
	DirAccess.remove_absolute(shorter.path_join("00000001/record.json"))
	DirAccess.remove_absolute(shorter.path_join("00000001"))
	DirAccess.remove_absolute(shorter)
	_reset_cache()


func _reread_cases(journal: ReceiptJournal, path: String, original: String) -> void:
	var first: Dictionary = journal._read_record(path)
	var hash: String = first.hash
	first.receipt.base.cash = -99
	first.hash = "caller-poison"
	var again: Dictionary = journal._read_record(path)
	_check(again.error == OK and again.hash == hash and RecordEncoding.fingerprint(again.receipt) == hash,
		"caller mutations cannot poison a fresh native DTO restoration")
	var raw_caller: Dictionary = journal._read_record(path, false)
	raw_caller.receipt.base.cash = -88
	_check(RecordEncoding.fingerprint(journal._read_record(path, false).receipt) == hash,
		"even the internal non-isolated DTO path never publishes its stored mutable receipt")
	var entry: Dictionary = ReceiptJournal._record_cache[again.raw_identity]
	var damaged_dto: PackedByteArray = entry.dto.duplicate()
	damaged_dto[0] ^= 1
	entry.dto = damaged_dto
	_start("damaged-native-dto-fallback")
	var fallback: Dictionary = journal._read_record(path)
	_finish()
	_check(fallback.error == OK and fallback.hash == hash
		and int(profiles.back().profile.metadata.get("record_dto_cache_fallbacks", 0)) == 1
		and int(profiles.back().profile.stages.get("exact.unpack", {}).get("calls", 0)) == 1,
		"damaged private DTO is discarded before native inflate and the real source codec is reapplied")
	_write(path, original + " ")
	_start("new-valid-raw-bytes")
	var changed: Dictionary = journal._read_record(path)
	_finish()
	var profile: Dictionary = profiles.back().profile
	_check(changed.error == OK and changed.hash == hash and int(profile.metadata.get("record_cache_misses", 0)) == 1
		and int(profile.stages.get("exact.unpack", {}).get("calls", 0)) == 1
		and int(profile.stages.get("receipt.problem", {}).get("calls", 0)) == 1,
		"new raw bytes with the same semantic hash still receive original codec and receipt validation")
	_write(path, original)
	var cross: String = output.path_join("other-directory-record.json")
	_write(cross, original)
	_start("cross-directory-exact-witness")
	var copied: Dictionary = ReceiptJournal.new(output)._read_record(cross)
	_finish()
	_check(copied.error == OK and copied.hash == hash and int(profiles.back().profile.metadata.get("record_dto_cache_hits", 0)) == 1
		and int(profiles.back().profile.metadata.get("journal_record_bytes_reads", 0)) == 1,
		"a different directory can reuse a pure proof only after its own identical complete bytes are read")
	var outer: Dictionary = JSON.parse_string(original)
	outer.sha256 = "0".repeat(64)
	_write(cross, JSON.stringify(outer, "", true, true))
	_check(journal._read_record(cross).error != OK, "a changed source hash cannot hit the DTO cache")
	var invalid: Dictionary = RecordEncoding.unpack(JSON.parse_string(original)).payload
	invalid.base.cash = -1
	_write(cross, RecordEncoding.stringify(invalid))
	_start("rehashed-invalid-business")
	var rejected: Dictionary = journal._read_record(cross)
	_finish()
	_check(rejected.error != OK and int(profiles.back().profile.stages.get("receipt.problem", {}).get("calls", 0)) == 1,
		"new correctly recompressed and rehashed invalid business data runs and fails the original validator")
	DirAccess.remove_absolute(cross)


func _lru_case(journal: ReceiptJournal, original: String) -> void:
	_reset_cache()
	var path: String = output.path_join("lru-transport-fixture.json")
	var identities: Array[String] = []
	_start("256-entry-lru")
	for index: int in range(ReceiptJournal.MAX_CACHED_RECORDS):
		var text: String = original + " ".repeat(index + 1)
		_write(path, text)
		var result: Dictionary = journal._read_record(path)
		_check(result.error == OK, "legal outer whitespace representation authenticates for LRU %d" % index)
		identities.append(result.get("raw_identity", ""))
	_write(path, original + " ")
	_check(journal._read_record(path).error == OK, "touching the oldest complete byte witness moves it to MRU")
	_write(path, original + " ".repeat(ReceiptJournal.MAX_CACHED_RECORDS + 1))
	var newest: Dictionary = journal._read_record(path)
	_finish()
	_check(newest.error == OK and ReceiptJournal._record_cache.size() == ReceiptJournal.MAX_CACHED_RECORDS
		and ReceiptJournal._record_cache.has(identities[0]) and not ReceiptJournal._record_cache.has(identities[1])
		and ReceiptJournal._record_cache.has(newest.raw_identity),
		"the 257th valid raw record evicts the least recently used entry without clearing other proofs")
	_check(_accounting() and int(profiles.back().profile.metadata.get("record_cache_evictions", 0)) == 1,
		"LRU entry bound and shared byte accounting remain explicit")
	DirAccess.remove_absolute(path)


func _budget_case(journal: ReceiptJournal, original: String) -> void:
	_reset_cache()
	var path: String = output.path_join("budget-transport-fixture.json")
	var padding: int = BUDGET_RAW_BYTES - original.to_utf8_buffer().size()
	_check(padding > 0, "bounded transport fixture fits the original single-record size")
	if padding <= 0: return
	_start("shared-32MiB-byte-budget")
	for index: int in range(35):
		_write(path, original + " ".repeat(padding + index))
		_check(journal._read_record(path).error == OK and _accounting(), "byte-budget sample %d remains valid and bounded" % index)
	_finish()
	_check(ReceiptJournal._record_cache.size() > 1 and ReceiptJournal._record_cache.size() < 35
		and int(profiles.back().profile.metadata.get("record_cache_evictions", 0)) > 0,
		"the original shared 32 MiB budget evicts incrementally before the entry cap")
	DirAccess.remove_absolute(path)


func _legacy_case(journal: ReceiptJournal, original: String) -> void:
	var receipt: Dictionary = RecordEncoding.unpack(JSON.parse_string(original)).payload
	var path: String = output.path_join("legacy-v1-transport.json")
	_write(path, RecordEncoding.pack_v1(receipt).text)
	var legacy: Dictionary = journal._read_record(path)
	_check(legacy.error == OK and ReceiptJournal._record_cache[legacy.raw_identity].has("dto") and _accounting(),
		"fully authenticated M48 policy also uses native DTO for its original unchanged V1 disk transport")
	_write(path, "x" + FileAccess.get_file_as_string(path).substr(1))
	_check(journal._read_record(path).error != OK, "old-codec cache also requires the complete freshly read bytes")
	var camp: Dictionary = receipt.base.duplicate(true)
	camp.journey.campaign.erase("economy")
	camp.journey.build.erase("progression")
	camp.journey.build.powers = PowerState.initial_progression(SpecialPowers.M47_VERSION)
	var m47: Dictionary = TransactionReceipt.registration(camp, camp.journey.root_id)
	_check(TransactionReceipt.problem(m47).is_empty(), "genuine historical M47 registration fixture authenticates under its original rules")
	_write(path, RecordEncoding.pack_v1(m47).text)
	var historical: Dictionary = journal._read_record(path)
	_check(historical.error == OK and ReceiptJournal._record_cache[historical.raw_identity].has("result")
		and not ReceiptJournal._record_cache[historical.raw_identity].has("dto") and _accounting(),
		"true pre-M48 V1 retains its complete decoded-result cache and original interpretation")
	DirAccess.remove_absolute(path)


func _limits_case(journal: ReceiptJournal) -> void:
	_check(ReceiptJournal.MAX_CACHED_BYTES == 33_554_432 and ReceiptJournal.MAX_CACHED_RECORDS == 256
		and ReceiptJournal.MAX_BYTES == 4_194_304 and ReceiptJournal.MAX_TOTAL_BYTES == 67_108_864
		and RunSave.MAX_BYTES == 1_048_576 and ReceiptJournal.MAX_NATIVE_DTO_BYTES == ReceiptJournal.MAX_BYTES,
		"only the explicit runtime entry cap changes; all persistent and cache byte limits remain unchanged")
	_check(ReceiptJournal.capacity_problem(1, "STARTED", ReceiptJournal.MAX_BYTES + 1, 0, 0) == "JOURNAL_COMPLETION_BYTE_RESERVE"
		and ReceiptJournal.capacity_problem(1, "SUSPEND_READY", 1, ReceiptJournal.MAX_TOTAL_BYTES, 0) == "JOURNAL_COMPLETION_BYTE_RESERVE",
		"native DTO caching does not relax original record or completion reserves")
	var path: String = output.path_join("oversized-record.json")
	_write(path, " ".repeat(ReceiptJournal.MAX_BYTES + 1))
	_check(journal._read_record(path).error != OK, "actual oversized physical records are rejected before a cache lookup")
	DirAccess.remove_absolute(path)


func _accounting() -> bool:
	var total: int = 0
	var valid: bool = true
	ReceiptJournal._prefix_mutex.lock()
	var prefix: Dictionary = ReceiptJournal._verified_prefix
	for entry: Dictionary in ReceiptJournal._record_cache.values():
		var payload_bytes: int = entry.dto.size() if entry.has("dto") else int(entry.decoded_bytes)
		var charge: int = (0 if entry.raw_shared else entry.raw.size()) + payload_bytes + ReceiptJournal.CACHE_METADATA_BYTES
		if charge != int(entry.cache_bytes): valid = false
		if entry.raw_shared:
			var aliases: bool = false
			if not prefix.is_empty():
				for original: PackedByteArray in prefix.raw_records:
					if is_same(entry.raw, original) and entry.raw == original: aliases = true
			if not aliases or entry.shared_generation != ReceiptJournal._prefix_generation: valid = false
		if entry.has("dto") and (entry.has("result") or not SurvivalContracts.integer(entry.dto_unpacked_bytes, 1, ReceiptJournal.MAX_NATIVE_DTO_BYTES)):
			valid = false
		total += charge
	valid = valid and total == ReceiptJournal._cached_bytes and total <= ReceiptJournal.MAX_CACHED_BYTES \
		and ReceiptJournal._record_cache.size() <= ReceiptJournal.MAX_CACHED_RECORDS
	ReceiptJournal._prefix_mutex.unlock()
	return valid


func _reset_cache() -> void:
	ReceiptJournal._prefix_mutex.lock()
	ReceiptJournal._record_cache.clear()
	ReceiptJournal._cached_bytes = 0
	ReceiptJournal._prefix_mutex.unlock()


func _real_history(path: String) -> void:
	_check(path.is_absolute_path() and "/.local/" in path and DirAccess.dir_exists_absolute(path), "real cache comparison uses an existing isolated source history")
	if not path.is_absolute_path() or "/.local/" not in path or not DirAccess.dir_exists_absolute(path): return
	var reader: ReceiptJournal = ReceiptJournal.new(path)
	var manifest: Dictionary = {}
	for folder: String in DirAccess.get_directories_at(path):
		var file: String = path.path_join(folder).path_join("record.json")
		if FileAccess.file_exists(file): manifest[file] = FileAccess.get_sha256(file)
	_start("real-history-complete-authentication")
	var full: Dictionary = reader.read_all()
	_finish()
	_check(full.error == OK, "real complete source history authenticates before memo comparison")
	if full.error != OK: return
	_reset_cache()
	for pass_index: int in range(2):
		_start("real-history-first-scan" if pass_index == 0 else "real-history-warm-scan")
		for revision: int in range(1, int(full.receipt.revision) + 1):
			_check(reader._read_record(path.path_join("%08d/record.json" % revision)).error == OK,
				"real immutable source exact-decodes or restores under the same byte witness")
		_finish()
	var metadata: Dictionary = profiles.back().profile.metadata
	_check(int(metadata.get("journal_record_bytes_reads", 0)) == int(full.receipt.revision)
		and int(metadata.get("record_dto_cache_hits", 0)) == int(full.receipt.revision)
		and int(profiles.back().profile.stages.get("exact.unpack", {}).get("calls", 0)) == 0 and _accounting(),
		"real warm scan reads every full source while all M48 DTOs fit original budgets without ExactJSON repetition")
	for file: String in manifest:
		_check(FileAccess.get_sha256(file) == manifest[file], "real source files remain byte-identical during cache measurement")


func _start(label: String) -> void:
	print("M48_RECORD_CACHE_STAGE ", label)
	FreezeProfile.enabled = true
	FreezeProfile.start({"fixture":label})


func _finish() -> void:
	FreezeProfile.finish()
	profiles.append({"profile":FreezeProfile.latest.duplicate(true), "charged_bytes":ReceiptJournal._cached_bytes,
		"entries":ReceiptJournal._record_cache.size()})


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
