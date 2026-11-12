class_name ProductionProgress
extends RefCounted
## Explicit sandbox wiring through main. The reserved path remains gated when sidecars disappear.

var daily_actions: bool = false
var fault_hook: Callable
var token: Dictionary = {}
var packet: Dictionary = {}
var battle_mode: bool = false
var survival_mode: bool = false
var rescue_mode: bool = false
var growth_mode: bool = false
var field_join_mode: bool = false
var trait_mode: bool = false
var training_mode: bool = false
var pool_mode: bool = false
var roster_mode: bool = false
var enemy_mode: bool = false
var quality_mode: bool = false
var hunger_trial: bool = false
var suspend_enabled: bool = false
var _path: String
var _writer: ProgressWriter
var _transaction: RunTransaction
var _problem: String = ""
var _pending_base: Dictionary = {}
var _new_root: String = ""
var _archived: bool = false
var _archive_specialty: String = ""
var _expected: String = ""
var _active_base: Dictionary = {}
var _active_rules: Dictionary = {}
var _pending_edit: String = ""
var _pending_edit_head: String = ""
var _pending_edit_request: Dictionary = {}
var _suspend_generation: String = ""
var _catalog_store: CatalogProgress
var _catalog_state: Dictionary = {}


func _init(save_path: String, battle: bool = false, survival: bool = false, hunger: bool = false, rescue: bool = false, growth: bool = false, field: bool = false, traits: bool = false, training: bool = false, pool: bool = false, roster: bool = false, quality: bool = false, enemy: bool = false, playable: bool = false) -> void:
	daily_actions = playable
	enemy_mode = enemy
	quality_mode = quality or enemy
	roster_mode = roster or quality_mode
	pool_mode = pool or roster_mode
	training_mode = training or pool_mode
	trait_mode = traits or training_mode
	field_join_mode = field or trait_mode
	growth = growth or field_join_mode
	rescue_mode = rescue or growth
	growth_mode = growth
	if growth and not (survival and hunger):
		_problem = "GROWTH_ISOLATED_SURVIVAL_REQUIRED"
		return
	survival_mode = survival
	hunger_trial = hunger
	battle_mode = battle or survival
	if hunger_trial and not survival_mode:
		_problem = "HUNGER_ISOLATED_SURVIVAL_REQUIRED"
		return
	_path = ProjectSettings.globalize_path(save_path).replace("\\", "/").simplify_path()
	var user_path: String = OS.get_user_data_dir().replace("\\", "/").to_lower()
	# An exported build has a different res:// root. Require explicit isolated storage instead.
	var required: String = "run.battle-v1.json" if battle_mode else "run.txn-v1.json"
	if survival_mode:
		required = "run.survival-v1.json"
	if rescue_mode:
		required = "run.rescue-v1.json"
	if growth_mode:
		required = "run.growth-v1.json"
	if field_join_mode:
		required = "run.field-join-v1.json"
	if trait_mode:
		required = "run.trait-v1.json"
	if training_mode:
		required = "run.enemy-v1.json" if enemy_mode else "run.weapon-quality-v1.json" if quality_mode else "run.roster-v1.json" if roster_mode else "run.rescue-pool-v1.json" if pool_mode else "run.training-v1.json"
	var dedicated_playable: bool = playable and enemy_mode and survival_mode and hunger_trial and PlayableEntry.owns_path(_path)
	var isolated_test: bool = save_path.is_absolute_path() and _path.get_file().to_lower()==required and "/.local/" in _path.to_lower() and "/.local/" in user_path and user_path.get_slice("/.local/",0)==_path.to_lower().get_slice("/.local/",0)
	if not dedicated_playable and not isolated_test:
		_problem = "EXPLICIT_ISOLATED_TRANSACTION_PATH_REQUIRED"
		return
	_writer = ProgressWriter.new(_path)
	if _writer.acquire() != OK:
		_problem = _writer.reason
	_expected = _disk_identity()
	if playable:
		_catalog_store = CatalogProgress.new(_path)


func close() -> void:
	if _writer != null:
		_writer.release()


