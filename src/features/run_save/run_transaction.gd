class_name RunTransaction
extends RefCounted
## Explicit opt-in coordinator. No production caller, scene, rules recalculation or implicit path.

var _journal: ReceiptJournal
var _save: RunSave
var _fault: Callable
var _path_problem: String = ""
var _run_id: String
var _root_id: String
var _writer: ProgressWriter
var _binding_path: String
var _session_writer: ProgressWriter
var _claim_retry_hash: String = ""


func _init(journal_directory: String, camp_path: String, run_id: String, root_id: String, fault_hook: Callable = Callable(), session_writer: ProgressWriter = null) -> void:
	_journal = ReceiptJournal.new(journal_directory, fault_hook)
	var file_name: String = camp_path.replace("\\", "/").get_file().to_lower()
	_save = RunSave.new(camp_path, file_name == "run.battle-v1.json", file_name == "run.survival-v1.json", file_name == "run.rescue-v1.json", file_name == "run.growth-v1.json", file_name == "run.field-join-v1.json", file_name == "run.trait-v1.json", file_name == "run.training-v1.json", file_name == "run.rescue-pool-v1.json", file_name == "run.roster-v1.json", file_name == "run.weapon-quality-v1.json", file_name == "run.enemy-v1.json")
	_fault = fault_hook
	_session_writer = session_writer
	_run_id = run_id
	_root_id = root_id
	_binding_path = _save.path + ".txn/binding.json"
	var normalized: String = _save.path.replace("\\", "/").to_lower()
	var journal_path: String = _journal.directory.to_lower()
	if not camp_path.is_absolute_path() or camp_path.begins_with("res://") or camp_path.begins_with("user://") or normalized == journal_path or normalized.begins_with(journal_path + "/"):
		_path_problem = "EXPLICIT_SEPARATE_PATHS_REQUIRED"
	if normalized + ".txn/journal" != journal_path or run_id.length() != 32 or not run_id.is_valid_hex_number(false) or root_id.length() != 32 or not root_id.is_valid_hex_number(false):
		_path_problem = "CANONICAL_RUN_ROOT_REQUIRED"
	if not ProgressWriter._unlinked(_journal.directory) or not ProgressWriter._unlinked(_binding_path):
		_path_problem = "LINKED_TRANSACTION_PATH"


func register(base: Dictionary) -> Dictionary:
	return _execute(_register.bind(base), false)


func begin(base: Dictionary, identity: String, rules: Dictionary) -> Dictionary:
	return _execute(_begin.bind(base, identity, rules))


func join_field(token: Dictionary, event: Dictionary) -> Dictionary:
	return _execute(_checked.bind(token,_join_field.bind(event)))


func checkpoint(token: Dictionary, health: Array) -> Dictionary:
	return _execute(_checked.bind(token, _checkpoint.bind(health)))


func confirm_death(token: Dictionary, death: Dictionary, health_before: float) -> Dictionary:
	return _execute(_checked.bind(token, _confirm_death.bind(death, health_before)))


func prepare(token: Dictionary, envelope: Dictionary, camp_key: String = "") -> Dictionary:
	return _execute(_checked.bind(token, _prepare.bind(envelope, camp_key)))


func suspend(token: Dictionary, world: Dictionary) -> Dictionary:
	return _execute(_checked.bind(token, _suspend.bind(world)))


func preview_suspend(token: Dictionary, world: Dictionary) -> Dictionary:
	return _execute(_checked.bind(token, _suspend.bind(world,false)),true,false)


func claim_suspend(token: Dictionary, world_hash: String, generation: String = "") -> Dictionary:
	var result: Dictionary = _execute(_checked.bind(token, _claim_suspend.bind(world_hash,generation)))
	if result.error == OK:
		_claim_retry_hash = ""
	return result


func commit(token: Dictionary) -> Dictionary:
	return _execute(_checked.bind(token, _commit))


func recover() -> Dictionary:
	return _execute(_recover, true, false)


func validate_action(token: Dictionary) -> Dictionary:
	return _execute(_checked.bind(token, _active), true, false)


func prepare_edit(expected_head: String, identity: String, request: Dictionary) -> Dictionary:
	return _execute(_prepare_edit.bind(expected_head, identity, request))


