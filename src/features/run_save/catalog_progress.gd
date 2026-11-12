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
var _verified_specialty_settlements: Dictionary[String, bool] = {}


func _init(slot: String) -> void:
	_slot = slot
	_folder = slot + ".catalog"
	_slot_hash = (slot.to_lower() if OS.has_feature("windows") else slot).sha256_text()


static func policy_problem(value: Variant) -> String:
	if not value is Dictionary or value.size() != 2 or not SurvivalContracts.integer(value.get("version"), VERSION, VERSION):
		return "CATALOG_POLICY"
	var unlock: Variant = value.get("unlock")
	return "" if unlock is String and (unlock.is_empty() or _hex(unlock, 64)) else "CATALOG_POLICY"


static func eligible_for(state: Dictionary, plan: String) -> Array[String]:
	return SpecializationProgress.eligible_for(state.get("specialties", {}), plan)


func refresh(fault: Callable) -> Dictionary:
	var stamp: int = FreezeProfile.enter("catalog.refresh")
	var result: Dictionary = _profiled_refresh(fault)
	FreezeProfile.leave("catalog.refresh", stamp)
	return result


func _profiled_refresh(fault: Callable) -> Dictionary:
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
	if _terminal_pending(live):
		return _blocked("CATALOG_TERMINAL_PENDING")
	return _refresh_specialties(state, live, fault)


func _refresh_specialties(state: Dictionary, live: Dictionary, fault: Callable) -> Dictionary:
	var archive_prefix: String = _slot.get_file() + SpecializationProgress.ARCHIVE_PREFIX
	var archives: Array[String] = []
	var parent: String = _slot.get_base_dir()
	if DirAccess.dir_exists_absolute(parent):
		var listing: Dictionary = ReceiptJournal.new(parent)._listing(parent)
		if listing.error != OK:
			return _blocked("CATALOG_SPECIALTY_ARCHIVE_READ")
		for entry: String in listing.files + listing.links:
			if entry.begins_with(archive_prefix):
				return _blocked("CATALOG_SPECIALTY_ARCHIVE_PATH")
		for folder: String in listing.directories:
			if folder.begins_with(archive_prefix):
				if not _hex(folder.trim_prefix(archive_prefix), 32):
					return _blocked("CATALOG_SPECIALTY_ARCHIVE_PATH")
				archives.append(parent.path_join(folder))
	archives.sort()
	var names: Dictionary = _specialty_records()
	if names.has("reason"):
		return names
	var experience: Dictionary = SpecializationProgress.initial()
	var discoveries: Dictionary = {}
	var seen_runs: Dictionary = {}
	var seen_roots: Dictionary = {}
	for folder: String in archives:
		var history: Dictionary = _history(folder)
		if history.has("reason"):
			return history
		if history.opening.get("version") != OpeningBuild.SPECIALTY_VERSION or history.run_id != folder.get_file().trim_prefix(archive_prefix) \
				or seen_runs.has(history.run_id) or seen_roots.has(history.root_id) or _terminal_pending(history):
			return _blocked("CATALOG_SPECIALTY_ARCHIVE_SOURCE")
		seen_runs[history.run_id] = true
		seen_roots[history.root_id] = true
		var projection: Dictionary = _specialty_history(history, names, false, fault)
		if projection.has("reason"):
			return projection
		discoveries.merge(projection.discoveries)
		if not projection.event.is_empty():
			experience[projection.event.plan] += int(projection.event.delta)
	state.specialization_result = {}
	state.m47_run_id = ""
	if not live.is_empty() and live.opening.get("version") == OpeningBuild.SPECIALTY_VERSION:
		if seen_runs.has(live.run_id) or seen_roots.has(live.root_id):
			return _blocked("CATALOG_SPECIALTY_REUSED_RUN")
		var plan: String = live.opening.plan
		var confirmed_eligible: Array[String] = SpecializationProgress.eligible_for(experience, plan)
		for id: String in live.opening.specialty.eligible:
			if id not in confirmed_eligible:
				return _blocked("CATALOG_SPECIALTY_SOURCE_MISSING")
		var projection: Dictionary = _specialty_history(live, names, true, fault)
		if projection.has("reason"):
			return projection
		state.m47_run_id = live.run_id
		discoveries.merge(projection.discoveries)
		state.specialization_result = SpecializationProgress.result_for(projection.event, int(experience[plan]))
		if not projection.event.is_empty():
			experience[plan] = state.specialization_result.after
	if not names.is_empty():
		return _blocked("CATALOG_SPECIALTY_SOURCE_MISSING")
	state.specialties = experience
	state.specialty_discoveries = discoveries
	return state


