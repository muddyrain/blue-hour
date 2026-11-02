class_name SaveMigration
extends RefCounted
## One-time migration intent and retention proof; gameplay facts use the original journal only.

var _target: String
var _writer: ProgressWriter
var _fault: Callable


func _init(target: String, writer: ProgressWriter, fault: Callable = Callable()) -> void:
	_target = ProjectSettings.globalize_path(target).replace("\\", "/").simplify_path()
	_writer = writer
	_fault = fault


static func path_key(path: String) -> String:
	var normalized: String = ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	return (normalized.to_lower() if OS.has_feature("windows") else normalized).sha256_text()


static func preview(source: String, target: String, choice: String, writer: ProgressWriter) -> Dictionary:
	if writer == null or not writer.owns(target):
		return _blocked("MIGRATION_TARGET_WRITER_REQUIRED")
	var source_owner: ProgressWriter = ProgressWriter.new(source)
	if source_owner.acquire() != OK:
		return _blocked("SOURCE_WRITER_BUSY")
	var result: Dictionary = _source(source, target, choice, source_owner)
	source_owner.release()
	if result.error != OK:
		return result
	var existing: Dictionary = _read(target + ".migration/intent.json")
	if existing.error == OK:
		if not intent_problem(existing.payload, target).is_empty():
			return _blocked("MIGRATION_INTENT_DAMAGED")
		if not TransactionReceipt.same(existing.payload.source_manifest, result.manifest):
			return _blocked("SOURCE_CHANGED_OR_SELECTION_CONFLICT")
		var resume: String = _bootstrap_problem(target, existing.payload, writer)
		if not resume.is_empty():
			return _blocked(resume)
		return {"error":OK,"intent":existing.payload,"initial":existing.payload.initial,"resume":true,"completed":FileAccess.file_exists(target + ".migration/seal.json")}
	if existing.error != ERR_FILE_NOT_FOUND:
		return _blocked("MIGRATION_INTENT_DAMAGED")
	if FileAccess.file_exists(target) or FileAccess.file_exists(target + ".bak") or DirAccess.dir_exists_absolute(target + ".txn") or FileAccess.file_exists(target + ".txn") or FileAccess.file_exists(target + ".migration/seal.json"):
		return _blocked("TARGET_ALREADY_EXISTS")
	var meta: Dictionary = SurvivalState.initial()
	var identity: Dictionary = _identity(result.manifest, path_key(target))
	meta.root_id = identity.root_id
	var origin: Dictionary = {"policy_id":"V5_SAFE_MIGRATION_V1","migration_id":identity.migration_id,
		"source_path_key":path_key(source),"target_path_key":path_key(target),"source_choice":choice,
		"source_main_hash":result.manifest.main_hash,"source_backup_hash":result.manifest.backup_hash,
		"selected_hash":result.manifest.main_hash if choice == "MAIN" else result.manifest.backup_hash,
		"source_state_hash":SurvivalContracts.fingerprint(result.data),"source_settled_sorties":result.data.settled_sorties,
		"root_id":meta.root_id,"target_schema":SurvivalState.SCHEMA}
	var initial: Dictionary = SurvivalState.snapshot(result.data, meta, origin)
	var intent: Dictionary = {"format":"BH_MIGRATION_INTENT_V1","initial":initial,
		"source_manifest":result.manifest,"target_path_key":path_key(target)}
	var issue: String = intent_problem(intent, target)
	return {"error":OK,"intent":intent,"initial":initial,"resume":false} if issue.is_empty() else _blocked(issue)


func confirm(source: String, proposed: Dictionary) -> Dictionary:
	if _writer == null or not _writer.owns(_target) or not intent_problem(proposed, _target).is_empty():
		return _blocked("MIGRATION_IDENTITY_OR_WRITER")
	var source_owner: ProgressWriter = ProgressWriter.new(source)
	if source_owner.acquire() != OK:
		return _blocked("SOURCE_WRITER_BUSY")
	var result: Dictionary = _confirm_owned(source, proposed, source_owner)
	source_owner.release()
	return result