func commit_edit(identity: String) -> Dictionary:
	return _execute(_commit_edit.bind(identity))


func resolve_interruption(_token: Dictionary) -> Dictionary:
	return _error(ERR_UNAVAILABLE, "INTERRUPTION_POLICY_REQUIRES_APPROVAL")


static func token_for(receipt: Dictionary) -> Dictionary:
	if receipt.is_empty() or receipt.phase in ["CAMP_REGISTERED", "EDIT_READY", "EDIT_COMMITTED"]:
		return {}
	return {"run_id":receipt.base.profile_id, "root_id":receipt.root_id,
		"transaction_id":receipt.transaction_id, "base_hash":SurvivalContracts.fingerprint(receipt.base),
		"rules_hash":SurvivalContracts.fingerprint(receipt.rules)}


func _execute(operation: Callable, require_binding: bool = true, acknowledge: bool = true) -> Dictionary:
	if not _path_problem.is_empty():
		return _error(ERR_INVALID_PARAMETER, _path_problem)
	var owner: ProgressWriter = _session_writer if _session_writer != null else ProgressWriter.new(_save.path)
	var error: Error = (OK if owner.owns(_save.path) else ERR_UNAUTHORIZED) if _session_writer != null else owner.acquire()
	if error != OK:
		return _error(error, owner.reason)
	_writer = owner
	var result: Dictionary = _binding_check() if require_binding else {"error":OK}
	if result.error == OK:
		result = operation.call()
	if result.error == OK and acknowledge and not result.get("receipt", {}).is_empty():
		var remembered: Dictionary = _remember(result)
		if remembered.error != OK:
			result = remembered
	if result.error == OK:
		result.token = token_for(result.get("receipt", {}))
	_writer = null
	if _session_writer == null:
		owner.release()
	return result


func _checked(token: Dictionary, operation: Callable) -> Dictionary:
	var loaded: Dictionary = _load()
	if loaded.error != OK:
		return loaded
	var expected: Dictionary = token_for(loaded.receipt)
	if expected.is_empty() or not TransactionReceipt.same(token, expected):
		return _error(ERR_INVALID_DATA, "STALE_OR_FOREIGN_OPERATION_TOKEN")
	return operation.call()


func _register(base: Dictionary) -> Dictionary:
	if FileAccess.file_exists(_binding_path):
		var binding: Dictionary = _binding_check()
		if binding.error != OK:
			return binding
	if not TransactionReceipt.camp_problem(base).is_empty() or base.profile_id != _run_id:
		return _error(ERR_INVALID_DATA, "REGISTRATION_BASE")
	var disk: Dictionary = _save.read_transaction_exact()
	if disk.error != OK or not TransactionReceipt.same(disk.data, base):
		return _error(ERR_INVALID_DATA, "BASE_NOT_DURABLE")
	var loaded: Dictionary = _load()
	if loaded.error != OK:
		return loaded
	if not loaded.receipt.is_empty():
		if loaded.receipt.phase != "CAMP_REGISTERED" or not TransactionReceipt.same(loaded.receipt.base, base):
			return _error(ERR_INVALID_DATA, "REGISTRATION_ALREADY_USED")
		if not FileAccess.file_exists(_binding_path):
			var directory: DirAccess = DirAccess.open(_binding_path.get_base_dir())
			if directory == null:
				return _error(ERR_CANT_OPEN, "BINDING_DIRECTORY_UNREADABLE")
			for file_name: String in directory.get_files():
				if file_name.begins_with("binding.json.previous-"):
					return _error(ERR_FILE_CORRUPT, "BINDING_LOST_AFTER_CONFIRMATION")
		return _recover()
	if FileAccess.file_exists(_binding_path):
		return _error(ERR_FILE_CORRUPT, "REQUIRED_JOURNAL_MISSING")
	var error: Error = DirAccess.make_dir_recursive_absolute(_binding_path.get_base_dir())
	if error != OK:
		return _error(error, "BINDING_DIRECTORY")
	return _append(TransactionReceipt.registration(base, _root_id), "")


