class_name RecordHashProcess
extends Node
## One process per invocation; only explicitly supplied task-local profiles are used.

var app: Node
var _output: String
var _mode: String = "read"
var _old: String
var _rows: Array[Dictionary] = []
var _expected_state: String = ""
var _barrier: String = ""
var _barrier_phase: String = ""
var _journal_path: String = ""
var _legacy_sources: String = ""
var _expected_camp: String = ""
var _expected_world: String = ""
var _armed: bool = false
var _fired: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--process-output="): _output = arg.trim_prefix("--process-output=")
		if arg.begins_with("--process-mode="): _mode = arg.trim_prefix("--process-mode=")
		if arg.begins_with("--process-old="): _old = arg.trim_prefix("--process-old=")
		if arg.begins_with("--expected-state="): _expected_state = arg.trim_prefix("--expected-state=")
		if arg.begins_with("--process-barrier="): _barrier = arg.trim_prefix("--process-barrier=")
		if arg.begins_with("--barrier-phase="): _barrier_phase = arg.trim_prefix("--barrier-phase=")
		if arg.begins_with("--process-journal="): _journal_path = arg.trim_prefix("--process-journal=").replace("\\","/").simplify_path()
		if arg.begins_with("--legacy-fixtures="): _legacy_sources = arg.trim_prefix("--legacy-fixtures=").replace("\\","/").simplify_path()
		if arg.begins_with("--process-camp-expected="): _expected_camp = arg.trim_prefix("--process-camp-expected=")
		if arg.begins_with("--process-world-expected="): _expected_world = arg.trim_prefix("--process-world-expected=")
	_output = _output.replace("\\", "/").simplify_path()
	if not _output.is_absolute_path() or "/.local/p0-record-hash-02/" not in _output or DirAccess.dir_exists_absolute(_output):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	_run.call_deferred()