func _specialty_records() -> Dictionary:
	var names: Dictionary = {}
	if not DirAccess.dir_exists_absolute(_folder):
		return names
	var listing: Dictionary = ReceiptJournal.new(_folder)._listing(_folder)
	if listing.error != OK:
		return _blocked("CATALOG_SPECIALTY_READ")
	for entry: String in listing.directories + listing.links:
		if entry.begins_with(SpecializationProgress.RECORD_PREFIX):
			return _blocked("CATALOG_SPECIALTY_RECORD_PATH")
	for entry: String in listing.files:
		if not entry.begins_with(SpecializationProgress.RECORD_PREFIX):
			continue
		var name: String = entry.trim_suffix(".json")
		if name == entry or not _hex(name.trim_prefix(SpecializationProgress.RECORD_PREFIX), 32):
			return _blocked("CATALOG_SPECIALTY_RECORD_PATH")
		names[name] = true
	return names


func _specialty_history(history: Dictionary, names: Dictionary, live: bool, fault: Callable) -> Dictionary:
	var projection: Dictionary = _specialty_projection(history)
	if projection.has("reason"):
		return _blocked(projection.reason)
	var kind: String = SpecializationProgress.RECORD_PREFIX + history.run_id
	var event: Dictionary = projection.event
	var award: bool = int(event.get("delta", 0)) > 0
	if names.erase(kind):
		var saved: Dictionary = _read_event(kind)
		if saved.has("reason"):
			return saved
		if not award or not TransactionReceipt.same(saved.get("event", {}), event):
			return _blocked("CATALOG_SPECIALTY_SOURCE")
	elif award:
		if not live:
			return _blocked("CATALOG_SPECIALTY_RECORD_MISSING")
		var published: Dictionary = _publish(kind, event, fault)
		if published.has("reason"):
			return published
	return projection


func _specialty_projection(history: Dictionary) -> Dictionary:
	var stamp: int = FreezeProfile.enter("catalog.specialty_projection")
	var key: String = _projection_key(history, "specialty", "")
	var memo: Dictionary = _projection_get(history, key)
	var result: Dictionary
	if memo.has("value"):
		result = memo.value
	else:
		result = SpecializationProgress.derive(history, _slot_hash, _verified_specialty_settlements)
		_projection_put(history, key, result)
	FreezeProfile.leave("catalog.specialty_projection", stamp)
	return result


func _history(folder: String) -> Dictionary:
	var stamp: int = FreezeProfile.enter("catalog.history")
	var result: Dictionary = _profiled_history(folder)
	FreezeProfile.leave("catalog.history", stamp)
	return result


func _profiled_history(folder: String) -> Dictionary:
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
	var root: Dictionary = journal._read_record(journal.directory.path_join("00000001/record.json"), false)
	if root.error != OK or root.hash != binding.root_hash:
		return _blocked("CATALOG_HISTORY_CHANGED")
	var initial: Dictionary = root.receipt.base.get("journey", {})
	return {"journal":journal, "hashes":verified.hashes, "through":revision, "tip":verified.receipt,
		"run_id":binding.run_id, "root_id":binding.root_id,
		"opening":initial.get("build", {}).get("opening", {}), "open_streets":initial.get("campaign", {}).get("open_streets_policy", 0),
		"memo_token":journal.prefix_memo_token()}


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
	var stamp: int = FreezeProfile.enter("catalog.derive." + kind)
	var key: String = _projection_key(history, kind, unlock_hash)
	var memo: Dictionary = _projection_get(history, key)
	var result: Dictionary
	if memo.has("value"):
		result = memo.value
	else:
		result = _scan_derive(history, kind, unlock_hash)
		_projection_put(history, key, result)
	FreezeProfile.leave("catalog.derive." + kind, stamp)
	return result


func _scan_derive(history: Dictionary, kind: String, unlock_hash: String) -> Dictionary:
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


