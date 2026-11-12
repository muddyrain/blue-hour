class_name ReceiptJournal
extends RefCounted
## Immutable generations avoid replacing the only acknowledged death/result record.

const MAX_BYTES: int = 4_194_304
const MAX_TOTAL_BYTES: int = 67_108_864
const MAX_STAGES: int = 32
const MAX_CACHED_RECORDS: int = 256
# The ordinary M38 route exceeds 8 MiB before its first two-build sortie.
const MAX_CACHED_BYTES: int = 33_554_432
# Explicit per-entry reservation for dictionary slots, two hashes and LRU metadata.
# Buffer charges below are actual byte lengths; this is not a process RSS bound.
const CACHE_METADATA_BYTES: int = 2048
const MAX_NATIVE_DTO_BYTES: int = MAX_BYTES
const MAX_CACHED_TRANSITIONS: int = 128
# All directory proofs share one original-journal-sized budget, including their
# boundary and projection metadata. Only actual active-prefix buffer aliases avoid
# a second raw charge in the record cache; transient snapshots are not an RSS bound.
const MAX_PREFIX_BYTES: int = MAX_TOTAL_BYTES
const MAX_CACHED_PREFIXES: int = 128
const PREFIX_RECORD_METADATA_BYTES: int = 512

## Pure proofs are shared across coordinator recreation; every caller still rereads its own files.
static var _record_cache: Dictionary = {}
static var _transition_cache: Dictionary = {}
static var _cached_bytes: int = 0
static var _verified_prefix: Dictionary = {}
static var _verified_prefixes: Dictionary = {}
static var _prefix_bytes: int = 0
static var _prefix_serial: int = 0
static var _prefix_mutex: Mutex = Mutex.new() # One short critical section owns prefix, cache and byte accounting.
static var _prefix_generation: int = 0
static var _cache_serial: int = 0

var directory: String
var fault: Callable


func _init(explicit_directory: String, fault_hook: Callable = Callable()) -> void:
	directory = explicit_directory.replace("\\", "/").simplify_path().trim_suffix("/")
	fault = fault_hook


func read_all() -> Dictionary:
	var stamp: int = FreezeProfile.enter("journal.read_all")
	var result: Dictionary = _profiled_read_all()
	FreezeProfile.leave("journal.read_all", stamp)
	return result