func catalog_state() -> Dictionary:
	return _catalog_state.duplicate(true)


func refresh_catalog() -> Dictionary:
	if _catalog_store == null or _writer == null or not _writer.owns(_path):
		_catalog_state = {"error":ERR_UNAVAILABLE, "reason":"CATALOG_WRITER_UNAVAILABLE"}
	else:
		_catalog_state = _catalog_store.refresh(_fault)
	return catalog_state()


func death_equipment(camp: Dictionary) -> Dictionary:
	# Read-only view of the original retained receipts, never infer from a starter gun.
	var result: Dictionary = {}
	if _transaction==null or not TransactionReceipt.camp_problem(camp).is_empty():
		return result
	var journal: ReceiptJournal = _transaction._journal
	if journal.read_all().error!=OK:
		return result
	for folder: String in DirAccess.get_directories_at(journal.directory):
		if folder.begins_with(".stage-"): continue
		var row: Dictionary = journal._read_record(journal.directory.path_join(folder).path_join("record.json"))
		if row.error!=OK: return {}
		var receipt: Dictionary = row.receipt
		for death: Dictionary in camp.journey.deaths:
			if receipt.transaction_id!=death.transaction_id: continue
			var context: Dictionary = FieldJoinRules.context(receipt) if FieldJoinState.is_family(receipt.base) else receipt.base
			var item: Dictionary = WeaponInventory.for_member(context,int(death.member_id))
			if not item.is_empty():
				result[int(death.member_id)] = {"instance_id":item.instance_id,"weapon_id":item.weapon_id,"transaction_id":death.transaction_id}
	return result