func _confirm_owned(source: String, intent: Dictionary, source_owner: ProgressWriter) -> Dictionary:
	var current: Dictionary = _source(source, _target, intent.initial.origin.source_choice, source_owner)
	if current.error != OK:
		return current
	if not TransactionReceipt.same(current.manifest, intent.source_manifest) or SurvivalContracts.fingerprint(current.data) != intent.initial.origin.source_state_hash:
		return _blocked("SOURCE_CHANGED_AFTER_PREVIEW")
	var directory: String = _target + ".migration"
	var prior: Dictionary = _read(directory + "/intent.json")
	if prior.error != ERR_FILE_NOT_FOUND and (prior.error != OK or not TransactionReceipt.same(prior.payload, intent)):
		return _blocked("MIGRATION_ID_CONFLICT")
	if prior.error == ERR_FILE_NOT_FOUND and (FileAccess.file_exists(_target) or FileAccess.file_exists(_target + ".bak") or DirAccess.dir_exists_absolute(_target + ".txn") or FileAccess.file_exists(_target + ".txn")):
		return _blocked("TARGET_ALREADY_EXISTS")
	if FileAccess.file_exists(directory + "/seal.json"):
		var sealed: String = _bootstrap_problem(_target, intent, _writer)
		return {"error":OK,"state":"MIGRATED"} if sealed.is_empty() else _blocked(sealed)
	var bootstrap: String = _bootstrap_problem(_target, intent, _writer)
	if not bootstrap.is_empty():
		return _blocked(bootstrap)
	var error: Error = _immutable(directory + "/intent.json", intent, "intent")
	if error != OK:
		return _blocked("MIGRATION_INTENT_WRITE", error)
	for suffix: String in ["", ".bak"]:
		var digest: String = intent.source_manifest.main_hash if suffix.is_empty() else intent.source_manifest.backup_hash
		if digest == "MISSING":
			continue
		error = _retain(source + suffix, directory + "/blobs/" + digest + ".json", digest)
		if error != OK:
			return _blocked("SOURCE_RETENTION_FAILED", error)
	current = _source(source, _target, intent.initial.origin.source_choice, source_owner)
	if current.error != OK or not TransactionReceipt.same(current.get("manifest", {}), intent.source_manifest):
		return _blocked("SOURCE_CHANGED_DURING_CONFIRMATION")
	if _call_fault("before_migration_target") != OK:
		return _blocked("MIGRATION_TARGET_WRITE")
	var save: RunSave = RunSave.new(_target, false, true)
	var disk: Dictionary = save.read_transaction_exact()
	if disk.error != OK:
		if disk.error != ERR_FILE_NOT_FOUND:
			return _blocked("MIGRATION_TARGET_DAMAGED")
		error = save.save(intent.initial, false, _writer, _call_fault)
		if error != OK:
			return _blocked("MIGRATION_TARGET_WRITE", error)
	elif not TransactionReceipt.same(disk.data, intent.initial):
		return _blocked("MIGRATION_TARGET_CONFLICT")
	if _call_fault("after_migration_target") != OK:
		return _blocked("MIGRATION_TARGET_UNCONFIRMED")
	disk = save.read_transaction_exact()
	if disk.error != OK or not TransactionReceipt.same(disk.data, intent.initial):
		return _blocked("MIGRATION_TARGET_READBACK")
	current = _source(source, _target, intent.initial.origin.source_choice, source_owner)
	if current.error != OK or not TransactionReceipt.same(current.get("manifest", {}), intent.source_manifest):
		return _blocked("SOURCE_CHANGED_BEFORE_REGISTRATION")
	var transaction: RunTransaction = RunTransaction.new(_target + ".txn/journal", _target,
		intent.initial.profile_id, intent.initial.journey.root_id, _call_fault, _writer)
	var registered: Dictionary = transaction.register(intent.initial)
	if registered.error != OK:
		return registered
	if _call_fault("after_migration_registration") != OK:
		return _blocked("MIGRATION_REGISTRATION_ACK_PENDING")
	current = _source(source, _target, intent.initial.origin.source_choice, source_owner)
	if current.error != OK or not TransactionReceipt.same(current.get("manifest", {}), intent.source_manifest):
		return _blocked("SOURCE_CHANGED_BEFORE_SEAL")
	var seal: Dictionary = {"format":"BH_MIGRATION_SEAL_V1","intent_hash":SurvivalContracts.fingerprint(intent),
		"run_id":intent.initial.profile_id,"root_id":intent.initial.journey.root_id,"registration_hash":registered.hash}
	error = _immutable(directory + "/seal.json", seal, "seal")
	if error != OK:
		return _blocked("MIGRATION_SEAL_WRITE", error)
	var issue: String = activation_problem(_target, intent.initial.origin)
	return {"error":OK,"state":"MIGRATED"} if issue.is_empty() else _blocked(issue)


