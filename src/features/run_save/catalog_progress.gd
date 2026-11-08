class_name CatalogProgress
extends RefCounted
## Read and publish under the existing progress-slot writer. Each milestone is immutable.

const VERSION: int = 1
const REQUIRED_RETURNS: int = 2
const MAX_RECORD_BYTES: int = 4096
const MILESTONES: Array[String] = ["unlock", "discovery"]

var _slot: String
var _folder: String
var _slot_hash: String


func _init(slot: String) -> void:
	_slot = slot
	_folder = slot + ".catalog"
	_slot_hash = (slot.to_lower() if OS.has_feature("windows") else slot).sha256_text()


static func policy_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 2 or not SurvivalContracts.integer(value.get("version"), VERSION, VERSION):
		return "CATALOG_POLICY"
	var unlock: Variant = value.get("unlock")
	return "" if unlock is String and (unlock.is_empty() or _hex(unlock, 64)) else "CATALOG_POLICY"


func refresh(fault: Callable) -> Dictionary:
	if not ProgressWriter._unlinked(_folder) or FileAccess.file_exists(_folder):
		return _blocked("CATALOG_PATH")
	var live_path: String = _slot + ".txn"
	if not ProgressWriter._unlinked(live_path) or FileAccess.file_exists(live_path):
		return _blocked("CATALOG_HISTORY_PATH")
	var live: Dictionary = _history(live_path) if DirAccess.dir_exists_absolute(live_path) else {}
	if live.has("reason"):
		return live
	var stored_unlock: Dictionary = _read_event("unlock")
	var stored_discovery: Dictionary = _read_event("discovery")
	for record: Dictionary in [stored_unlock, stored_discovery]:
		if record.has("reason"):
			return record
	var frozen: String = live.get("tip", {}).get("base", {}).get("journey", {}).get("build", {}).get("catalog", {}).get("unlock", "")
	if (stored_unlock.is_empty() and not stored_discovery.is_empty()) \
			or (not frozen.is_empty() and stored_unlock.get("hash") != frozen):
		return _blocked("CATALOG_UNLOCK_MISSING")
	var state: Dictionary = {"error":OK, "unlock":{}, "discovery":{}, "unlock_hash":""}
	for kind: String in MILESTONES:
		var saved: Dictionary = stored_unlock if kind == "unlock" else stored_discovery
		if not saved.is_empty():
			var history: Dictionary = _source_history(saved.event, live)
			var expected: Dictionary = _derive(history, kind, state.unlock_hash)
			if not TransactionReceipt.same(expected, saved.event):
				return _blocked("CATALOG_SOURCE")
			state[kind] = saved.event
			if kind == "unlock":
				state.unlock_hash = saved.hash
			continue
		var event: Dictionary = _derive(live, kind, state.unlock_hash)
		if event.has("reason"):
			return event
		if not event.is_empty():
			var result: Dictionary = _publish(kind, event, fault)
			if result.has("reason"):
				return result
			state[kind] = result.event
			if kind == "unlock":
				state.unlock_hash = result.hash
	if not live.is_empty() and _terminal(live.tip) \
			and (live.tip.phase != "COMMITTED" or live.tip.revision > live.through):
		return _blocked("CATALOG_TERMINAL_PENDING")
	return state


func _history(folder: String) -> Dictionary:
	if not ProgressWriter._unlinked(folder.path_join("binding.json")) or not ProgressWriter._unlinked(folder.path_join("journal")):
		return _blocked("CATALOG_HISTORY_PATH")
	var decoded: Dictionary = RunTransaction.read_binding(folder.path_join("binding.json"))
	if decoded.error != OK:
		return _blocked("CATALOG_HISTORY_BINDING")
	var binding: Dictionary = decoded.payload
	if binding.size() != 7 or not SurvivalContracts.integer(binding.get("binding_version"), 1, 1) \
			or not _hex(binding.get("run_id"), 32) or not _hex(binding.get("root_id"), 32) \
			or binding.get("journal") != _slot + ".txn/journal" \
			or not SurvivalContracts.integer(binding.get("revision"), 1, 4096):
		return _blocked("CATALOG_HISTORY_BINDING")
	var journal: ReceiptJournal = ReceiptJournal.new(folder.path_join("journal"))
	var verified: Dictionary = journal.read_all()
	if verified.error != OK or verified.receipt.is_empty():
		return _blocked("CATALOG_HISTORY_JOURNAL")
	var revision: int = int(binding.revision)
	if not verified.hashes.has(revision) or verified.hashes[revision] != binding.get("head_hash") \
			or verified.hashes.get(1) != binding.get("root_hash") \
			or verified.receipt.base.profile_id != binding.run_id or verified.receipt.root_id != binding.root_id:
		return _blocked("CATALOG_HISTORY_ANCHOR")
	return {"journal":journal, "hashes":verified.hashes, "through":revision, "tip":verified.receipt,
		"run_id":binding.run_id, "root_id":binding.root_id}


func _source_history(event: Dictionary, live: Dictionary) -> Dictionary:
	if live.get("run_id") == event.run_id and live.get("root_id") == event.root_id:
		return live
	var prefix: String = _slot.get_file() + ".txn.previous-"
	for name: String in DirAccess.get_directories_at(_slot.get_base_dir()):
		if not name.begins_with(prefix):
			continue
		var folder: String = _slot.get_base_dir().path_join(name)
		var path: String = folder.path_join("binding.json")
		if not ProgressWriter._unlinked(path):
			continue
		var binding: Dictionary = RunTransaction.read_binding(path)
		if binding.error == OK and binding.payload.get("run_id") == event.run_id and binding.payload.get("root_id") == event.root_id:
			return _history(folder)
	return {}