func inspect() -> Dictionary:
	if not _problem.is_empty():
		return _blocked(_problem)
	if not _writer.owns(_path):
		return _blocked("SESSION_WRITER_LOST")
	var has_camp: bool = FileAccess.file_exists(_path) or FileAccess.file_exists(_path+".bak")
	var has_marker: bool = DirAccess.dir_exists_absolute(_path+".txn") or FileAccess.file_exists(_path+".txn")
	if not has_camp and not has_marker:
		if DirAccess.dir_exists_absolute(_path + ".migration") or FileAccess.file_exists(_path + ".migration"):
			return _blocked("MIGRATION_REQUIRED_TARGET_MISSING")
		return {"error":OK,"state":"EMPTY","camp":{},"reason":"NEW_JOURNEY_CONFIRMATION_REQUIRED"}
	var parsed: JSON = JSON.new()
	var binding_path: String = _path+".txn/binding.json"
	if not FileAccess.file_exists(binding_path) or parsed.parse(FileAccess.get_file_as_string(binding_path)) != OK or not parsed.data is Dictionary or not parsed.data.get("payload") is Dictionary:
		return _blocked("REQUIRED_BINDING_MISSING_OR_DAMAGED")
	var binding: Dictionary = parsed.data.payload
	if not binding.get("run_id") is String or not binding.get("root_id") is String:
		return _blocked("BINDING_IDENTITY")
	_transaction = RunTransaction.new(_path+".txn/journal",_path,binding.run_id,binding.root_id,_fault,_writer)
	var recovered: Dictionary = _transaction.recover()
	if recovered.error != OK:
		return recovered
	var receipt: Dictionary = recovered.receipt
	if SurvivalState.is_extended(receipt.base) != battle_mode or SurvivalState.is_survival(receipt.base) != survival_mode or RescueState.is_family(receipt.base) != rescue_mode or GrowthState.is_family(receipt.base) != growth_mode or FieldJoinState.is_family(receipt.base) != field_join_mode or TraitState.is_family(receipt.base) != trait_mode or TrainingState.is_family(receipt.base) != training_mode or RescuePoolState.is_family(receipt.base) != pool_mode or RosterState.is_family(receipt.base) != roster_mode or WeaponState.is_family(receipt.base) != quality_mode or EnemyState.is_state(receipt.base) != enemy_mode:
		return _blocked("UNSUPPORTED_PROGRESS_FORMAT")
	if survival_mode:
		var migrated: String = SaveMigration.activation_problem(_path, TransactionReceipt.camp(receipt).get("origin", receipt.base.origin))
		if not migrated.is_empty():
			return _blocked(migrated)
	if receipt.phase == "SUSPEND_READY":
		if not suspend_enabled:
			return _blocked("SUSPEND_EXPLICIT_ENTRY_REQUIRED")
		return {"error":OK,"state":"SUSPENDED","receipt":receipt,"hash":recovered.hash,"camp":{},"reason":"SUSPEND_READY"}
	if receipt.phase in ["STARTED","IN_PROGRESS","DEATH_CONFIRMED","RESUME_CLAIMED"]:
		var blocked: Dictionary = _blocked("UNFINISHED_ACTION_POLICY_REQUIRED:"+receipt.phase)
		blocked.confirmed_deaths = receipt.deaths.duplicate(true)
		return blocked
	var scope: String = FrozenSettlement.BATTLE if battle_mode else FrozenSettlement.FOUNDATION
	if survival_mode:
		scope = FrozenSettlement.SURVIVAL
		var has_starvation: bool = receipt.base.journey.deaths.any(func(death: Dictionary) -> bool: return death.cause == "STARVATION")
		if receipt.phase in ["RESULT_READY","COMMITTED"] and receipt.envelope.result.get("scope") == FrozenSettlement.HUNGER_PILOT:
			has_starvation = true
			if hunger_trial:
				scope = FrozenSettlement.HUNGER_PILOT
		if has_starvation and not hunger_trial:
			return _blocked("HUNGER_EXPLICIT_TRIAL_REQUIRED")
	if rescue_mode:
		scope = RescueState.SCOPE
	if growth_mode:
		scope = RescuePoolState.SCOPE if pool_mode else TraitState.SCOPE if trait_mode else FieldJoinState.SCOPE if field_join_mode else GrowthState.SCOPE
	if receipt.phase in ["RESULT_READY","COMMITTED"] and receipt.envelope.result.get("scope") != scope:
		return _blocked("UNSUPPORTED_RESULT_SCOPE")
	var ready: bool = receipt.phase in ["RESULT_READY","EDIT_READY"]
	if not ready and not battle_mode:
		for member: Dictionary in TransactionReceipt.camp(receipt).crew:
			if member.health <= 0:
				return _blocked("LEGACY_ZERO_HP_NOT_ENROLLED")
	var camp: Dictionary = TransactionReceipt.camp(receipt).duplicate(true)
	return {"error":OK,"state":"RECOVERY_READY" if ready else ("ENDED" if battle_mode and (camp.journey.state == "FAILED" or CampaignState.ended(camp)) else "CAMP"),"camp":camp,
		"receipt":receipt,"hash":recovered.hash,"reason":recovered.state}


func activate() -> Dictionary:
	var state: Dictionary = inspect()
	if state.error != OK or state.state == "EMPTY":
		return state
	if state.receipt.phase in ["RESULT_READY","COMMITTED","EDIT_READY","EDIT_COMMITTED"]:
		var result: Dictionary = _transaction.commit_edit(state.receipt.transaction_id) if state.receipt.phase in ["EDIT_READY","EDIT_COMMITTED"] else _transaction.commit(RunTransaction.token_for(state.receipt))
		if result.error != OK:
			return result
	var confirmed: Dictionary = inspect()
	if confirmed.error == OK:
		_expected = _disk_identity()
		if _catalog_store != null:
			var catalog: Dictionary = refresh_catalog()
			if catalog.error != OK:
				return _catalog_pending(confirmed, catalog)
	return confirmed