func _profiled_read_all() -> Dictionary:
	if not directory.is_absolute_path() or directory.begins_with("user://") or directory.begins_with("res://"):
		return _error(ERR_INVALID_PARAMETER, "EXPLICIT_ABSOLUTE_PATH_REQUIRED")
	if FileAccess.file_exists(directory):
		return _error(ERR_FILE_CANT_OPEN, "JOURNAL_IS_FILE")
	if not DirAccess.dir_exists_absolute(directory):
		var missing: String = directory
		var ancestor: String = missing.get_base_dir()
		while not DirAccess.dir_exists_absolute(ancestor):
			if FileAccess.file_exists(ancestor):
				return _error(ERR_CANT_OPEN, "JOURNAL_PARENT_IS_FILE")
			var parent_path: String = ancestor.get_base_dir()
			if parent_path == ancestor:
				return _error(ERR_CANT_OPEN, "JOURNAL_ANCESTOR_UNREADABLE")
			missing = ancestor
			ancestor = parent_path
		var parent: Dictionary = _listing(ancestor)
		if parent.error != OK:
			return parent
		for name: String in parent.directories + parent.files:
			if name == missing.get_file() or (OS.has_feature("windows") and name.to_lower() == missing.get_file().to_lower()):
				return _error(ERR_CANT_OPEN, "JOURNAL_EXISTS_BUT_UNREADABLE")
		return {"error":OK, "receipt":{}, "hash":"", "unpublished":[], "bytes":0}
	var listing: Dictionary = _listing(directory)
	if listing.error != OK:
		return listing
	var names: Array = listing.directories
	var stages: Array[String] = []
	var generations: Array[String] = []
	if not listing.files.is_empty() or not listing.links.is_empty():
		return _error(ERR_FILE_CORRUPT, "UNEXPECTED_JOURNAL_FILE")
	for name: String in names:
		if name.begins_with(".stage-") and name.trim_prefix(".stage-").length() == 32 and name.trim_prefix(".stage-").is_valid_hex_number(false):
			stages.append(name)
		elif name.length() == 8 and name.is_valid_int() and name == "%08d" % int(name) and int(name) > 0:
			generations.append(name)
		else:
			return _error(ERR_FILE_CORRUPT, "UNEXPECTED_JOURNAL_DIRECTORY")
	if generations.size() > 4096:
		return _error(ERR_FILE_CORRUPT, "JOURNAL_LIMIT")
	if stages.size() > MAX_STAGES:
		return _error(ERR_OUT_OF_MEMORY, "UNPUBLISHED_STAGE_LIMIT")
	FreezeProfile.scale("journal_generations",generations.size())
	generations.sort()
	var previous: Dictionary = {}
	var previous_identity: String = ""
	var claimed_event: Dictionary = {}
	var claimed_recon: Dictionary = {}
	var claimed_billboard: Dictionary = {}
	var digest: String = ""
	var hashes: Dictionary = {}
	var identities: Array[String] = []
	var total: int = 0
	for stage: String in stages:
		var contents: Dictionary = _listing(directory.path_join(stage))
		if contents.error != OK:
			return contents
		if not contents.directories.is_empty() or not contents.links.is_empty() or (not contents.files.is_empty() and contents.files != ["record.json"]):
			return _error(ERR_FILE_CORRUPT, "UNPUBLISHED_STAGE_FILES")
		if not contents.files.is_empty():
			var partial: FileAccess = FileAccess.open(directory.path_join(stage).path_join("record.json"), FileAccess.READ)
			if partial == null:
				return _error(ERR_CANT_OPEN, "UNPUBLISHED_STAGE_UNREADABLE")
			var length: int = partial.get_length()
			partial.close()
			if length > MAX_BYTES:
				return _error(ERR_OUT_OF_MEMORY, "UNPUBLISHED_STAGE_SIZE")
			total += length
	if total > MAX_TOTAL_BYTES:
		return _error(ERR_OUT_OF_MEMORY, "UNPUBLISHED_STAGE_TOTAL")
	# Enumerate and reread every real file before reusing any pure prefix proof.
	var observed_raw: Array[PackedByteArray] = []
	var raw_total: int = 0
	for index: int in range(generations.size()):
		if generations[index] != "%08d" % (index + 1):
			return _error(ERR_FILE_CORRUPT, "GENERATION_GAP")
		var folder: String = directory.path_join(generations[index])
		var entries: Dictionary = _listing(folder)
		if entries.error != OK:
			return entries
		if not entries.directories.is_empty() or not entries.links.is_empty() or entries.files != ["record.json"]:
			return _error(ERR_FILE_CORRUPT, "GENERATION_FILES")
		var read: Dictionary = _read_record_bytes(folder.path_join("record.json"))
		if read.error != OK:
			return read
		observed_raw.append(read.raw)
		raw_total += read.raw.size()
		total += read.raw.size()
		if total > MAX_TOTAL_BYTES:
			return _error(ERR_FILE_CORRUPT, "JOURNAL_SIZE_LIMIT")
	var prefix: Dictionary = _prefix_snapshot()
	var reused: int = _matching_prefix(prefix, observed_raw)
	if reused > 0:
		FreezeProfile.count("journal_prefix_hits")
		FreezeProfile.scale("journal_prefix_reused_records", reused)
		var boundary: Dictionary = prefix.boundary
		previous = boundary.receipt.duplicate(true)
		previous_identity = boundary.raw_identity
		claimed_event = boundary.claimed_event.duplicate(true)
		claimed_recon = boundary.claimed_recon.duplicate(true)
		claimed_billboard = boundary.claimed_billboard.duplicate(true)
		digest = boundary.hash
		hashes = boundary.hashes.duplicate()
		identities.assign(boundary.identities)
	else:
		FreezeProfile.count("journal_prefix_misses")
		if not prefix.is_empty() and prefix.directory == directory: FreezeProfile.count("journal_prefix_fallbacks")
	for index: int in range(reused, generations.size()):
		var result: Dictionary = _decode_record(observed_raw[index], false)
		if result.error != OK:
			return result
		var receipt: Dictionary = result.receipt
		if receipt.transaction_id != previous.get("transaction_id", ""):
			claimed_event = {}
			claimed_recon = {}
			claimed_billboard = {}
			if not receipt.transaction_id.is_empty():
				if receipt.transaction_id in identities:
					return _error(ERR_FILE_CORRUPT, "TRANSACTION_ID_REUSED")
				identities.append(receipt.transaction_id)
		if receipt.previous_hash != digest:
			return _error(ERR_FILE_CORRUPT, "CHAIN_HASH")
		var issue: String = _transition(previous, receipt, previous_identity, result.raw_identity)
		if not issue.is_empty():
			return _error(ERR_FILE_CORRUPT, issue)
		# A death checkpoint has no world. Compare against the last claim outside
		# the adjacent-record cache, whose key does not include earlier history.
		if (not claimed_event.is_empty() or not claimed_recon.is_empty() or not claimed_billboard.is_empty()) \
				and previous.phase != "RESUME_CLAIMED":
			issue = TaskActions.event_history_problem(claimed_event, receipt)
			if issue.is_empty():
				issue = ReconKnowledge.history_problem(claimed_recon, receipt)
			if issue.is_empty():
				issue = BillboardIntelV1.history_problem(claimed_billboard, receipt)
			if not issue.is_empty():
				return _error(ERR_FILE_CORRUPT, issue)
		if receipt.phase == "RESUME_CLAIMED":
			claimed_event = TaskActions.claimed_event(receipt)
			claimed_recon = ReconKnowledge.claimed(receipt)
			claimed_billboard = BillboardIntelV1.claimed(receipt)
		previous = receipt
		previous_identity = result.raw_identity
		digest = result.hash
		hashes[int(receipt.revision)] = digest
	FreezeProfile.scale("journal_total_bytes",total)
	if not observed_raw.is_empty() and raw_total <= MAX_PREFIX_BYTES:
		_publish_prefix(observed_raw, {"receipt":previous, "raw_identity":previous_identity, "hash":digest,
			"hashes":hashes, "identities":identities, "claimed_event":claimed_event,
			"claimed_recon":claimed_recon, "claimed_billboard":claimed_billboard}, raw_total)
	# Intermediate chain proofs only read the cached values. Isolate the one receipt
	# that actually leaves the journal instead of cloning every historical generation.
	return {"error":OK, "receipt":previous.duplicate(true), "hash":digest, "hashes":hashes, "identities":identities, "unpublished":stages, "bytes":total, "claimed_event":claimed_event.duplicate(true), "claimed_recon":claimed_recon.duplicate(true), "claimed_billboard":claimed_billboard.duplicate(true)}