func _run() -> void:
	var main: Node = app
	if main == null:
		main = load("res://src/app/main.tscn").instantiate()
		get_tree().root.add_child(main)
	app = main
	var path: String = main.progress_path.replace("\\","/").simplify_path()
	var scope: String = _output.get_slice("/.local/p0-record-hash-02/",0)
	var identity: String = path.to_lower() if OS.has_feature("windows") else path
	var allowed: String = (scope+"/.local/p0-record-hash-02/").to_lower() if OS.has_feature("windows") else scope+"/.local/p0-record-hash-02/"
	if not path.is_absolute_path() or not identity.begins_with(allowed):
		get_tree().quit(2)
		return
	await get_tree().process_frame
	var session: ProductionProgress = main.progress_session
	session.fault_hook = _wait_at_barrier
	var state: Dictionary = session.inspect()
	if _mode == "legacy":
		_legacy_compatibility()
	elif _mode == "inspect":
		_expect((state.error != OK if _expected_state == "BLOCKED" else state.error == OK and state.get("state") == _expected_state),"fresh PID state matches "+_expected_state)
		if not _expected_camp.is_empty() and state.error == OK: _compare_expected(state.camp,_expected_camp,"new PID exact latest camp/death/edit/training")
		if not _expected_world.is_empty() and state.error == OK: _compare_expected(state.receipt.envelope.world,_expected_world,"new PID exact world after publication/ACK crash")
	elif _mode == "contact-old":
		_expect(state.error == OK and state.get("state") == "SUSPENDED","legacy world authenticates under its exact historical shape")
		if state.error == OK and state.get("state") == "SUSPENDED":
			var malformed: Dictionary = state.receipt.envelope.world.duplicate(true)
			malformed.survivors[0].visual._walk_rest = 0.0
			_expect(not SortieSnapshot.problem(malformed,state.receipt).is_empty(),"legacy authentication still rejects extra contact fields")
		var unchanged: String = _files_digest(main.progress_path)
		main._hunger_consented = true
		main.continue_game()
		await get_tree().process_frame
		_expect(main.expedition == null and main._progress_blocked and not main._requires_continue,"old contact rules explicitly refuse resume before a claim")
		_expect("旧接触规则" in main._progress_message,"old-world rejection explains the compatibility boundary")
		_expect(session.inspect().get("state") == "SUSPENDED" and unchanged == _files_digest(main.progress_path),"legacy in-flight records remain unconsumed and byte identical")
	elif _mode == "contact-cache":
		_expect(state.error == OK and state.get("state") == "SUSPENDED","new contact world is suspended")
		var original: Dictionary = state.receipt.envelope.world.duplicate(true)
		var missing: Dictionary = original.duplicate(true)
		missing.survivors[0].visual.erase("_contact_display")
		_expect(not SortieSnapshot.problem(missing,state.receipt).is_empty(),"new contact build cannot omit its required visual state")
		main.survival_pilot = false
		main._hunger_consented = true
		main.continue_game()
		await get_tree().process_frame
		var world: Expedition = main.expedition
		_expect(world != null and world.is_paused,"new PID restores paused without solver movement")
		if world != null:
			_expect(RecordEncoding.fingerprint(SortieSnapshot.capture(world)) == RecordEncoding.fingerprint(original),"restored position path clocks and contact visual caches exactly match")
			var frozen: String = RecordEncoding.fingerprint(SortieSnapshot.capture(world))
			world.step(1.0)
			_expect(frozen == RecordEncoding.fingerprint(SortieSnapshot.capture(world)),"paused step does not separate, advance or change a single saved value")
			world.toggle_pause()
			var starts: Array[Vector2] = []
			for actor: FieldActor in world.survivors: starts.append(actor.position)
			world.step(1.0/60.0)
			var bounded: bool = true
			for index: int in range(world.survivors.size()): bounded = bounded and world.survivors[index].position.distance_to(starts[index])<=world.survivors[index].speed/60.0+FieldContacts.RECOVERY_SPEED/60.0+1.0
			_expect(bounded,"first resumed contact tick stays within motion/recovery budget")
			world.toggle_pause()
			var continued: Dictionary = SortieSnapshot.capture(world)
			_write_exact("continued.exact.json",continued)
			var suspended: Dictionary = session.suspend_world(continued)
			_expect(suspended.error == OK and session.inspect().get("state") == "SUSPENDED","continued contact world republishes a new real generation")
	elif _mode == "journal-read":
		if not _journal_path.is_absolute_path() or "/.local/p0-record-hash-02/" not in _journal_path:
			get_tree().quit(2)
			return
		var mixed: Dictionary = ReceiptJournal.new(_journal_path).read_all()
		_expect(mixed.error == OK and mixed.receipt.revision == 3 and mixed.receipt.phase == "IN_PROGRESS","fresh PID authenticates legacy/new mixed chain")
	elif _mode == "replay":
		_expect(state.error == OK and state.get("state") in ["CAMP","ENDED"],"latest confirmed camp is readable")
		var stable: String = _files_digest(main.progress_path)
		for folder: String in DirAccess.get_directories_at(main.progress_path+".txn/journal"):
			if folder.begins_with(".stage-"): continue
			var record: Dictionary = session._transaction._journal._read_record((main.progress_path+".txn/journal").path_join(folder).path_join("record.json"))
			_expect(record.error == OK,"published record authenticates before replay probe")
			if record.error == OK and record.receipt.phase == "SUSPEND_READY":
				var old: Dictionary = record.receipt
				_expect(session._transaction.claim_suspend(RunTransaction.token_for(old),old.envelope.world_hash,old.envelope.previous_head).error != OK,"new PID rejects every old generation after camp changes")
				_expect(session._transaction.suspend(RunTransaction.token_for(old),old.envelope.world).error != OK,"new PID rejects every old world after camp changes")
		_expect(stable == _files_digest(main.progress_path),"old worlds cannot change latest death edit training or result bytes")
	elif _mode == "activate":
		_expect(state.error == OK and state.get("state") in ["RECOVERY_READY","CAMP","ENDED"],"committable or acknowledged camp exists")
		var frozen: Dictionary = state.receipt.envelope.result if state.receipt.phase in ["EDIT_READY","EDIT_COMMITTED"] else state.receipt.envelope.result.camp
		_armed = true
		var committed: Dictionary = session.activate()
		_expect(committed.error == OK and committed.get("state") in ["CAMP","ENDED"],"READY activation commits existing frozen result once")
		_expect(RecordEncoding.fingerprint(committed.camp) == RecordEncoding.fingerprint(frozen) and committed.camp.settled_sorties == frozen.settled_sorties,"first activation applies the exact frozen camp and settlement count")
		if not _expected_camp.is_empty(): _compare_expected(committed.camp,_expected_camp,"first restart applies pre-kill authoritative camp exactly")
		var stable: String = _files_digest(main.progress_path)
		for repeat: int in range(3): session.activate()
		_expect(stable == _files_digest(main.progress_path),"repeated activation never adds a receipt or reward")
		state = committed
	elif _mode in ["edit","train"]:
		_expect(state.error == OK and state.get("state") == "CAMP","camp edit starts at acknowledged state")
		if state.error == OK and state.get("state") == "CAMP":
			var before: Dictionary = state.camp.duplicate(true)
			var request: Dictionary = {"kind":"rename","member_id":1,"value":"精确回读"}
			if _mode == "train":
				var preview: Dictionary = TrainingRules.preview(before,1)
				_expect(String(preview.get("error","unavailable")).is_empty(),"real training preview accepts living member and food")
				request = preview.get("request",{})
			_armed = true
			_write_exact("operation.expected.exact.json",CampEdit.propose(before,request))
			var edited: Dictionary = session.edit(before,request)
			_expect(edited.error == OK and edited.get("state") == "CAMP","existing edit transaction commits")
			if edited.error == OK:
				_expect(edited.camp.journey.deaths == before.journey.deaths and edited.camp.recruits == before.recruits,"camp edit preserves confirmed deaths and real recruit history")
				if _mode == "train": _expect(edited.camp.food == before.food-1,"one real training purchase costs one food")
				else: _expect(SurvivorRoster.member(edited.camp.crew,1).call_sign == "精确回读","rename durable via original edit owner")
			state = edited
	elif _mode == "busy":
		_expect(state.error != OK and "WRITER_BUSY" in String(state.get("reason","")), "second PID refuses same profile writer")
	elif _mode == "hold":
		_expect(state.error == OK,"first PID holds profile writer")
		_write("barrier.json",{"pid":OS.get_process_id()})
		var deadline: int = Time.get_ticks_msec()+45000
		while not FileAccess.file_exists(_output.path_join("release")) and Time.get_ticks_msec()<deadline:
			await get_tree().create_timer(0.05).timeout
	else:
		_expect(state.error == OK,"fresh PID authenticates complete chain and binding")
		if state.error == OK and _mode in ["same-resave","retry-ack"]:
			var offered: Dictionary = session.resume_offer()
			_expect(offered.error == OK,"SUSPEND_READY offered in fresh PID")
			if offered.error == OK:
				var transaction: RunTransaction = session._transaction
				var world: Dictionary = offered.receipt.envelope.world.duplicate(true)
				var world_hash: String = offered.receipt.envelope.world_hash
				var exact_hash: String = RecordEncoding.fingerprint(world)
				var generation: String = offered.receipt.envelope.previous_head
				var token: Dictionary = RunTransaction.token_for(offered.receipt)
				_armed = true
				if not _old.is_empty():
					var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_old))
					_expect(transaction.claim_suspend(old.token,old.world_hash,old.generation).error != OK,"old generation cannot consume new identical world")
				if _mode == "retry-ack":
					transaction._fault = func(point: String) -> Error: return ERR_CANT_CREATE if point == "before_binding_write" else OK
				var claimed: Dictionary = transaction.claim_suspend(token,world_hash,generation)
				if _mode == "retry-ack":
					_expect(claimed.error != OK,"published claim with unacknowledged binding reports failure")
					var pending: Dictionary = transaction._journal.read_all()
					transaction._fault = Callable()
					claimed = transaction.claim_suspend(token,world_hash,generation)
					_expect(claimed.error == OK and claimed.hash == pending.hash,"same owner retries exact published claim without a new generation")
				_expect(claimed.error == OK,"current generation claimed exactly once")
				_expect(transaction.claim_suspend(token,world_hash,generation).error != OK,"duplicate acknowledged claim refused")
				for changed: String in ["version","build","compatibility"]:
					var incompatible: Dictionary = world.duplicate(true)
					incompatible[changed] = 999 if changed == "version" else "unknown-old-build" if changed == "build" else {}
					var before_reject: String = _files_digest(main.progress_path)
					_expect(transaction.suspend(token,incompatible).error != OK and before_reject == _files_digest(main.progress_path),"incompatible synthetic old-world "+changed+" refused without changing original bytes")
				var saved: Dictionary = transaction.suspend(token,world)
				_expect(saved.error == OK,"unchanged authoritative world can be resuspended")
				if saved.error == OK:
					_expect(saved.receipt.envelope.previous_head != generation and saved.receipt.envelope.world_hash == world_hash and RecordEncoding.fingerprint(saved.receipt.envelope.world) == exact_hash,"same-content S2/S3 has unique predecessor and exact unchanged world")
					var bytes_before: String = FileAccess.get_sha256(main.progress_path)
					_expect(transaction.claim_suspend(token,world_hash,generation).error != OK and bytes_before == FileAccess.get_sha256(main.progress_path),"stale generation rejection leaves camp unchanged")
				_write("consumed.json",{"generation":generation,"world_hash":world_hash,"token":token})
				state = saved
	var failed: int = _rows.filter(func(row: Dictionary) -> bool: return not row.pass).size()
	_write("result.json",{"pid":OS.get_process_id(),"mode":_mode,"layer":OS.get_name()+" process / "+DisplayServer.get_name(), "checks":_rows,"failures":failed,"state":state.get("state"),"reason":state.get("reason"),"hash":state.get("hash"),"camp":state.get("camp",{})})
	main.audio.shutdown()
	print("RECORD_PROCESS ",_mode," failures=",failed)
	get_tree().quit(0 if failed == 0 else 1)