func create(base: Dictionary) -> Dictionary:
	if not _problem.is_empty():
		return _blocked(_problem)
	if not TransactionReceipt.camp_problem(base).is_empty() or base.settled_sorties != 0 or SurvivalState.is_extended(base) != battle_mode or SurvivalState.is_survival(base) != survival_mode or RescueState.is_family(base) != rescue_mode or GrowthState.is_family(base) != growth_mode or FieldJoinState.is_family(base) != field_join_mode or TraitState.is_family(base) != trait_mode or TrainingState.is_family(base) != training_mode or RescuePoolState.is_family(base) != pool_mode or RosterState.is_family(base) != roster_mode or WeaponState.is_family(base) != quality_mode or EnemyState.is_state(base) != enemy_mode:
		return _blocked("NEW_BASE_FORMAT")
	var opening_issue: String = OpeningBuild.registration_problem(base)
	if not opening_issue.is_empty():
		return _blocked(opening_issue)
	if _pending_base.is_empty():
		if _expected != _disk_identity():
			return _blocked("NEW_JOURNEY_DISK_CHANGED")
		var catalog_policy: Dictionary = base.get("journey", {}).get("build", {}).get("catalog", {})
		if _catalog_store != null or not catalog_policy.is_empty():
			var catalog: Dictionary = refresh_catalog()
			if catalog.error != OK:
				return _blocked(catalog.reason)
			if not catalog_policy.is_empty() and catalog_policy.unlock != catalog.unlock_hash:
				return _blocked("CATALOG_NEW_RUN_POLICY")
			if OpeningBuild.is_m47(base) and (base.journey.campaign.open_streets_policy != OpenStreetsV1.VERSION \
					or OpeningBuild.eligible(base) != CatalogProgress.eligible_for(catalog, OpeningBuild.plan(base))):
				return _blocked("CATALOG_NEW_SPECIALTY_POLICY")
			_archive_specialty = catalog.m47_run_id
		_pending_base = base.duplicate(true)
		_new_root = base.journey.root_id if battle_mode else RunSave.new_profile_id()
	elif not TransactionReceipt.same(_pending_base,base):
		return _blocked("RETRY_SAME_CONFIRMED_BASE_REQUIRED")
	if _fault("before_foundation_write") != OK:
		return _blocked("FIRST_BASE_WRITE_FAILED")
	# The live .bak rotates again on the next edit. Preserve the old main independently.
	if not _archived and FileAccess.file_exists(_path):
		var archive_path: String = _path+".previous-"+RunSave.new_profile_id()
		if DirAccess.copy_absolute(_path,archive_path) != OK or FileAccess.get_sha256(archive_path) != FileAccess.get_sha256(_path):
			return _blocked("OLD_CAMP_ARCHIVE_FAILED")
	if not _archived and (DirAccess.dir_exists_absolute(_path+".txn") or FileAccess.file_exists(_path+".txn")):
		var archive: String = _path + ".txn.previous-" + RunSave.new_profile_id() if _archive_specialty.is_empty() \
			else _path + SpecializationProgress.ARCHIVE_PREFIX + _archive_specialty
		if FileAccess.file_exists(archive) or DirAccess.dir_exists_absolute(archive) or DirAccess.rename_absolute(_path+".txn", archive) != OK:
			return _blocked("OLD_JOURNAL_ARCHIVE_FAILED")
	if not _archived and (FileAccess.file_exists(_path+".bak") or DirAccess.dir_exists_absolute(_path+".bak")):
		if DirAccess.rename_absolute(_path+".bak",_path+".bak.previous-"+RunSave.new_profile_id()) != OK:
			return _blocked("OLD_BACKUP_ARCHIVE_FAILED")
	if not _archived and survival_mode and (FileAccess.file_exists(_path+".migration") or DirAccess.dir_exists_absolute(_path+".migration")):
		if DirAccess.rename_absolute(_path+".migration",_path+".migration.previous-"+RunSave.new_profile_id()) != OK:
			return _blocked("OLD_MIGRATION_ARCHIVE_FAILED")
	_archived = true
	var save: RunSave = RunSave.new(_path,battle_mode and not survival_mode,survival_mode and not rescue_mode,rescue_mode and not growth_mode,growth_mode and not field_join_mode,field_join_mode and not trait_mode,trait_mode and not training_mode,training_mode and not pool_mode,pool_mode and not roster_mode,roster_mode and not quality_mode,quality_mode and not enemy_mode,enemy_mode)
	var disk: Dictionary = save.read_transaction_exact()
	if disk.error != OK or not TransactionReceipt.same(disk.data,base):
		var error: Error = save.save(base,true,_writer)
		if error != OK:
			return _blocked("FIRST_BASE_WRITE_FAILED:"+save.diagnostic)
	if _fault("after_foundation_write") != OK:
		return _blocked("BASE_WRITTEN_REGISTRATION_PENDING")
	_transaction = RunTransaction.new(_path+".txn/journal",_path,base.profile_id,_new_root,_fault,_writer)
	var registered: Dictionary = _transaction.register(base)
	if registered.error != OK:
		return registered
	_pending_base = {}
	token = {}
	packet = {}
	_active_base = {}
	_active_rules = {}
	_pending_edit = ""
	_pending_edit_head = ""
	_pending_edit_request = {}
	_new_root = ""
	_archived = false
	_archive_specialty = ""
	_expected = _disk_identity()
	return inspect()