func _prepare_edit(expected_head: String, identity: String, request: Dictionary) -> Dictionary:
	var loaded: Dictionary = _recover()
	if loaded.error != OK:
		return loaded
	if loaded.receipt.transaction_id == identity and loaded.receipt.phase in ["EDIT_READY", "EDIT_COMMITTED"]:
		return loaded if TransactionReceipt.same(loaded.receipt.rules.request, request) else _error(ERR_INVALID_DATA, "EDIT_ID_CONFLICT")
	if loaded.state not in ["CAMP_READY", "CAMP_EDITED", "ALREADY_COMMITTED"] or loaded.hash != expected_head:
		return _error(ERR_BUSY, "EDIT_REQUIRES_CONFIRMED_CAMP_HEAD")
	var before: Dictionary = TransactionReceipt.camp(loaded.receipt)
	var after: Dictionary = CampEdit.propose(before, request)
	if after.is_empty():
		return _error(ERR_INVALID_DATA, "EDIT_REQUEST")
	if TransactionReceipt.same(before, after):
		return loaded
	var next: Dictionary = CampEdit.record(before, request, identity, loaded.receipt)
	return _append(next, loaded.hash)


func _commit_edit(identity: String) -> Dictionary:
	var loaded: Dictionary = _load()
	if loaded.error != OK:
		return loaded
	if loaded.receipt.is_empty() or loaded.receipt.phase not in ["EDIT_READY", "EDIT_COMMITTED"] or loaded.receipt.transaction_id != identity:
		return _error(ERR_INVALID_DATA, "STALE_EDIT_ID")
	return _commit()


func _binding_check() -> Dictionary:
	var stamp: int = FreezeProfile.enter("binding.check")
	var result: Dictionary = _profiled_binding_check()
	FreezeProfile.leave("binding.check", stamp)
	return result


func _profiled_binding_check() -> Dictionary:
	var file: FileAccess = FileAccess.open(_binding_path, FileAccess.READ)
	if file == null:
		return _error(ERR_FILE_CORRUPT, "REQUIRED_BINDING_MISSING_OR_UNREADABLE")
	if file.get_length() == 0 or file.get_length() > 4096:
		file.close()
		return _error(ERR_FILE_CORRUPT, "BINDING_SIZE")
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var text: String = bytes.get_string_from_utf8()
	var parser: JSON = JSON.new()
	var value: Variant = parser.data if text.to_utf8_buffer() == bytes and parser.parse(text) == OK else null
	if not value is Dictionary or value.size() != 2 or not value.get("payload") is Dictionary or not value.get("sha256") is String or TransactionReceipt.legacy_fingerprint(value.payload) != value.sha256:
		return _error(ERR_FILE_CORRUPT, "BINDING_HASH")
	var binding: Dictionary = value.payload
	if binding.size() != 7 or binding.get("binding_version") != 1 or binding.get("run_id") != _run_id or binding.get("root_id") != _root_id or binding.get("journal") != _journal.directory or not SurvivalContracts.integer(binding.get("revision"), 1, 4096):
		return _error(ERR_INVALID_DATA, "BINDING_IDENTITY")
	var loaded: Dictionary = _load()
	if loaded.error != OK:
		return loaded
	var hashes: Dictionary = loaded.get("hashes", {})
	if not hashes.has(int(binding.revision)) or hashes.get(1) != binding.get("root_hash") or hashes.get(int(binding.revision)) != binding.get("head_hash"):
		return _error(ERR_FILE_CORRUPT, "CONFIRMED_JOURNAL_HEAD_MISSING")
	return {"error":OK}


func _remember(loaded: Dictionary) -> Dictionary:
	var stamp: int = FreezeProfile.enter("binding.remember")
	var result: Dictionary = _profiled_remember(loaded)
	FreezeProfile.leave("binding.remember", stamp)
	return result