static func activation_problem(target: String, origin: Dictionary) -> String:
	if origin.is_empty():
		return ""
	var intent: Dictionary = _read(target + ".migration/intent.json")
	var seal: Dictionary = _read(target + ".migration/seal.json")
	if intent.error != OK:
		return "MIGRATION_INTENT_MISSING_OR_DAMAGED"
	if seal.error != OK:
		return "MIGRATION_NOT_SEALED"
	var issue: String = intent_problem(intent.payload, target)
	if not issue.is_empty():
		return issue
	var proof: Dictionary = seal.payload
	if proof.size() != 5 or not proof.has_all(["format", "intent_hash", "run_id", "root_id", "registration_hash"]) or proof.format != "BH_MIGRATION_SEAL_V1" or proof.intent_hash != SurvivalContracts.fingerprint(intent.payload) or proof.run_id != intent.payload.initial.profile_id or proof.root_id != origin.root_id or not TransactionReceipt.same(origin, intent.payload.initial.origin):
		return "MIGRATION_SEAL_CONFLICT"
	var binding: Dictionary = _read(target + ".txn/binding.json")
	if binding.error != OK or binding.payload.get("root_hash") != proof.registration_hash:
		return "MIGRATION_REQUIRED_BINDING_MISSING"
	for digest: String in [origin.source_main_hash, origin.source_backup_hash]:
		if digest != "MISSING" and FileAccess.get_sha256(target + ".migration/blobs/" + digest + ".json") != digest:
			return "MIGRATION_RETAINED_SOURCE_DAMAGED"
	return ""


static func intent_problem(intent: Dictionary, target: String) -> String:
	if intent.size() != 4 or not intent.has_all(["format", "initial", "source_manifest", "target_path_key"]) or intent.format != "BH_MIGRATION_INTENT_V1" or not intent.initial is Dictionary or not intent.source_manifest is Dictionary or intent.target_path_key != path_key(target):
		return "MIGRATION_INTENT_FORMAT"
	var initial: Dictionary = intent.initial
	var issue: String = SurvivalState.problem(initial)
	if not issue.is_empty():
		return issue
	if initial.origin.is_empty() or not initial.journey.deaths.is_empty() or not TransactionReceipt.same({"ids":initial.journey.active_member_ids}, {"ids":[1, 2]}) or initial.settled_sorties != initial.origin.source_settled_sorties:
		return "MIGRATION_INITIAL_STATE"
	var origin: Dictionary = initial.origin
	var manifest: Dictionary = intent.source_manifest
	if manifest.size() != 4 or manifest.get("main_hash") != origin.source_main_hash or manifest.get("backup_hash") != origin.source_backup_hash or manifest.get("source_path_key") != origin.source_path_key or manifest.get("choice") != origin.source_choice or origin.target_path_key != intent.target_path_key:
		return "MIGRATION_SOURCE_MANIFEST"
	var identity: Dictionary = _identity(manifest, intent.target_path_key)
	if origin.migration_id != identity.migration_id or origin.root_id != identity.root_id:
		return "MIGRATION_DERIVED_IDENTITY_CONFLICT"
	return "" if SurvivalContracts.fingerprint(SurvivalState.legacy(initial)) == origin.source_state_hash else "MIGRATION_VALUE_MAPPING"


static func _identity(manifest: Dictionary, target_key: String) -> Dictionary:
	# Cold retry before intent publication must derive the same ID without writing during preview.
	var id: String = SurvivalContracts.fingerprint({"policy":"V5_SAFE_MIGRATION_V1","source":manifest,"target":target_key}).substr(0,32)
	return {"migration_id":id,"root_id":SurvivalContracts.fingerprint({"migration_id":id,"purpose":"BH_SURVIVAL_ROOT_V1"}).substr(0,32)}