func edit(before: Dictionary, request: Dictionary) -> Dictionary:
	var state: Dictionary = inspect()
	if state.error != OK or state.state != "CAMP" or not TransactionReceipt.same(state.camp,before):
		return _blocked("STALE_CAMP_EDIT")
	if not _pending_edit.is_empty():
		return _blocked("PENDING_EDIT_RETRY_REQUIRED")
	var proposal: Dictionary = CampEdit.propose(before,request)
	if proposal.is_empty():
		return {"error":ERR_INVALID_PARAMETER,"state":"BUSINESS_REJECTED","reason":"EDIT_NOT_AVAILABLE",
			"message":"训练未执行：旧预览可能已失效，请重新选择成员、查看粮食和等级，再明确确认。" if request.get("kind") is String and request.kind=="train_trait" else "操作未执行：请检查货币、装备状态或呼号。","camp":before.duplicate(true)}
	if TransactionReceipt.same(proposal,before):
		return state
	_pending_edit = TrainingRules.intent_for(request).edit_id if request.kind=="train_trait" else String(before.profile_id)+":edit:"+RunSave.new_profile_id()
	if request.kind == "economy":
		var intent: Variant = JSON.parse_string(request.value)
		_pending_edit = String(intent.edit_id)
	_pending_edit_head = state.hash
	_pending_edit_request = request.duplicate(true)
	return _retry_edit()


func preview_migration(source: String, choice: String) -> Dictionary:
	if not survival_mode or not _problem.is_empty() or _writer == null or not _writer.owns(_path):
		return _blocked("MIGRATION_ISOLATED_WRITER_REQUIRED")
	return SaveMigration.preview(source, _path, choice, _writer)


func migrate(source: String, intent: Dictionary) -> Dictionary:
	if not survival_mode or not _problem.is_empty() or _writer == null or not _writer.owns(_path):
		return _blocked("MIGRATION_ISOLATED_WRITER_REQUIRED")
	var migration: SaveMigration = SaveMigration.new(_path, _writer, _fault)
	var result: Dictionary = migration.confirm(source, intent)
	# A failed attempt may have retained an intent. A separate, confirmed new journey can archive it.
	_expected = _disk_identity()
	if result.error != OK:
		return result
	return inspect()


func _retry_edit() -> Dictionary:
	var ready: Dictionary = _transaction.prepare_edit(_pending_edit_head,_pending_edit,_pending_edit_request)
	if ready.error != OK:
		return ready
	var result: Dictionary = _transaction.commit_edit(_pending_edit)
	if result.error != OK:
		return result
	_pending_edit = ""
	_pending_edit_head = ""
	_pending_edit_request = {}
	_expected = _disk_identity()
	return inspect()