func _expect(value: bool, label: String) -> void:
	_rows.append({"case":label,"pass":value})
	if not value: print("FAILED ",label)


func _write(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true)+"\n")
	file.close()


func _files_digest(path: String) -> String:
	var files: Dictionary = {}
	for suffix: String in ["",".bak",".txn/binding.json"]:
		files[suffix] = FileAccess.get_sha256(path+suffix) if FileAccess.file_exists(path+suffix) else "MISSING"
	var journal: ReceiptJournal = ReceiptJournal.new(path+".txn/journal")
	files.head = journal.read_all().get("hash","")
	return SurvivalContracts.fingerprint(files)


func _wait_at_barrier(point: String) -> Error:
	if not _armed or _fired or _barrier.is_empty() or point != _barrier:
		return OK
	if not _barrier_phase.is_empty() and point == "after_record_publish":
		var head: Dictionary = ReceiptJournal.new(app.progress_path+".txn/journal").read_all()
		if head.error != OK or head.receipt.phase != _barrier_phase: return OK
	_fired = true
	_write("barrier.json",{"pid":OS.get_process_id(),"point":point,"operation":_mode,"phase":_barrier_phase,"failures":_rows.filter(func(row: Dictionary) -> bool: return not row.pass).size()})
	var deadline: int = Time.get_ticks_msec()+45000
	while not FileAccess.file_exists(_output.path_join("release")) and Time.get_ticks_msec()<deadline:
		OS.delay_msec(10)
	return OK