static func _bootstrap_problem(target: String, intent: Dictionary, writer: ProgressWriter) -> String:
	if not ProgressWriter._unlinked(target + ".txn/journal") or not ProgressWriter._unlinked(target + ".migration"):
		return "MIGRATION_LINKED_TARGET_CONFLICT"
	if FileAccess.file_exists(target + ".migration/seal.json"):
		var active: Dictionary = RunSave.new(target, false, true).read_transaction_exact()
		if active.error != OK or not TransactionReceipt.same(active.data.origin, intent.initial.origin):
			return "MIGRATION_TARGET_OTHER_JOURNEY"
		var sealed: String = activation_problem(target, intent.initial.origin)
		if not sealed.is_empty():
			return sealed
		var owner: RunTransaction = RunTransaction.new(target + ".txn/journal", target,
			intent.initial.profile_id, intent.initial.journey.root_id, Callable(), writer)
		var state: Dictionary = owner.recover()
		var binding: Dictionary = _read(target + ".txn/binding.json")
		if state.error != OK or state.receipt.phase not in ["CAMP_REGISTERED", "EDIT_COMMITTED", "COMMITTED"] or state.hash != binding.payload.get("head_hash"):
			return "MIGRATION_TARGET_REQUIRES_OWNER"
		return ""
	for suffix: String in ["", ".bak"]:
		if DirAccess.dir_exists_absolute(target + suffix):
			return "MIGRATION_TARGET_CONFLICT"
		if FileAccess.file_exists(target + suffix):
			var saved: Dictionary = RunSave.new(target + suffix, false, true).read_transaction_exact()
			if saved.error != OK or not TransactionReceipt.same(saved.data, intent.initial):
				return "MIGRATION_TARGET_CONFLICT"
	var journal: ReceiptJournal = ReceiptJournal.new(target + ".txn/journal")
	var issue: String = journal.registration_problem(intent.initial, intent.initial.journey.root_id)
	if not issue.is_empty():
		return "MIGRATION_JOURNAL_CONFLICT:" + issue
	if FileAccess.file_exists(target + ".txn/binding.json"):
		var transaction: RunTransaction = RunTransaction.new(target + ".txn/journal", target,
			intent.initial.profile_id, intent.initial.journey.root_id, Callable(), writer)
		var current: Dictionary = transaction.recover()
		if current.error != OK or current.receipt.phase != "CAMP_REGISTERED" or not TransactionReceipt.same(current.receipt.base, intent.initial):
			return "MIGRATION_BINDING_CONFLICT"
	if FileAccess.file_exists(target + ".txn"):
		return "MIGRATION_BINDING_CONFLICT"
	if DirAccess.dir_exists_absolute(target + ".txn"):
		var directory: DirAccess = DirAccess.open(target + ".txn")
		if directory == null:
			return "MIGRATION_BINDING_UNREADABLE"
		for name: String in directory.get_files():
			if name == "binding.json":
				continue
			if not name.begins_with("binding.json.tmp-"):
				return "MIGRATION_BINDING_CONFLICT"
			var staged: Dictionary = _read(target + ".txn/" + name)
			var chain: Dictionary = journal.read_all()
			if staged.error != OK or chain.error != OK or staged.payload.size() != 7 or staged.payload.get("binding_version") != 1 or staged.payload.get("revision") != 1 or staged.payload.get("journal") != journal.directory or staged.payload.get("root_hash") != chain.get("hashes", {}).get(1) or staged.payload.get("head_hash") != chain.get("hashes", {}).get(1) or staged.payload.get("run_id") != intent.initial.profile_id or staged.payload.get("root_id") != intent.initial.journey.root_id:
				return "MIGRATION_BINDING_STAGE_CONFLICT"
	return ""