func begin(before: Dictionary, supply: MissionSupply) -> Dictionary:
	if CampaignState.ended(before): return _blocked("CAMPAIGN_ALREADY_ENDED")
	var state: Dictionary = inspect()
	if state.error != OK or state.state != "CAMP" or not TransactionReceipt.same(state.camp,before):
		return _blocked("CAMP_NOT_CONFIRMED")
	for member: Dictionary in before.crew:
		if member.health <= 0 and not battle_mode:
			return _blocked("LEGACY_ZERO_HP_NOT_ENROLLED")
	if daily_actions and (supply==null or not DailyActions.matches(before,supply.generated)):
		return _blocked("DAILY_SELECTION_NOT_CURRENT")
	_active_base = before.duplicate(true)
	_active_rules = FrozenSettlement.battle_rules(supply) if battle_mode else FrozenSettlement.foundation_rules(supply)
	if survival_mode:
		_active_rules = FrozenSettlement.survival_hunger_rules(supply) if hunger_trial else FrozenSettlement.survival_rules(supply)
	if rescue_mode:
		_active_rules = FrozenSettlement.rescue_rules(supply)
	if growth_mode:
		_active_rules = FrozenSettlement.trait_rules(supply) if trait_mode else FrozenSettlement.field_join_rules(supply) if field_join_mode else FrozenSettlement.growth_rules(supply)
	if pool_mode:
		_active_rules = FrozenSettlement.pool_rules(before,supply)
	var started: Dictionary = _transaction.begin(before,"%s:%d" % [before.profile_id,int(before.settled_sorties)+1],_active_rules)
	if started.error == OK:
		token = started.token.duplicate(true)
		packet = {}
	return started


func active_supply() -> MissionSupply:
	return DailyActions.supply(_active_rules.mission.generated) if (_active_rules.get("data_version")==2 or _active_rules.get("data_version")==3 or _active_rules.get("data_version")==4 or (_active_rules.get("data_version")==5 or (_active_rules.get("data_version")==6 or (_active_rules.get("data_version")==7 or (_active_rules.get("data_version")==8 or (_active_rules.get("data_version")==9 or _active_rules.get("data_version")==10)))))) else null


func join_field(at_ms: int) -> Dictionary:
	if not field_join_mode or _transaction == null or token.is_empty():
		return _blocked("FIELD_JOIN_ENTRY_REQUIRED")
	return _transaction.join_field(token,FieldJoinRules.event(_active_base,token.transaction_id,at_ms))


func damage_gate(actor: FieldActor) -> PersistedDamageGate:
	return PersistedDamageGate.new(_transaction,token,actor)


func suspend_world(world: Dictionary) -> Dictionary:
	if not suspend_enabled or not survival_mode or _transaction == null or token.is_empty():
		return _blocked("SUSPEND_EXPLICIT_ENTRY_REQUIRED")
	# Freeze the intended publication before I/O, including an unknown publication ACK.
	var preview: Dictionary = _transaction.preview_suspend(token,world)
	if preview.error != OK:
		return preview
	_suspend_generation = preview.suspend_generation
	return _transaction.suspend(token,world)


func preview_suspend(world: Dictionary) -> Dictionary:
	if not suspend_enabled or not survival_mode or _transaction == null or token.is_empty() or world.is_empty():
		return _blocked("SUSPEND_STATE_OR_ENTRY_UNAVAILABLE")
	if not _writer.owns(_path):
		return _blocked("SESSION_WRITER_LOST")
	return _transaction.preview_suspend(token,world)


func resume_offer() -> Dictionary:
	var state: Dictionary = inspect()
	if state.error != OK or state.state != "SUSPENDED":
		return _blocked(state.get("reason","NO_SUSPEND_READY"))
	var receipt: Dictionary = state.receipt
	if daily_actions and receipt.rules.get("data_version")!=4 and receipt.rules.get("data_version")!=5 and (receipt.rules.get("data_version")!=6 and (receipt.rules.get("data_version")!=7 and (receipt.rules.get("data_version")!=8 and (receipt.rules.get("data_version")!=9 and receipt.rules.get("data_version")!=10)))):
		return _blocked("WORLD_DAILY_BUILD_MISMATCH")
	if SortieSnapshot.old_outdoor(receipt.envelope.world):
		return _blocked("WORLD_OUTDOOR_BUILD_MISMATCH")
	if receipt.envelope.world.hunger != hunger_trial:
		return _blocked("SUSPEND_HUNGER_ENTRY_MISMATCH")
	_active_base = receipt.base.duplicate(true)
	_active_rules = receipt.rules.duplicate(true)
	token = RunTransaction.token_for(receipt)
	_suspend_generation = receipt.envelope.previous_head
	return state