func _profiled_remember(loaded: Dictionary) -> Dictionary:
	var receipt: Dictionary = loaded.receipt
	var payload: Dictionary = {"binding_version":1, "run_id":_run_id, "root_id":_root_id,
		"journal":_journal.directory, "revision":receipt.revision,
		"root_hash":loaded.hashes[1], "head_hash":loaded.hash}
	var serialized: String = JSON.stringify({"payload":payload, "sha256":TransactionReceipt.legacy_fingerprint(payload)}, "", true, true) + "\n"
	if FileAccess.file_exists(_binding_path) and FileAccess.get_file_as_string(_binding_path) == serialized:
		return {"error":OK}
	if _inject("before_binding_write") != OK:
		return _error(ERR_CANT_CREATE, "BINDING_CONFIRMATION_PENDING")
	var temporary: String = _binding_path + ".tmp-" + RunSave.new_profile_id()
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error(FileAccess.get_open_error(), "BINDING_WRITE")
	file.store_string(serialized)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != serialized:
		return _error(ERR_FILE_CORRUPT, "BINDING_READBACK")
	if _inject("after_binding_flush") != OK:
		return _error(ERR_CANT_CREATE, "BINDING_CONFIRMATION_PENDING")
	var previous: String = _binding_path + ".previous-" + RunSave.new_profile_id()
	if FileAccess.file_exists(_binding_path):
		error = DirAccess.rename_absolute(_binding_path, previous)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, _binding_path)
	if error != OK:
		if not FileAccess.file_exists(_binding_path) and FileAccess.file_exists(previous):
			DirAccess.rename_absolute(previous, _binding_path)
		return _error(error, "BINDING_PUBLICATION")
	return _binding_check()


func _begin(base: Dictionary, identity: String, rules: Dictionary) -> Dictionary:
	var loaded: Dictionary = _load()
	if loaded.error != OK:
		return loaded
	if not TransactionReceipt.camp_problem(base).is_empty():
		return _error(ERR_INVALID_DATA, "BASE_FORMAT")
	if not SurvivalContracts.json_value(rules):
		return _error(ERR_INVALID_DATA, "RULES_VALUE")
	var previous: Dictionary = loaded.receipt
	if not previous.is_empty() and previous.transaction_id == identity:
		if TransactionReceipt.same(previous.base, base) and TransactionReceipt.same(previous.rules, rules):
			return _recover()
		return _error(ERR_INVALID_DATA, "DUPLICATE_TRANSACTION_CONFLICT")
	var disk: Dictionary = _save.read_transaction_exact()
	if disk.error != OK or not TransactionReceipt.same(disk.data, base):
		return _error(ERR_INVALID_DATA, "BASE_DISK_MISMATCH")
	var receipt: Dictionary = TransactionReceipt.initial(base, identity, rules, previous)
	return _append(receipt, loaded.hash)


func _join_field(event: Dictionary) -> Dictionary:
	var loaded: Dictionary = _active()
	if loaded.error != OK:
		return loaded
	var next: Dictionary = loaded.receipt.duplicate(true)
	if not FieldJoinState.is_family(next.base) or not FrozenSettlement._rules_problem(next.rules).is_empty() or next.rules.get("scope") != (RescuePoolState.SCOPE if RescuePoolState.is_family(next.base) else TraitState.SCOPE if TraitState.is_family(next.base) else FieldJoinState.SCOPE) or next.rules.mission.get("mission_id") != "rescue" or not FieldJoinRules.problem([event],next.base,next.transaction_id).is_empty():
		return _error(ERR_INVALID_DATA,"FIELD_JOIN_SOURCE")
	if not next.joins.is_empty():
		return loaded if TransactionReceipt.same(next.joins[0],event) else _error(ERR_INVALID_DATA,"FIELD_JOIN_CONFLICT")
	next.joins.append(event.duplicate(true))
	next.health.append({"id":int(event.member_id),"health":200.0})
	next.envelope = {}
	next.phase = "DEATH_CONFIRMED" if TransactionReceipt._has_current_death(next) else "IN_PROGRESS"
	next.revision += 1
	return _append(next,loaded.hash)


func _checkpoint(health: Array) -> Dictionary:
	if not SurvivalContracts.json_value(health):
		return _error(ERR_INVALID_DATA, "CHECKPOINT_VALUE")
	var loaded: Dictionary = _active()
	if loaded.error != OK:
		return loaded
	var next: Dictionary = loaded.receipt.duplicate(true)
	if TransactionReceipt.same({"rows":health}, {"rows":next.health}):
		return _recover()
	next.health = health.duplicate(true)
	next.envelope = {}
	next.phase = "DEATH_CONFIRMED" if TransactionReceipt._has_current_death(next) else "IN_PROGRESS"
	next.revision += 1
	return _append(next, loaded.hash)