func append(next: Dictionary, expected_hash: String) -> Dictionary:
	var stamp: int = FreezeProfile.enter("journal.append")
	var result: Dictionary = _profiled_append(next,expected_hash)
	FreezeProfile.leave("journal.append", stamp)
	return result


func _profiled_append(next: Dictionary, expected_hash: String) -> Dictionary:
	var shape_problem: String = TransactionReceipt.problem(next)
	if not shape_problem.is_empty():
		return _error(ERR_INVALID_DATA, shape_problem)
	var prior: Dictionary = read_all()
	if prior.error != OK:
		return prior
	if prior.hash != expected_hash:
		return _error(ERR_BUSY, "JOURNAL_REVISION_CONFLICT")
	if next.transaction_id != prior.receipt.get("transaction_id", "") and next.transaction_id in prior.get("identities", []):
		return _error(ERR_INVALID_DATA, "TRANSACTION_ID_REUSED")
	var receipt: Dictionary = next.duplicate(true)
	receipt.previous_hash = expected_hash
	var issue: String = TransactionReceipt.transition(prior.receipt, receipt,
		prior.get("claimed_event", {}), prior.get("claimed_recon", {}), prior.get("claimed_billboard", {}))
	if not issue.is_empty():
		return _error(ERR_INVALID_DATA, issue)
	var packet: Dictionary = RecordEncoding.pack(receipt)
	if packet.is_empty():
		return _error(ERR_INVALID_DATA, "RECORD_ENCODING_VALUE")
	var digest: String = packet.hash
	var serialized: String = packet.text
	var capacity: String = capacity_problem(int(receipt.revision), receipt.phase, serialized.to_utf8_buffer().size(), int(prior.bytes), prior.unpublished.size())
	if not capacity.is_empty():
		return _error(ERR_OUT_OF_MEMORY, capacity)
	var ancestor: String = directory
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor):
			return _error(ERR_CANT_CREATE, "JOURNAL_PARENT_IS_FILE")
		var parent: String = ancestor.get_base_dir()
		if parent == ancestor:
			break
		ancestor = parent
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return _error(error, "JOURNAL_DIRECTORY_WRITE")
	var stage: String = directory.path_join(".stage-" + RunSave.new_profile_id())
	error = DirAccess.make_dir_absolute(stage)
	if error != OK:
		return _error(error, "STAGE_DIRECTORY_WRITE")
	if _fault("before_record_write") != OK:
		return _error(ERR_CANT_CREATE, "INJECTED_RECORD_WRITE")
	var temporary: String = stage.path_join("record.json")
	var io_stamp: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error(FileAccess.get_open_error(), "RECORD_OPEN")
	file.store_string(serialized)
	file.flush()
	error = file.get_error()
	file.close()
	FreezeProfile.sample("file.write_flush_record",io_stamp)
	var checked: Dictionary = _read_record(temporary)
	if error != OK or checked.error != OK or checked.get("hash") != digest or FileAccess.get_file_as_string(temporary) != serialized:
		return _error(ERR_FILE_CORRUPT, "RECORD_READBACK:" + String(checked.get("reason","BYTE_OR_HASH_MISMATCH")))
	if _fault("after_record_flush") != OK:
		return _error(ERR_CANT_CREATE, "INJECTED_BEFORE_PUBLICATION")
	# Destination is a nonempty immutable directory, never an overwritable pointer file.
	var destination: String = directory.path_join("%08d" % int(receipt.revision))
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		return _error(ERR_BUSY, "GENERATION_ALREADY_EXISTS")
	error = DirAccess.rename_absolute(stage, destination)
	if error != OK:
		return _error(error, "GENERATION_PUBLICATION")
	if _fault("after_record_publish") != OK:
		return _error(ERR_CANT_CREATE, "PUBLICATION_ACK_UNKNOWN_RELOAD_REQUIRED")
	var final: Dictionary = read_all()
	if final.error != OK or final.hash != digest:
		return _error(ERR_FILE_CORRUPT, "PUBLICATION_READBACK")
	return final