func claim_world(world_hash: String) -> Dictionary:
	if not suspend_enabled or _transaction == null or token.is_empty():
		return _blocked("SUSPEND_EXPLICIT_ENTRY_REQUIRED")
	return _transaction.claim_suspend(token,world_hash,_suspend_generation)


func release_frozen_world(world_hash: String) -> Dictionary:
	if _transaction == null:
		return _blocked("NO_ACTIVE_TRANSACTION")
	var state: Dictionary = _transaction.recover()
	if state.error != OK:
		return state
	if state.receipt.phase in ["SUSPEND_READY","RESUME_CLAIMED"]:
		return claim_world(world_hash)
	return _transaction.validate_action(token)


func finish(report: Dictionary, carried: Dictionary) -> Dictionary:
	var stamp: int = FreezeProfile.enter("progress.finish")
	var result: Dictionary = _profiled_finish(report,carried)
	FreezeProfile.leave("progress.finish", stamp)
	return result


func _profiled_finish(report: Dictionary, carried: Dictionary) -> Dictionary:
	if _transaction == null or token.is_empty():
		return _blocked("NO_ACTIVE_TRANSACTION")
	var input: Dictionary = {"before":_active_base.duplicate(true),"token":token.duplicate(true),
		"participants":SurvivalContracts.participants(_active_base.crew,WeaponInventory.snapshot(_active_base),true,growth_mode),
		"rules":_active_rules.duplicate(true),"report":report.duplicate(true),"carried":carried.duplicate(true),
		"prior_deaths":_active_base.journey.deaths.duplicate(true) if battle_mode else [],"completion":"COMPLETED","searching_member_ids":[]}
	var computed: Dictionary = FrozenSettlement.compute(input)
	if not computed.error.is_empty():
		return _blocked(computed.reason)
	packet = computed.packet
	var ready: Dictionary = _prepare_packet()
	if ready.error != OK:
		ready.retry_packet = true
		return ready
	return {"error":OK,"state":"RESULT_READY","camp":packet.envelope.result.camp.duplicate(true)}


func commit_result() -> Dictionary:
	if _transaction == null or token.is_empty():
		return _blocked("NO_FROZEN_RESULT")
	var result: Dictionary = _transaction.commit(token)
	if result.error != OK:
		return result
	_expected = _disk_identity()
	var committed: Dictionary = inspect()
	if committed.error == OK and _catalog_store != null:
		var catalog: Dictionary = refresh_catalog()
		if catalog.error != OK:
			return _catalog_pending(committed, catalog)
	return committed


func _catalog_pending(confirmed: Dictionary, catalog: Dictionary) -> Dictionary:
	# The original ACK remains authoritative. A failed projection cannot turn it
	# into a second settlement or grant unverified new-journey qualifications.
	var result: Dictionary = confirmed.duplicate(true)
	result.error = catalog.error
	result.state = "CATALOG_PENDING"
	result.camp_saved = true
	result.reason = "CATALOG_SYNC:" + String(catalog.get("reason", "UNKNOWN"))
	return result


func retry() -> Dictionary:
	if not _pending_base.is_empty():
		return create(_pending_base)
	if not _pending_edit.is_empty():
		return _retry_edit()
	if not packet.is_empty() and _transaction != null:
		var current: Dictionary = _transaction.recover()
		if current.error != OK:
			return current
		if current.receipt.phase in ["STARTED","IN_PROGRESS","DEATH_CONFIRMED","RESULT_READY"]:
			var ready: Dictionary = _prepare_packet()
			if ready.error != OK:
				return ready
			return commit_result()
	var state: Dictionary = activate()
	if state.error == OK:
		_expected = _disk_identity()
	return state