func _derive(history: Dictionary, kind: String, unlock_hash: String) -> Dictionary:
	if not history.has("journal") or (kind == "discovery" and unlock_hash.is_empty()) \
			or not history.tip.base.get("journey", {}).get("build", {}).has("catalog"):
		return {}
	var journal: ReceiptJournal = history.journal
	var returned: Array[Dictionary] = []
	for revision: int in range(1, int(history.through) + 1):
		var row: Dictionary = journal._read_record(journal.directory.path_join("%08d/record.json" % revision), false)
		if row.error != OK or row.hash != history.hashes[revision]:
			return _blocked("CATALOG_HISTORY_CHANGED")
		var receipt: Dictionary = row.receipt
		if receipt.phase != "COMMITTED":
			continue
		var battle: Dictionary = receipt.envelope.result.battle
		var ref: Dictionary = {"transaction_id":receipt.transaction_id, "revision":revision, "hash":row.hash}
		if kind == "unlock":
			if not _terminal(receipt):
				if battle.evacuated and battle.mission_outcome == "EXTRACTED" and returned.size() < REQUIRED_RETURNS:
					returned.append(ref)
				continue
			if returned.size() < REQUIRED_RETURNS:
				continue
		elif not _found(receipt, battle, unlock_hash):
			continue
		return {"version":VERSION, "slot":_slot_hash, "kind":kind, "run_id":history.run_id,
			"root_id":history.root_id, "receipt":ref, "returns":returned}
	return {}


func _read_event(kind: String) -> Dictionary:
	var path: String = _folder.path_join(kind + ".json")
	if not ProgressWriter._unlinked(path) or DirAccess.dir_exists_absolute(path):
		return _blocked("CATALOG_EVENT_PATH")
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_RECORD_BYTES:
		return _blocked("CATALOG_EVENT_READ")
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var decoded_text: String = bytes.get_string_from_utf8()
	var raw: Variant = JSON.parse_string(decoded_text) if decoded_text.to_utf8_buffer() == bytes else null
	if not raw is Dictionary:
		return _blocked("CATALOG_EVENT_JSON")
	var decoded: Dictionary = RecordEncoding.unpack(raw)
	if decoded.error != OK:
		return _blocked("CATALOG_EVENT_HASH")
	var event: Dictionary = decoded.payload
	if event.get("slot") != _slot_hash or event.get("kind") != kind \
			or not _hex(event.get("run_id"), 32) or not _hex(event.get("root_id"), 32):
		return _blocked("CATALOG_EVENT_IDENTITY")
	return {"event":event, "hash":decoded.hash}


func _publish(kind: String, event: Dictionary, fault: Callable) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(_folder) != OK:
		return _blocked("CATALOG_WRITE")
	var path: String = _folder.path_join(kind + ".json")
	var staged: String = _folder.path_join(".stage-" + RunSave.new_profile_id())
	var file: FileAccess = FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return _blocked("CATALOG_WRITE")
	var packed: Dictionary = RecordEncoding.pack(event)
	file.store_string(packed.text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(staged) != packed.text:
		return _blocked("CATALOG_WRITE")
	if fault.is_valid() and fault.call("before_catalog_publish") != OK:
		return _blocked("CATALOG_WRITE")
	if FileAccess.file_exists(path) or DirAccess.rename_absolute(staged, path) != OK:
		return _blocked("CATALOG_PUBLISH")
	return _read_event(kind)


static func _terminal(receipt: Dictionary) -> bool:
	if receipt.get("phase") not in ["RESULT_READY", "COMMITTED"]:
		return false
	var camp: Dictionary = TransactionReceipt.camp(receipt)
	if not camp.get("journey", {}).get("build", {}).has("catalog"):
		return false
	var battle: Dictionary = receipt.envelope.result.battle
	var campaign: Dictionary = camp.journey.campaign
	if campaign.result_transaction != receipt.transaction_id:
		return false
	return (campaign.outcome == "VICTORY" and battle.evacuated and battle.mission_outcome == "EXTRACTED") \
		or (campaign.outcome == "DEFEAT" and not battle.evacuated and battle.mission_outcome == "FAILED" \
			and camp.journey.active_member_ids.is_empty())


static func _found(receipt: Dictionary, battle: Dictionary, unlock_hash: String) -> bool:
	var before: Dictionary = receipt.base.journey.build
	var generated: Dictionary = receipt.rules.mission.generated
	var after: Dictionary = TransactionReceipt.camp(receipt).journey.build
	return before.catalog.unlock == unlock_hash and generated.get("gear_build_policy") == BuildItems.CATALOG_POOL \
		and BuildItems.FILTER not in before.owned and BuildItems.FILTER in after.owned \
		and BuildItems.FILTER in BuildState.acquired(generated, battle.site_facts, battle.evacuated)


static func _hex(value: Variant, length: int) -> bool:
	return value is String and value.length() == length and value == value.to_lower() and value.is_valid_hex_number(false)


static func _blocked(reason: String) -> Dictionary:
	return {"error":ERR_UNAVAILABLE, "reason":reason, "unlock":{}, "discovery":{}, "unlock_hash":""}