static func _source(source: String, target: String, choice: String, owner: ProgressWriter) -> Dictionary:
	if not source.is_absolute_path() or not target.is_absolute_path() or choice not in ["MAIN", "BACKUP"] or path_key(source) == path_key(target) or path_key(source + ".bak") == path_key(target) or not ProgressWriter._unlinked(source + ".bak") or not ProgressWriter._unlinked(target + ".migration") or target.replace("\\", "/").get_file().to_lower() != "run.survival-v1.json":
		return _blocked("MIGRATION_EXPLICIT_PATHS_REQUIRED")
	if DirAccess.dir_exists_absolute(source) or DirAccess.dir_exists_absolute(source + ".bak"):
		return _blocked("SOURCE_PATH_IS_DIRECTORY")
	var selected: String = source + (".bak" if choice == "BACKUP" else "")
	var value: Dictionary = RunSave.new(selected).read_v5_exact()
	if value.error != OK or value.get("data", {}).get("schema_version") != 5:
		return _blocked("SOURCE_NOT_VALID_V5")
	for member: Dictionary in value.data.crew:
		if member.health <= 0:
			return _blocked("SOURCE_ZERO_HP_REQUIRES_POLICY")
	if RunSave.transaction_namespace(source) or DirAccess.dir_exists_absolute(source + ".txn") or FileAccess.file_exists(source + ".txn"):
		var bound: Dictionary = _read(source + ".txn/binding.json")
		if bound.error != OK or not bound.payload.get("root_id") is String:
			return _blocked("SOURCE_REQUIRED_BINDING_MISSING")
		var transaction: RunTransaction = RunTransaction.new(source + ".txn/journal", source,
			value.data.profile_id, bound.payload.root_id, Callable(), owner)
		var current: Dictionary = transaction.recover()
		if current.error != OK or current.receipt.phase not in ["CAMP_REGISTERED", "EDIT_COMMITTED", "COMMITTED"] or current.hash != bound.payload.get("head_hash"):
			return _blocked("SOURCE_TRANSACTION_REQUIRES_OWNER")
		if not TransactionReceipt.same(TransactionReceipt.camp(current.receipt), value.data):
			return _blocked("SOURCE_NOT_CONFIRMED_CAMP")
	var main_hash: String = FileAccess.get_sha256(source) if FileAccess.file_exists(source) else "MISSING"
	var backup_hash: String = FileAccess.get_sha256(source + ".bak") if FileAccess.file_exists(source + ".bak") else "MISSING"
	if main_hash.is_empty() or backup_hash.is_empty():
		return _blocked("SOURCE_UNREADABLE")
	return {"error":OK,"data":value.data,"manifest":{"main_hash":main_hash,"backup_hash":backup_hash,"source_path_key":path_key(source),"choice":choice}}


func _retain(source: String, target: String, digest: String) -> Error:
	if FileAccess.file_exists(target):
		return OK if FileAccess.get_sha256(target) == digest else ERR_FILE_CORRUPT
	if _call_fault("before_source_copy") != OK:
		return ERR_CANT_CREATE
	var error: Error = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error != OK:
		return error
	var stage: String = target + ".stage-" + RunSave.new_profile_id()
	error = DirAccess.copy_absolute(source, stage)
	if error != OK or FileAccess.get_sha256(stage) != digest:
		return ERR_FILE_CORRUPT
	if _call_fault("after_source_copy_stage") != OK:
		return ERR_CANT_CREATE
	error = DirAccess.rename_absolute(stage, target)
	return _call_fault("after_source_copy_publish") if error == OK else error


func _immutable(path: String, payload: Dictionary, kind: String) -> Error:
	var existing: Dictionary = _read(path)
	if existing.error != ERR_FILE_NOT_FOUND:
		return OK if existing.error == OK and TransactionReceipt.same(existing.payload, payload) else ERR_FILE_CORRUPT
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK or _call_fault("before_" + kind + "_write") != OK:
		return ERR_CANT_CREATE
	var stage: String = path + ".stage-" + RunSave.new_profile_id()
	var file: FileAccess = FileAccess.open(stage, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"payload":payload,"sha256":SurvivalContracts.fingerprint(payload)}, "", true, true) + "\n")
	file.flush()
	file.close()
	var checked: Dictionary = _read(stage)
	if checked.error != OK or not TransactionReceipt.same(checked.payload, payload):
		return ERR_FILE_CORRUPT
	if _call_fault("after_" + kind + "_stage") != OK:
		return ERR_CANT_CREATE
	error = DirAccess.rename_absolute(stage, path)
	return _call_fault("after_" + kind + "_publish") if error == OK else error


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error":ERR_FILE_NOT_FOUND,"payload":{}}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0 or file.get_length() > RunSave.MAX_BYTES:
		return {"error":ERR_FILE_CORRUPT,"payload":{}}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var text: String = bytes.get_string_from_utf8()
	var parser: JSON = JSON.new()
	if text.to_utf8_buffer() != bytes or parser.parse(text) != OK or not parser.data is Dictionary:
		return {"error":ERR_FILE_CORRUPT,"payload":{}}
	var data: Dictionary = parser.data
	if data.size() != 2 or not data.get("payload") is Dictionary or data.get("sha256") != SurvivalContracts.fingerprint(data.payload):
		return {"error":ERR_FILE_CORRUPT,"payload":{}}
	return {"error":OK,"payload":data.payload}


func _call_fault(point: String) -> Error:
	return int(_fault.call(point)) as Error if _fault.is_valid() else OK


static func _blocked(reason: String, error: Error = ERR_UNAVAILABLE) -> Dictionary:
	return {"error":error,"state":"MIGRATION_BLOCKED","reason":reason,"camp":{}}
