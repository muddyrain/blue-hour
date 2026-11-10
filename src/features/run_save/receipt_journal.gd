class_name ReceiptJournal
extends RefCounted
## Immutable generations avoid replacing the only acknowledged death/result record.

const MAX_BYTES: int = 4_194_304
const MAX_TOTAL_BYTES: int = 67_108_864
const MAX_STAGES: int = 32
const MAX_CACHED_RECORDS: int = 64
# The ordinary M38 route exceeds 8 MiB before its first two-build sortie.
const MAX_CACHED_BYTES: int = 33_554_432
const MAX_CACHED_TRANSITIONS: int = 128

## Pure proofs are shared across coordinator recreation; every caller still rereads its own files.
static var _record_cache: Dictionary = {}
static var _transition_cache: Dictionary = {}
static var _cached_bytes: int = 0

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
	for index: int in range(generations.size()):
		if generations[index] != "%08d" % (index + 1):
			return _error(ERR_FILE_CORRUPT, "GENERATION_GAP")
		var folder: String = directory.path_join(generations[index])
		var entries: Dictionary = _listing(folder)
		if entries.error != OK:
			return entries
		if not entries.directories.is_empty() or not entries.links.is_empty() or entries.files != ["record.json"]:
			return _error(ERR_FILE_CORRUPT, "GENERATION_FILES")
		var result: Dictionary = _read_record(folder.path_join("record.json"),false)
		if result.error != OK:
			return result
		total += int(result.bytes)
		if total > MAX_TOTAL_BYTES:
			return _error(ERR_FILE_CORRUPT, "JOURNAL_SIZE_LIMIT")
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
	var io_stamp: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _error(FileAccess.get_open_error(), "RECORD_READ")
	var length: int = file.get_length()
	if length == 0 or length > MAX_BYTES:
		return _error(ERR_FILE_CORRUPT, "RECORD_SIZE")
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	FreezeProfile.sample("file.read_record_bytes",io_stamp)
	FreezeProfile.scale("largest_record_bytes",length)
	if bytes.size() != length or read_error != OK:
		return _error(ERR_FILE_CORRUPT, "RECORD_INCOMPLETE_READ")
	# Every lookup follows a fresh file read and complete UTF-8 byte identity.
	# Claimed record hashes, paths, timestamps and mutable object references are insufficient.
	for cached_identity: String in _record_cache:
		var cached: Dictionary=_record_cache[cached_identity]
		if cached.raw.size()==length and cached.raw==bytes:
			FreezeProfile.count("record_cache_hits")
			return cached.result.duplicate(true) if isolate else cached.result
	var digest_context: HashingContext=HashingContext.new()
	digest_context.start(HashingContext.HASH_SHA256)
	digest_context.update(bytes)
	var identity: String=digest_context.finish().hex_encode()
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
	var issue: String = TransactionReceipt.problem(payload)
	if not issue.is_empty():
		return _error(ERR_FILE_CORRUPT, issue)
	var result: Dictionary = {"error":OK, "receipt":payload, "hash":digest,
		"bytes":length, "raw_identity":identity}
	if length <= MAX_CACHED_BYTES:
		if _record_cache.size() >= MAX_CACHED_RECORDS or _cached_bytes + length > MAX_CACHED_BYTES:
			_record_cache.clear()
			_cached_bytes = 0
		_record_cache[identity] = {"raw":bytes, "result":result.duplicate(true)}
		_cached_bytes += length
	return result


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