func _projection_key(history: Dictionary, kind: String, unlock_hash: String) -> String:
	if not history.has("journal") or String(history.get("memo_token", "")).is_empty():
		return ""
	# This key selects a pure projection inside an already byte-witnessed prefix.
	# Its hashes are never used to authenticate a file or replace read_all/binding checks.
	# Journal revisions are integer dictionary keys, while Exact V1 accepts only
	# string dictionary keys. Preserve every revision/hash as an ordered value pair.
	var revisions: Array = history.hashes.keys()
	revisions.sort()
	var hashes: Array = []
	for revision: int in revisions:
		hashes.append([revision, history.hashes[revision]])
	var context: Dictionary = {"slot":_slot_hash, "kind":kind, "unlock":unlock_hash,
		"through":history.through, "run_id":history.run_id, "root_id":history.root_id,
		"opening":history.opening, "open_streets":history.open_streets, "hashes":hashes,
		"catalog_policy":history.tip.base.get("journey", {}).get("build", {}).get("catalog", null)}
	return RecordEncoding.pack_v1(context).get("hash", "")


func _projection_get(history: Dictionary, key: String) -> Dictionary:
	if key.is_empty():
		return {}
	var journal: ReceiptJournal = history.journal
	var result: Dictionary = journal.prefix_memo_get(key, history.memo_token)
	FreezeProfile.count("catalog_projection_hits" if result.has("value") else "catalog_projection_misses")
	return result


func _projection_put(history: Dictionary, key: String, result: Dictionary) -> void:
	if key.is_empty() or result.has("reason"):
		return
	var journal: ReceiptJournal = history.journal
	journal.prefix_memo_put(key, result, history.memo_token)


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
	var specialty: bool = kind.begins_with(SpecializationProgress.RECORD_PREFIX)
	if specialty and fault.is_valid() and fault.call("before_specialty_publish") != OK:
		return _blocked("CATALOG_SPECIALTY_PENDING")
	if FileAccess.file_exists(path) or DirAccess.rename_absolute(staged, path) != OK:
		return _blocked("CATALOG_PUBLISH")
	if specialty and fault.is_valid() and fault.call("after_specialty_publish") != OK:
		return _blocked("CATALOG_SPECIALTY_PENDING")
	return _read_event(kind)


static func _terminal(receipt: Dictionary) -> bool:
	if receipt.get("phase") not in ["RESULT_READY", "COMMITTED"]:
		return false
	var camp: Dictionary = TransactionReceipt.camp(receipt)
	if not camp.get("journey", {}).get("build", {}).has("catalog"):
		return false
	var campaign: Dictionary = camp.journey.campaign
	if campaign.result_transaction != receipt.transaction_id:
		return false
	if campaign.outcome == "DEFEAT":
		# Rations settle after evacuation, so an extracted sortie can still end the journey.
		return camp.journey.active_member_ids.is_empty()
	var battle: Dictionary = receipt.envelope.result.battle
	return campaign.outcome == "VICTORY" and battle.evacuated and battle.mission_outcome == "EXTRACTED"


static func _terminal_pending(history: Dictionary) -> bool:
	return not history.is_empty() and _terminal(history.tip) \
		and (history.tip.phase != "COMMITTED" or history.tip.revision > history.through)


static func _found(receipt: Dictionary, battle: Dictionary, unlock_hash: String) -> bool:
	var before: Dictionary = receipt.base.journey.build
	var generated: Dictionary = receipt.rules.mission.generated
	var after: Dictionary = TransactionReceipt.camp(receipt).journey.build
	return before.catalog.unlock == unlock_hash and BuildItems.has_catalog(int(generated.get("gear_build_policy", 0))) \
		and BuildItems.FILTER not in before.owned and BuildItems.FILTER in after.owned \
		and BuildItems.FILTER in BuildState.acquired(generated, battle.site_facts, battle.evacuated)


static func _hex(value: Variant, length: int) -> bool:
	return value is String and value.length() == length and value == value.to_lower() and value.is_valid_hex_number(false)


static func _blocked(reason: String) -> Dictionary:
	return {"error":ERR_UNAVAILABLE, "reason":reason, "unlock":{}, "discovery":{}, "unlock_hash":"",
		"specialties":{}, "specialty_discoveries":{}, "specialization_result":{}}