func registration_problem(base: Dictionary, root_id: String) -> String:
	var current: Dictionary = read_all()
	if current.error != OK:
		return current.reason
	var expected: Dictionary = TransactionReceipt.registration(base, root_id)
	if not current.receipt.is_empty() and not TransactionReceipt.same(current.receipt, expected):
		return "FOREIGN_OR_ADVANCED_REGISTRATION"
	for stage: String in current.unpublished:
		var path: String = directory.path_join(stage).path_join("record.json")
		if not FileAccess.file_exists(path):
			continue
		var value: Dictionary = _read_record(path)
		if value.error != OK or not TransactionReceipt.same(value.receipt, expected):
			return "FOREIGN_OR_PARTIAL_REGISTRATION_STAGE"
	return ""


func _read_record(source: String, isolate: bool=true) -> Dictionary:
	var stamp: int = FreezeProfile.enter("journal.read_record")
	var result: Dictionary = _profiled_read_record(source,isolate)
	FreezeProfile.leave("journal.read_record", stamp)
	return result


func _profiled_read_record(source: String, isolate: bool=true) -> Dictionary:
	var read: Dictionary = _read_record_bytes(source)
	return read if read.error != OK else _decode_record(read.raw, isolate)


func _read_record_bytes(source: String) -> Dictionary:
	var io_stamp: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _error(FileAccess.get_open_error(), "RECORD_READ")
	var length: int = file.get_length()
	if length == 0 or length > MAX_BYTES:
		file.close()
		return _error(ERR_FILE_CORRUPT, "RECORD_SIZE")
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	FreezeProfile.sample("file.read_record_bytes",io_stamp)
	FreezeProfile.count("journal_record_bytes_reads")
	FreezeProfile.scale("largest_record_bytes",length)
	if bytes.size() != length or read_error != OK:
		return _error(ERR_FILE_CORRUPT, "RECORD_INCOMPLETE_READ")
	return {"error":OK, "raw":bytes}


func _decode_record(bytes: PackedByteArray, isolate: bool=true) -> Dictionary:
	var stamp: int = FreezeProfile.enter("journal.decode_record")
	var result: Dictionary = _profiled_decode_record(bytes, isolate)
	FreezeProfile.leave("journal.decode_record", stamp)
	return result


func _profiled_decode_record(bytes: PackedByteArray, isolate: bool=true) -> Dictionary:
	var length: int = bytes.size()
	# Every lookup follows a fresh file read and complete UTF-8 byte identity.
	# Claimed record hashes, paths, timestamps and mutable object references are insufficient.
	var digest_context: HashingContext=HashingContext.new()
	digest_context.start(HashingContext.HASH_SHA256)
	digest_context.update(bytes)
	var identity: String=digest_context.finish().hex_encode()
	var cached: Dictionary = _cache_lookup(identity, bytes)
	if not cached.is_empty():
		var restored: Dictionary = _cached_record_result(cached, isolate)
		if not restored.is_empty():
			FreezeProfile.count("record_cache_hits")
			_cache_profile()
			return restored
		_cache_forget(identity, int(cached.serial))
		FreezeProfile.count("record_dto_cache_fallbacks")
	FreezeProfile.count("record_cache_misses")
	var content: String = bytes.get_string_from_utf8()
	if content.to_utf8_buffer() != bytes:
		return _error(ERR_FILE_CORRUPT, "RECORD_UTF8")
	var parser: JSON = JSON.new()
	if parser.parse(content) != OK or not parser.data is Dictionary:
		return _error(ERR_FILE_CORRUPT, "RECORD_JSON")
	var record: Dictionary = parser.data
	var payload: Dictionary
	var digest: String
	if record.has("record_encoding"):
		var decoded: Dictionary = RecordEncoding.unpack(record)
		if decoded.error != OK:
			return _error(ERR_FILE_CORRUPT, decoded.reason)
		payload = decoded.payload
		digest = decoded.hash
	else:
		if record.size() != 2 or not record.get("payload") is Dictionary or not record.get("sha256") is String:
			return _error(ERR_FILE_CORRUPT, "RECORD_JSON")
		payload = record.payload
		digest = TransactionReceipt.legacy_fingerprint(payload)
		if digest.is_empty() or digest != record.sha256:
			return _error(ERR_FILE_CORRUPT, "RECORD_HASH")
	# The transport codec has just decoded and authenticated the freshly read bytes above.
	# Only a byte-for-byte match to a previously authenticated complete prefix
	# can reuse the pure receipt shape/source proof; new content is fully checked.
	if not _prefix_shape_proven(bytes):
		var issue: String = TransactionReceipt.problem(payload)
		if not issue.is_empty():
			return _error(ERR_FILE_CORRUPT, issue)
	var result: Dictionary = {"error":OK, "receipt":payload, "hash":digest,
		"bytes":length, "raw_identity":identity}
	_cache_record(identity, bytes, result, M48RecordTransport.supported(record.get("record_encoding")) or M48RecordTransport.eligible(payload))
	return result