func _write_exact(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(name),FileAccess.WRITE)
	file.store_string(RecordEncoding.stringify(value))
	file.close()


func _compare_expected(actual: Dictionary, source: String, description: String) -> void:
	var path: String = source.replace("\\","/").simplify_path()
	if not path.is_absolute_path() or "/.local/p0-record-hash-02/" not in path:
		_expect(false,"expected oracle must be task local")
		return
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_expect(decoded.error == OK,"expected oracle authenticates before comparison")
	_expect(decoded.error == OK and RecordEncoding.fingerprint(actual) == RecordEncoding.fingerprint(decoded.get("payload",{})),description)


func _legacy_compatibility() -> void:
	if not _legacy_sources.is_absolute_path() or "/.local/p0-record-hash-02/" not in _legacy_sources:
		_expect(false,"legacy fixture directory must be task local")
		return
	var migrated: Dictionary = {}
	for name: String in DirAccess.get_files_at(_legacy_sources):
		if not name.ends_with(".json"): continue
		var source: String = _legacy_sources.path_join(name)
		var target: String = _output.path_join(name)
		var original: String = FileAccess.get_sha256(source)
		var file: FileAccess = FileAccess.open(target,FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(source))
		file.close()
		var save: RunSave = RunSave.new(target)
		_expect(save.load_save() == OK and save.snapshot.schema_version == 5,"synthetic legacy camp loads through existing migration: "+name)
		_expect(original == FileAccess.get_sha256(source) and original == FileAccess.get_sha256(target),"legacy read never modifies primary/source bytes: "+name)
		_expect(save.read_transaction_exact().error != OK,"unacknowledged legacy is refused by transaction exact reader: "+name)
		migrated = save.snapshot.duplicate(true)
	for version: int in [3,4,5]:
		var value: Dictionary = migrated.duplicate(true)
		value.schema_version = version
		for index: int in range(value.crew.size()):
			if version == 3: value.crew[index] = {"id":value.crew[index].id,"health":value.crew[index].health}
			elif version == 4: value.crew[index].erase("growth")
		var target: String = _output.path_join("synthetic-v%d.json" % version)
		var file: FileAccess = FileAccess.open(target,FileAccess.WRITE)
		file.store_string(JSON.stringify(value,"",true,true))
		file.close()
		var original: String = FileAccess.get_sha256(target)
		var save: RunSave = RunSave.new(target)
		_expect(save.load_save() == OK and save.snapshot.schema_version == 5,"synthetic v%d retains existing supported camp semantics" % version)
		_expect(FileAccess.get_sha256(target) == original,"synthetic camp read retains original bytes")
	var unsupported: Dictionary = migrated.duplicate(true)
	unsupported.schema_version = 999
	var target: String = _output.path_join("unsupported.json")
	var file: FileAccess = FileAccess.open(target,FileAccess.WRITE)
	file.store_string(JSON.stringify(unsupported))
	file.close()
	var original: String = FileAccess.get_sha256(target)
	_expect(RunSave.new(target).load_save() != OK and original == FileAccess.get_sha256(target),"unknown camp version refused without rewriting original")
	var pair: String = _output.path_join("explicit-backup-choice.json")
	var backup: String = _legacy_sources.path_join("legacy-v2-backup.json")
	file = FileAccess.open(pair,FileAccess.WRITE)
	file.store_string("{bad-json")
	file.close()
	file = FileAccess.open(pair+".bak",FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(backup))
	file.close()
	var primary_hash: String = FileAccess.get_sha256(pair)
	var backup_hash: String = FileAccess.get_sha256(pair+".bak")
	var saved: RunSave = RunSave.new(pair)
	_expect(saved.load_save() != OK and saved.load_save(true) == OK,"bad primary refuses; explicit checked legacy backup choice succeeds")
	_expect(primary_hash == FileAccess.get_sha256(pair) and backup_hash == FileAccess.get_sha256(pair+".bak"),"explicit legacy backup read leaves both original files unchanged")