func _prepare_packet() -> Dictionary:
	if pool_mode:
		return FrozenSettlement.prepare_pool(_transaction,packet)
	if trait_mode:
		return FrozenSettlement.prepare_traits(_transaction,packet)
	if field_join_mode:
		return FrozenSettlement.prepare_field_join(_transaction,packet)
	if growth_mode:
		return FrozenSettlement.prepare_growth(_transaction,packet)
	if rescue_mode:
		return FrozenSettlement.prepare_rescue(_transaction,packet)
	if survival_mode:
		return FrozenSettlement.prepare_survival_hunger(_transaction,packet) if hunger_trial else FrozenSettlement.prepare_survival(_transaction,packet)
	return FrozenSettlement.prepare_battle(_transaction,packet) if battle_mode else FrozenSettlement.prepare_foundation(_transaction,packet)


func _disk_identity() -> String:
	var values: Dictionary = {}
	for suffix: String in ["",".bak",".txn/binding.json", ".migration/intent.json", ".migration/seal.json"]:
		values[suffix] = FileAccess.get_sha256(_path+suffix) if FileAccess.file_exists(_path+suffix) else "MISSING"
	return SurvivalContracts.fingerprint(values)


func _fault(point: String) -> Error:
	return int(fault_hook.call(point)) as Error if fault_hook.is_valid() else OK


func _blocked(reason: String) -> Dictionary:
	return {"error":ERR_UNAVAILABLE,"state":"BLOCKED","reason":reason,"camp":{}}

func accept_support(before: Dictionary, request: Dictionary) -> Dictionary:
	if not suspend_enabled or _transaction==null or token.is_empty() or (_active_rules.get("data_version")!=8 and (_active_rules.get("data_version")!=9 and _active_rules.get("data_version")!=10)): return _blocked("SUPPORT_MODE_REQUIRED")
	var accepted: Dictionary=_transaction.accept_support(token,before,request)
	if accepted.error!=OK: return accepted
	var receipt: Dictionary=accepted.receipt
	var world: Dictionary=receipt.envelope.world.duplicate(true)
	if receipt.phase=="SUSPEND_READY":
		accepted=_transaction.claim_suspend(token,receipt.envelope.world_hash,receipt.envelope.previous_head)
		if accepted.error!=OK: return accepted
	elif receipt.phase!="RESUME_CLAIMED": return _blocked("SUPPORT_ACK_PHASE")
	accepted.world=world
	return accepted

func accept_power(before: Dictionary, request: Dictionary) -> Dictionary:
	if not suspend_enabled or _transaction==null or token.is_empty() or not PowerAuthority.mode(_active_rules): return _blocked("POWER_MODE_REQUIRED")
	var accepted: Dictionary=_transaction.accept_power(token,before,request)
	if accepted.error!=OK: return accepted
	var receipt: Dictionary=accepted.receipt
	var world: Dictionary=receipt.envelope.world.duplicate(true)
	if receipt.phase=="SUSPEND_READY":
		accepted=_transaction.claim_suspend(token,receipt.envelope.world_hash,receipt.envelope.previous_head)
		if accepted.error!=OK: return accepted
	elif receipt.phase!="RESUME_CLAIMED": return _blocked("POWER_ACK_PHASE")
	accepted.world=world
	return accepted


func accept_burst(before: Dictionary) -> Dictionary:
	if not suspend_enabled or _transaction == null or token.is_empty() or not BurstAuthorityV1.mode(_active_rules):
		return _blocked("BURST_MODE_REQUIRED")
	var accepted: Dictionary = _transaction.accept_burst(token, before)
	if accepted.error != OK:
		return accepted
	var receipt: Dictionary = accepted.receipt
	var world: Dictionary = receipt.envelope.world.duplicate(true)
	if receipt.phase == "SUSPEND_READY":
		accepted = _transaction.claim_suspend(token, receipt.envelope.world_hash, receipt.envelope.previous_head)
		if accepted.error != OK:
			return accepted
	elif receipt.phase != "RESUME_CLAIMED":
		return _blocked("BURST_ACK_PHASE")
	accepted.world = world
	return accepted