func _cache_lookup(identity: String, bytes: PackedByteArray) -> Dictionary:
	_prefix_mutex.lock()
	var cached: Dictionary = _record_cache.get(identity, {})
	var snapshot: Dictionary = cached.duplicate(false)
	_prefix_mutex.unlock()
	# Hash is only an index. The whole freshly read byte buffer remains the proof.
	if snapshot.is_empty() or snapshot.raw.size() != bytes.size() or snapshot.raw != bytes:
		return {}
	_prefix_mutex.lock()
	if _record_cache.has(identity) and _record_cache[identity].serial == snapshot.serial:
		# Prefix publication may have rebound this same serial while bytes were
		# compared. Touch its current accounting/alias instead of restoring the old one.
		var current: Dictionary = _record_cache[identity]
		_record_cache.erase(identity)
		_record_cache[identity] = current
	_prefix_mutex.unlock()
	return snapshot


func _cached_record_result(cached: Dictionary, isolate: bool) -> Dictionary:
	if not cached.has("dto"):
		return cached.result.duplicate(true) if isolate else cached.result
	var stamp: int = FreezeProfile.enter("journal.native_dto_restore")
	# Only private, previously authenticated primitive DTOs reach bytes_to_var.
	# Digest/frame checks detect cache damage before the fixed native decompressor.
	var restored: Dictionary = {}
	if cached.get("dto") is PackedByteArray and M48RecordTransport._hash(cached.get("dto_sha256")) \
			and SurvivalContracts.integer(cached.get("dto_unpacked_bytes"), 1, MAX_NATIVE_DTO_BYTES) \
			and M48RecordTransport._bytes_hash(cached.dto) == cached.dto_sha256 \
			and M48RecordTransport.zstd_frame(cached.dto, int(cached.dto_unpacked_bytes)):
		var native: PackedByteArray = cached.dto.decompress(int(cached.dto_unpacked_bytes), FileAccess.COMPRESSION_ZSTD)
		if native.size() == int(cached.dto_unpacked_bytes):
			# No object decoding; never use bytes_to_var_with_objects.
			var payload: Variant = bytes_to_var(native)
			if payload is Dictionary:
				restored = {"error":OK, "receipt":payload, "hash":cached.hash,
					"bytes":cached.raw.size(), "raw_identity":cached.raw_identity}
	FreezeProfile.leave("journal.native_dto_restore", stamp)
	if not restored.is_empty(): FreezeProfile.count("record_dto_cache_hits")
	return restored


func _cache_record(identity: String, bytes: PackedByteArray, result: Dictionary, compact: bool) -> void:
	# Serialization, compression and all business/source proofs stay outside the lock.
	var entry: Dictionary
	if compact:
		var stamp: int = FreezeProfile.enter("journal.native_dto_store")
		var native: PackedByteArray = var_to_bytes(result.receipt)
		if native.is_empty() or native.size() > MAX_NATIVE_DTO_BYTES:
			FreezeProfile.count("record_dto_cache_oversized")
			FreezeProfile.leave("journal.native_dto_store", stamp)
			return
		var dto: PackedByteArray = native.compress(FileAccess.COMPRESSION_ZSTD)
		if not M48RecordTransport.zstd_frame(dto, native.size()):
			FreezeProfile.leave("journal.native_dto_store", stamp)
			return
		entry = {"raw":bytes, "dto":dto, "dto_unpacked_bytes":native.size(),
			"dto_sha256":M48RecordTransport._bytes_hash(dto), "hash":result.hash, "raw_identity":identity}
		FreezeProfile.leave("journal.native_dto_store", stamp)
		FreezeProfile.count("record_dto_cache_stores")
	else:
		# Genuine pre-M48 receipts keep their complete decoded result and byte proof.
		entry = {"raw":bytes, "result":result.duplicate(true), "decoded_bytes":var_to_bytes(result).size(), "raw_identity":identity}
	var prefix_state: Dictionary = _prefix_state()
	_cache_reprice(entry, prefix_state.active)
	_prefix_mutex.lock()
	_cache_remove_locked(identity)
	_cache_serial += 1
	entry.serial = _cache_serial
	if int(prefix_state.generation) != _prefix_generation:
		_cache_unshare(entry)
	entry.shared_generation = _prefix_generation if entry.raw_shared else -1
	var charge: int = int(entry.cache_bytes)
	if charge <= MAX_CACHED_BYTES:
		_cache_trim_locked(charge, 1)
		_record_cache[identity] = entry
		_cached_bytes += charge
	_prefix_mutex.unlock()
	_cache_profile()