func _confirm_death(death: Dictionary, health_before: float) -> Dictionary:
	var loaded: Dictionary = _recover()
	if loaded.error != OK or loaded.receipt.is_empty():
		return loaded if loaded.error != OK else _error(ERR_DOES_NOT_EXIST, "NO_TRANSACTION")
	var next: Dictionary = loaded.receipt.duplicate(true)
	if not DeathRules.problem(death, next.base.profile_id).is_empty() or not is_finite(health_before) or health_before <= 0:
		return _error(ERR_INVALID_DATA, "DEATH_INPUT")
	for existing: Dictionary in next.deaths:
		if int(existing.death.member_id) == int(death.member_id):
			return _recover() if TransactionReceipt.same(existing, {"death":death, "health_before":health_before}) else _error(ERR_INVALID_DATA, "DEATH_CONFLICT")
	if next.phase not in ["STARTED","IN_PROGRESS","DEATH_CONFIRMED","RESUME_CLAIMED"] or death.transaction_id != next.transaction_id:
		return _error(ERR_INVALID_DATA, "DEATH_PHASE")
	var member: Dictionary = SurvivorRoster.member(next.health, int(death.member_id))
	if member.is_empty() or health_before > float(member.health):
		return _error(ERR_INVALID_DATA, "DEATH_HEALTH_SOURCE")
	member.health = 0.0
	next.deaths.append({"death":death.duplicate(true), "health_before":health_before})
	next.envelope = {}
	next.phase = "DEATH_CONFIRMED"
	next.revision += 1
	return _append(next, loaded.hash)


func _prepare(envelope: Dictionary, camp_key: String = "") -> Dictionary:
	if not SurvivalContracts.json_value(envelope, -1):
		return _error(ERR_INVALID_DATA, "RESULT_VALUE")
	var loaded: Dictionary = _recover()
	if loaded.error != OK or loaded.receipt.is_empty():
		return loaded if loaded.error != OK else _error(ERR_DOES_NOT_EXIST, "NO_TRANSACTION")
	var next: Dictionary = loaded.receipt.duplicate(true)
	if next.phase in ["RESULT_READY", "COMMITTED"]:
		return _recover() if TransactionReceipt.same(next.envelope, envelope) and next.camp_key == camp_key else _error(ERR_INVALID_DATA, "FROZEN_RESULT_CONFLICT")
	if next.phase not in ["STARTED","IN_PROGRESS","DEATH_CONFIRMED","RESUME_CLAIMED"]:
		return _error(ERR_INVALID_DATA,"SUSPEND_MUST_BE_CLAIMED")
	next.envelope = envelope.duplicate(true)
	next.camp_key = camp_key
	next.phase = "RESULT_READY"
	next.revision += 1
	return _append(next, loaded.hash)


func _suspend(world: Dictionary, publish: bool = true) -> Dictionary:
	var loaded: Dictionary = _recover()
	if loaded.error != OK:
		return loaded
	var next: Dictionary = loaded.receipt.duplicate(true)
	if next.phase == "SUSPEND_READY":
		loaded.suspend_generation = next.envelope.previous_head
		return loaded if TransactionReceipt.same(world,next.envelope.world) else _error(ERR_INVALID_DATA,"PENDING_SUSPEND_CHANGED")
	if next.phase not in ["STARTED","IN_PROGRESS","DEATH_CONFIRMED","RESUME_CLAIMED"] or not world.get("survivors") is Array:
		return _error(ERR_INVALID_DATA,"NO_SUSPENDABLE_ACTION")
	var health: Array = []
	for row: Variant in world.survivors:
		if not row is Dictionary or not row.get("state") is Dictionary or not row.state.has_all(["member_id","health"]):
			return _error(ERR_INVALID_DATA,"SUSPEND_ACTOR_FIELDS")
		health.append({"id":row.state.member_id,"health":row.state.health})
	next.health = health
	next.phase = "SUSPEND_READY"
	next.envelope = SuspendRecord.make(world,token_for(next),loaded.hash)
	next.previous_hash = loaded.hash
	next.revision += 1
	var issue: String = TransactionReceipt.transition(loaded.receipt,next)
	if issue.is_empty():
		var serialized: String = RecordEncoding.stringify(next)
		issue = ReceiptJournal.capacity_problem(int(next.revision),next.phase,serialized.to_utf8_buffer().size(),int(loaded.bytes),loaded.unpublished.size())
	if not issue.is_empty():
		return _error(ERR_INVALID_DATA,issue)
	if not publish:
		loaded.suspend_generation = next.envelope.previous_head
		return loaded
	return _append(next,loaded.hash)


