extends SceneTree
## One process per invocation; only explicitly supplied task-local profiles are used.

var _output: String
var _mode: String = "read"
var _old: String
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--process-output="): _output = arg.trim_prefix("--process-output=")
		if arg.begins_with("--process-mode="): _mode = arg.trim_prefix("--process-mode=")
		if arg.begins_with("--process-old="): _old = arg.trim_prefix("--process-old=")
	if not _output.is_absolute_path() or "/.local/p0-record-hash-01/" not in _output or DirAccess.dir_exists_absolute(_output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var session: ProductionProgress = main.progress_session
	var state: Dictionary = session.inspect()
	if _mode == "busy":
		_expect(state.error != OK and "WRITER_BUSY" in String(state.get("reason","")), "second PID refuses same profile writer")
	elif _mode == "hold":
		_expect(state.error == OK,"first PID holds profile writer")
		_write("barrier.json",{"pid":OS.get_process_id()})
		var deadline: int = Time.get_ticks_msec()+45000
		while not FileAccess.file_exists(_output.path_join("release")) and Time.get_ticks_msec()<deadline:
			await create_timer(0.05).timeout
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
				var saved: Dictionary = transaction.suspend(token,world)
				_expect(saved.error == OK,"unchanged authoritative world can be resuspended")
				if saved.error == OK:
					_expect(saved.receipt.envelope.previous_head != generation and saved.receipt.envelope.world_hash == world_hash and RecordEncoding.fingerprint(saved.receipt.envelope.world) == exact_hash,"same-content S2/S3 has unique predecessor and exact unchanged world")
					var bytes_before: String = FileAccess.get_sha256(main.progress_path)
					_expect(transaction.claim_suspend(token,world_hash,generation).error != OK and bytes_before == FileAccess.get_sha256(main.progress_path),"stale generation rejection leaves camp unchanged")
				_write("consumed.json",{"generation":generation,"world_hash":world_hash,"token":token})
				state = saved
	var failed: int = _rows.filter(func(row: Dictionary) -> bool: return not row.pass).size()
	_write("result.json",{"pid":OS.get_process_id(),"mode":_mode,"layer":"macOS headless cross-process real files", "checks":_rows,"failures":failed,"state":state.get("state"),"hash":state.get("hash")})
	main.audio.shutdown()
	print("RECORD_PROCESS ",_mode," failures=",failed)
	quit(0 if failed == 0 else 1)


func _expect(value: bool, label: String) -> void:
	_rows.append({"case":label,"pass":value})
	if not value: print("FAILED ",label)


func _write(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true)+"\n")
	file.close()