func _cache_forget(identity: String, serial: int) -> void:
	_prefix_mutex.lock()
	if _record_cache.has(identity) and _record_cache[identity].serial == serial:
		_cache_remove_locked(identity)
	_prefix_mutex.unlock()


func _cache_remove_locked(identity: String) -> void:
	if not _record_cache.has(identity): return
	_cached_bytes -= int(_record_cache[identity].cache_bytes)
	_record_cache.erase(identity)


func _cache_trim_locked(incoming_bytes: int = 0, incoming_entries: int = 0) -> void:
	while not _record_cache.is_empty() and (_record_cache.size() + incoming_entries > MAX_CACHED_RECORDS or _cached_bytes + incoming_bytes > MAX_CACHED_BYTES):
		_cache_remove_locked(String(_record_cache.keys()[0]))
		FreezeProfile.count("record_cache_evictions")


func _cache_reprice(entry: Dictionary, prefix: Dictionary) -> void:
	_cache_unshare(entry)
	if not prefix.is_empty():
		var original: PackedByteArray = prefix.raw_index.get(entry.raw_identity, PackedByteArray())
		# Hashes narrow the lookup; the complete bytes still prove the alias.
		if not original.is_empty() and original == entry.raw:
			entry.raw = original
			entry.raw_shared = is_same(entry.raw, original)
	var payload_bytes: int = entry.dto.size() if entry.has("dto") else int(entry.decoded_bytes)
	entry.cache_bytes = (0 if entry.raw_shared else entry.raw.size()) + payload_bytes + CACHE_METADATA_BYTES


func _cache_unshare(entry: Dictionary) -> void:
	entry.raw_shared = false
	entry.shared_generation = -1
	var payload_bytes: int = entry.dto.size() if entry.has("dto") else int(entry.decoded_bytes)
	entry.cache_bytes = entry.raw.size() + payload_bytes + CACHE_METADATA_BYTES


func _cache_profile() -> void:
	if not FreezeProfile.active: return
	var raw_bytes: int = 0
	var shared_raw_bytes: int = 0
	var dto_bytes: int = 0
	var legacy_bytes: int = 0
	_prefix_mutex.lock()
	for entry: Dictionary in _record_cache.values():
		if entry.raw_shared: shared_raw_bytes += entry.raw.size()
		else: raw_bytes += entry.raw.size()
		if entry.has("dto"): dto_bytes += entry.dto.size()
		else: legacy_bytes += int(entry.decoded_bytes)
	var count: int = _record_cache.size()
	var charge: int = _cached_bytes
	_prefix_mutex.unlock()
	FreezeProfile.scale("record_cache_entries", count)
	FreezeProfile.scale("record_cache_raw_bytes", raw_bytes)
	FreezeProfile.scale("record_cache_shared_raw_bytes", shared_raw_bytes)
	FreezeProfile.scale("record_cache_dto_bytes", dto_bytes)
	FreezeProfile.scale("record_cache_legacy_native_bytes", legacy_bytes)
	FreezeProfile.scale("record_cache_metadata_bytes", count * CACHE_METADATA_BYTES)
	FreezeProfile.scale("record_cache_charged_bytes", charge)


func _replace_prefix(value: Dictionary) -> void:
	# Only complete authenticated publication or a trusted in-process snapshot may
	# reset this memo control. Normal publication retains other bounded directories.
	_install_prefix(value, true)


func _prefix_state() -> Dictionary:
	_prefix_mutex.lock()
	var value: Dictionary = {"generation":_prefix_generation, "serial":_prefix_serial,
		"prefixes":_verified_prefixes.duplicate(), "active":_verified_prefix,
		"records":_record_cache.duplicate()}
	_prefix_mutex.unlock()
	return value


func _prefix_snapshot() -> Dictionary:
	_prefix_mutex.lock()
	# Published contents are private and immutable; validation happens outside the lock.
	var value: Dictionary = _verified_prefixes.get(directory, {})
	_prefix_mutex.unlock()
	return value


func prefix_memo_token() -> String:
	return String(_prefix_snapshot().get("token", ""))