func _claim_suspend(world_hash: String, generation: String) -> Dictionary:
	var loaded: Dictionary = _recover()
	if loaded.error != OK:
		return loaded
	var next: Dictionary = loaded.receipt.duplicate(true)
	# The immutable predecessor identifies a publication even when its world is identical.
	# Check before the retry branch so a stale request cannot acknowledge another claim.
	if next.phase not in ["SUSPEND_READY","RESUME_CLAIMED"] or generation.is_empty() or generation != next.envelope.previous_head:
		return _error(ERR_INVALID_DATA,"STALE_OR_MISSING_SUSPEND_GENERATION")
	if next.phase == "RESUME_CLAIMED" and loaded.hash == _claim_retry_hash and next.envelope.world_hash == world_hash:
		return loaded
	if next.phase != "SUSPEND_READY" or next.envelope.world_hash != world_hash:
		return _error(ERR_INVALID_DATA,"SUSPEND_CONSUMED_OR_CHANGED")
	next.phase = "RESUME_CLAIMED"
	next.revision += 1
	next.previous_hash = loaded.hash
	_claim_retry_hash = TransactionReceipt.fingerprint(next)
	return _append(next,loaded.hash)


func _recover() -> Dictionary:
	var loaded: Dictionary = _load()
	if loaded.error != OK:
		return loaded
	var receipt: Dictionary = loaded.receipt
	if receipt.is_empty():
		return _error(ERR_FILE_CORRUPT, "REQUIRED_JOURNAL_MISSING")
	var disk: Dictionary = _save.read_transaction_exact()
	if receipt.phase == "CAMP_REGISTERED":
		if disk.error != OK or not TransactionReceipt.same(disk.data, receipt.base):
			return _error(ERR_INVALID_DATA, "REGISTERED_CAMP_CONFLICT")
		loaded.state = "CAMP_READY"
		return loaded
	var edited: bool = receipt.phase in ["EDIT_READY", "EDIT_COMMITTED"]
	var frozen: bool = edited or receipt.phase in ["RESULT_READY", "COMMITTED"]
	var after: Dictionary = TransactionReceipt.camp(receipt) if frozen else {}
	if frozen and disk.error == OK and TransactionReceipt.same(disk.data, after):
		if edited:
			loaded.state = "CAMP_EDITED" if receipt.phase == "EDIT_COMMITTED" else "EDIT_WRITTEN_RECEIPT_PENDING"
		else:
			loaded.state = "ALREADY_COMMITTED" if receipt.phase == "COMMITTED" else "CAMP_WRITTEN_RECEIPT_PENDING"
	elif disk.error == OK and TransactionReceipt.same(disk.data, receipt.base) and receipt.phase not in ["COMMITTED", "EDIT_COMMITTED"]:
		loaded.state = "EDIT_READY" if edited else ("RESULT_READY" if frozen else ("INTERRUPTED_WITH_DEATHS" if TransactionReceipt._has_current_death(receipt) else "INTERRUPTED"))
	elif receipt.phase in ["RESULT_READY", "EDIT_READY"] and disk.error == ERR_FILE_NOT_FOUND:
		var backup: Dictionary = RunSave.new(_save.path + ".bak",BattleState.is_state(receipt.base),SurvivalState.is_state(receipt.base),RescueState.is_state(receipt.base),GrowthState.is_state(receipt.base),FieldJoinState.is_state(receipt.base),TraitState.is_state(receipt.base),TrainingState.is_state(receipt.base),RescuePoolState.is_state(receipt.base),RosterState.is_state(receipt.base),WeaponState.is_state(receipt.base),EnemyState.is_state(receipt.base)).read_transaction_exact()
		if backup.error != OK or not TransactionReceipt.same(backup.data, receipt.base):
			return _error(ERR_FILE_CORRUPT, "MISSING_CAMP_WITHOUT_EXACT_BASE_BACKUP")
		loaded.state = "EDIT_READY_BASE_IN_BACKUP" if edited else "RESULT_READY_BASE_IN_BACKUP"
	else:
		return _error(ERR_INVALID_DATA, "CAMP_CONFLICT_OR_UNREADABLE")
	loaded.acknowledged = true
	return loaded