func prefix_memo_get(key: String, expected_token: String) -> Dictionary:
	var prefix: Dictionary = _prefix_snapshot()
	if expected_token.is_empty() or prefix.get("token") != expected_token:
		return {}
	var candidate: Variant = prefix.get("memo", {}).get(key, {})
	if not candidate is Dictionary:
		FreezeProfile.count("journal_projection_corruptions")
		return {}
	var memo: Dictionary = candidate
	if memo.is_empty():
		return {}
	# A private primitive DTO is checked before decoding; objects are never enabled.
	if not memo.get("raw") is PackedByteArray or not M48RecordTransport._hash(memo.get("sha256")):
		FreezeProfile.count("journal_projection_corruptions")
		return {}
	var raw: PackedByteArray = memo.raw
	if raw.is_empty() or raw.size() > MAX_BYTES or M48RecordTransport._bytes_hash(raw) != memo.sha256:
		FreezeProfile.count("journal_projection_corruptions")
		return {}
	var value: Variant = bytes_to_var(raw)
	if not value is Dictionary:
		return {}
	FreezeProfile.count("journal_projection_hits")
	return {"value":value}


func prefix_memo_put(key: String, value: Dictionary, expected_token: String) -> void:
	if key.is_empty() or key.to_utf8_buffer().size() > 512 or expected_token.is_empty():
		return
	var raw: PackedByteArray = var_to_bytes(value)
	# A single pure projection must not consume more than an ordinary record.
	if raw.is_empty() or raw.size() > MAX_BYTES:
		return
	var memo: Dictionary = {"raw":raw, "sha256":M48RecordTransport._bytes_hash(raw)}
	_install_prefix({}, false, expected_token, key, memo)


func _prefix_charge(value: Dictionary) -> int:
	var total: int = int(value.raw_bytes) + var_to_bytes(value.boundary).size() \
		+ CACHE_METADATA_BYTES + value.raw_records.size() * PREFIX_RECORD_METADATA_BYTES
	for memo: Dictionary in value.memo.values():
		total += memo.raw.size() + CACHE_METADATA_BYTES
	return total


func _install_prefix(value: Dictionary, reset: bool = false, expected_token: String = "", memo_key: String = "", memo: Dictionary = {}) -> void:
	var stamp: int = FreezeProfile.enter("journal.cache_prefix_rebind")
	while true:
		var snapshot: Dictionary = _prefix_state()
		var prefixes: Dictionary = {} if reset else snapshot.prefixes.duplicate()
		var next: Dictionary = value.duplicate()
		var serial: int = int(snapshot.serial)
		if not memo_key.is_empty():
			var current: Dictionary = prefixes.get(directory, {})
			if current.get("token", "") != expected_token:
				break
			next = current.duplicate()
			next.memo = current.memo.duplicate()
			next.memo[memo_key] = memo
		elif not next.is_empty():
			var current: Dictionary = prefixes.get(next.directory, {})
			var identical: bool = not current.is_empty() and current.raw_records.size() == next.raw_records.size() \
				and _matching_prefix(current, next.raw_records) == next.raw_records.size()
			if identical:
				next.token = current.token
				next.memo = current.memo
			elif not next.has("token") or not reset:
				serial += 1
				next.token = str(serial)
				next.memo = {}
		var evictions: int = 0
		if not next.is_empty():
			next.charge = _prefix_charge(next)
			prefixes.erase(next.directory)
			if int(next.charge) <= MAX_PREFIX_BYTES:
				prefixes[next.directory] = next
			else:
				# Oversized memo additions are optional; retain the authenticated source proof.
				if not memo_key.is_empty():
					break
				next = {}
		var bytes: int = 0
		for prefix: Dictionary in prefixes.values():
			bytes += int(prefix.charge)
		while not prefixes.is_empty() and (bytes > MAX_PREFIX_BYTES or prefixes.size() > MAX_CACHED_PREFIXES):
			var oldest: String = String(prefixes.keys()[0])
			bytes -= int(prefixes[oldest].charge)
			prefixes.erase(oldest)
			evictions += 1
		var planned: Dictionary = {}
		for identity: String in snapshot.records:
			var entry: Dictionary = snapshot.records[identity].duplicate()
			_cache_reprice(entry, next)
			planned[identity] = entry
		# Directory/byte comparisons, serialization and copy work all happened outside.
		_prefix_mutex.lock()
		if int(snapshot.generation) != _prefix_generation:
			_prefix_mutex.unlock()
			continue
		_verified_prefixes = prefixes
		_verified_prefix = next
		_prefix_bytes = bytes
		_prefix_serial = serial
		_prefix_generation += 1
		_cached_bytes = 0
		for identity: String in _record_cache:
			var entry: Dictionary = _record_cache[identity]
			if planned.has(identity) and planned[identity].serial == entry.serial:
				entry = planned[identity]
				entry.shared_generation = _prefix_generation if entry.raw_shared else -1
				_record_cache[identity] = entry
			else:
				# Another publisher may already hold this entry in a shallow snapshot.
				# Replace its accounting without mutating that immutable snapshot.
				entry = entry.duplicate(false)
				_cache_unshare(entry)
				_record_cache[identity] = entry
			_cached_bytes += int(entry.cache_bytes)
		_cache_trim_locked()
		_prefix_mutex.unlock()
		for index: int in range(evictions):
			FreezeProfile.count("journal_prefix_evictions")
		FreezeProfile.scale("journal_prefix_entries", prefixes.size())
		FreezeProfile.scale("journal_prefix_charged_bytes", bytes)
		break
	FreezeProfile.leave("journal.cache_prefix_rebind", stamp)
	_cache_profile()


func _prefix_shape_proven(bytes: PackedByteArray) -> bool:
	var stamp: int = FreezeProfile.enter("journal.prefix_shape_witness")
	var prefix: Dictionary = _prefix_snapshot()
	var proven: bool = false
	if not prefix.is_empty():
		for original: PackedByteArray in prefix.raw_records:
			if original.size() == bytes.size() and original == bytes:
				proven = true
				break
	FreezeProfile.leave("journal.prefix_shape_witness", stamp)
	FreezeProfile.count("record_prefix_shape_hits" if proven else "record_prefix_shape_misses")
	return proven


func _matching_prefix(prefix: Dictionary, observed_raw: Array[PackedByteArray]) -> int:
	if prefix.is_empty() or prefix.directory != directory or prefix.raw_records.is_empty() or observed_raw.size() < prefix.raw_records.size(): return 0
	var stamp: int = FreezeProfile.enter("journal.prefix_witness")
	var matched: bool = true
	for index: int in range(prefix.raw_records.size()):
		if prefix.raw_records[index] != observed_raw[index]:
			matched = false
			break
	FreezeProfile.leave("journal.prefix_witness", stamp)
	return prefix.raw_records.size() if matched else 0


func _publish_prefix(raw_records: Array[PackedByteArray], boundary: Dictionary, raw_bytes: int) -> void:
	if raw_bytes > MAX_PREFIX_BYTES: return
	var raw_index: Dictionary = {}
	for raw: PackedByteArray in raw_records:
		raw_index[M48RecordTransport._bytes_hash(raw)] = raw
	var value: Dictionary = {"directory":directory, "raw_records":raw_records.duplicate(),
		"boundary":boundary.duplicate(true), "raw_bytes":raw_bytes, "raw_index":raw_index, "memo":{}}
	_install_prefix(value)
	FreezeProfile.scale("journal_prefix_bytes", raw_bytes)


func _transition(previous: Dictionary, next: Dictionary, previous_identity: String, next_identity: String) -> String:
	# A transition proof is valid only for the full adjacent raw records, not merely a head ID.
	var identity: String = previous_identity + ":" + next_identity
	if _transition_cache.has(identity):
		FreezeProfile.count("transition_cache_hits")
		return ""
	FreezeProfile.count("transition_cache_misses")
	var issue: String = TransactionReceipt.transition(previous, next)
	if issue.is_empty():
		if _transition_cache.size() >= MAX_CACHED_TRANSITIONS:
			_transition_cache.clear()
		_transition_cache[identity] = true
	return issue


static func capacity_problem(revision: int, phase: String, record_bytes: int, used_bytes: int, stages: int) -> String:
	var reserve: int = 0 if phase in ["COMMITTED", "EDIT_COMMITTED", "CAMP_REGISTERED"] else (1 if phase in ["RESULT_READY", "EDIT_READY"] else 2)
	if phase == "SUSPEND_READY":
		reserve = 3 # claim, complete result, commit must all still fit.
	if stages >= MAX_STAGES:
		return "UNPUBLISHED_STAGE_LIMIT"
	if revision + reserve > 4096:
		return "JOURNAL_COMPLETION_REVISION_RESERVE"
	if record_bytes > MAX_BYTES or used_bytes + record_bytes + reserve * MAX_BYTES > MAX_TOTAL_BYTES:
		return "JOURNAL_COMPLETION_BYTE_RESERVE"
	return ""


func _listing(source: String) -> Dictionary:
	if _fault("before_directory_list") != OK:
		return _error(ERR_CANT_OPEN, "DIRECTORY_ENUMERATION_DENIED")
	var access: DirAccess = DirAccess.open(source)
	if access == null:
		return _error(ERR_CANT_OPEN, "DIRECTORY_OPEN")
	access.include_hidden = true
	var error: Error = access.list_dir_begin()
	if error != OK:
		return _error(error, "DIRECTORY_ENUMERATION")
	var directories: Array[String] = []
	var files: Array[String] = []
	var links: Array[String] = []
	var name: String = access.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			if access.is_link(name):
				links.append(name)
			if access.current_is_dir():
				directories.append(name)
			else:
				files.append(name)
		name = access.get_next()
	access.list_dir_end()
	return {"error":OK, "directories":directories, "files":files, "links":links}


func _fault(point: String) -> Error:
	return int(fault.call(point)) as Error if fault.is_valid() else OK


func _error(code: Error, reason: String) -> Dictionary:
	return {"error":code, "reason":reason, "state":"BLOCKED", "acknowledged":false, "receipt":{}}