func _commit() -> Dictionary:
	var recovered: Dictionary = _recover()
	if recovered.error != OK:
		return recovered
	if recovered.state in ["ALREADY_COMMITTED", "CAMP_EDITED"]:
		return recovered
	if recovered.state not in ["RESULT_READY", "RESULT_READY_BASE_IN_BACKUP", "CAMP_WRITTEN_RECEIPT_PENDING", "EDIT_READY", "EDIT_READY_BASE_IN_BACKUP", "EDIT_WRITTEN_RECEIPT_PENDING"]:
		return _error(ERR_INVALID_DATA, "NO_FROZEN_RESULT")
	var receipt: Dictionary = recovered.receipt
	if recovered.state not in ["CAMP_WRITTEN_RECEIPT_PENDING", "EDIT_WRITTEN_RECEIPT_PENDING"]:
		if _inject("before_camp_write") != OK:
			return _error(ERR_CANT_CREATE, "INJECTED_CAMP_WRITE")
		# Recheck immediately before I/O; main integration must serialize all camp writers.
		var again: Dictionary = _recover()
		if again.error != OK or again.hash != recovered.hash or again.state not in ["RESULT_READY", "RESULT_READY_BASE_IN_BACKUP", "EDIT_READY", "EDIT_READY_BASE_IN_BACKUP"]:
			return _error(ERR_BUSY, "CAMP_CHANGED_BEFORE_WRITE")
		var error: Error = _save.save(TransactionReceipt.camp(receipt), false, _writer, _fault)
		if error != OK:
			return _error(error, "CAMP_WRITE_FAILED: " + _save.diagnostic)
		if _inject("after_camp_write") != OK:
			return _error(ERR_CANT_CREATE, "CAMP_WRITTEN_ACK_PENDING")
	var disk: Dictionary = _save.read_transaction_exact()
	if disk.error != OK or not TransactionReceipt.same(disk.data, TransactionReceipt.camp(receipt)):
		return _error(ERR_FILE_CORRUPT, "CAMP_READBACK")
	if _inject("before_commit_receipt") != OK:
		return _error(ERR_CANT_CREATE, "COMMIT_RECEIPT_PENDING")
	var next: Dictionary = receipt.duplicate(true)
	next.phase = "EDIT_COMMITTED" if receipt.phase == "EDIT_READY" else "COMMITTED"
	next.revision += 1
	return _append(next, recovered.hash)


func _active() -> Dictionary:
	var loaded: Dictionary = _recover()
	if loaded.error == OK and (loaded.receipt.is_empty() or loaded.receipt.phase not in ["STARTED", "IN_PROGRESS", "DEATH_CONFIRMED","RESUME_CLAIMED"]):
		return _error(ERR_INVALID_DATA, "NO_ACTIVE_ACTION")
	return loaded


func _load() -> Dictionary:
	var stamp: int = FreezeProfile.enter("transaction.load")
	var result: Dictionary = _profiled_load()
	FreezeProfile.leave("transaction.load", stamp)
	return result


func _profiled_load() -> Dictionary:
	if not _path_problem.is_empty():
		return _error(ERR_INVALID_PARAMETER, _path_problem)
	var loaded: Dictionary = _journal.read_all()
	if loaded.error == OK and not loaded.receipt.is_empty() and (loaded.receipt.root_id != _root_id or loaded.receipt.base.profile_id != _run_id):
		return _error(ERR_INVALID_DATA, "RUN_ROOT_MISMATCH")
	return loaded


func _append(receipt: Dictionary, expected: String) -> Dictionary:
	var written: Dictionary = _journal.append(receipt, expected)
	return _recover() if written.error == OK else written


func _inject(point: String) -> Error:
	return int(_fault.call(point)) as Error if _fault.is_valid() else OK


func _error(code: Error, reason: String) -> Dictionary:
	return {"error":code, "reason":reason, "state":"BLOCKED", "acknowledged":false, "receipt":{}}
