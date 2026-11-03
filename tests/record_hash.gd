extends SceneTree
## Exact numeric transport, strict legacy authentication and mixed-generation regression.

var _rows: Array[Dictionary] = []
var _output: String


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--record-output="):
			_output = arg.trim_prefix("--record-output=")
	if not _output.is_absolute_path() or "/.local/" not in _output or DirAccess.dir_exists_absolute(_output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	_run.call_deferred()


func _run() -> void:
	var small: float = JSON.parse_string("9.714451465470121e-17")
	var minimum: float = "0100000000000000".hex_decode().decode_double(0)
	var maximum: float = "ffffffffffffef7f".hex_decode().decode_double(0)
	var values: Array = [small, -small, minimum, -minimum, maximum, -maximum, 0, -0.0, 2, 2.0,
		SurvivalContracts.MAX_JSON_INTEGER, -SurvivalContracts.MAX_JSON_INTEGER, 0.0333333333333333, 199.99999999999997]
	for index: int in range(values.size()):
		var value: Dictionary = {"nested":[null, true, "中文", {"x":values[index]}]}
		var hash: String = TransactionReceipt.fingerprint(value)
		var stable: bool = not hash.is_empty()
		for turn: int in range(10):
			var parsed: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(value)))
			stable = stable and parsed.error == OK
			if parsed.error != OK:
				break
			value = parsed.payload
			stable = stable and hash == TransactionReceipt.fingerprint(value) and value.nested[3].x == values[index]
		_expect(stable, "ten exact JSON roundtrips numeric case " + str(index))
	_expect(TransactionReceipt.fingerprint({"x":2}) == TransactionReceipt.fingerprint({"x":2.0}), "int and float share JSON business identity")
	_expect(TransactionReceipt.fingerprint({"x":0}) == TransactionReceipt.fingerprint({"x":-0.0}), "both zero signs share JSON business identity")
	_expect(TransactionReceipt.fingerprint({"b":2,"a":1}) == TransactionReceipt.fingerprint({"a":1.0,"b":2.0}), "dictionary order is canonical")
	_expect(TransactionReceipt.fingerprint({"x":small}) != TransactionReceipt.fingerprint({"x":JSON.parse_string("9.71445146547012e-17")}), "adjacent small values remain distinct")
	_expect(TransactionReceipt.fingerprint({"x":200.0}) != TransactionReceipt.fingerprint({"x":199.99999999999997}), "one ULP business change remains distinct")
	_expect(TransactionReceipt.fingerprint({"x":minimum}) != TransactionReceipt.fingerprint({"x":0.0}), "subnormal never rounds to zero")
	_expect(TransactionReceipt.fingerprint({"x":INF}).is_empty() and TransactionReceipt.fingerprint({"x":NAN}).is_empty(), "nonfinite input rejected")
	_expect(TransactionReceipt.fingerprint({"x":SurvivalContracts.MAX_JSON_INTEGER + 1}).is_empty(), "unsafe integer rejected")
	var packet: Dictionary = JSON.parse_string(RecordEncoding.stringify({"x":small}))
	packet.payload[1][0][1][1] = RecordEncoding._number_hex(-small)
	_expect(RecordEncoding.unpack(packet).error != OK, "fine payload tampering rejected without rehash")
	packet = JSON.parse_string(RecordEncoding.stringify({"x":small}))
	packet.record_encoding = "UNKNOWN"
	_expect(RecordEncoding.unpack(packet).error != OK, "unknown codec rejected")
	for bad: Array in [["number","000000000000f07f"], ["number","0000000000000080"], ["object", [["x",["null"]],["x",["null"]]]], ["object", [["z",["null"]],["a",["null"]]]]]:
		_expect(not RecordEncoding._decode(bad, 0).ok, "noncanonical or invalid tagged input rejected")
	var main: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var base: Dictionary = main.camp_snapshot()
	var journal: ReceiptJournal = ReceiptJournal.new(_output.path_join("mixed-journal"))
	var registration: Dictionary = TransactionReceipt.registration(base, "22222222222222222222222222222222")
	var old_hash: String = TransactionReceipt.legacy_fingerprint(registration)
	var old_path: String = journal.directory.path_join("00000001/record.json")
	_write(old_path, JSON.stringify({"payload":registration,"sha256":old_hash}, "", true, true) + "\n")
	var old_bytes: String = FileAccess.get_sha256(old_path)
	var prior: Dictionary = journal.read_all()
	_expect(prior.error == OK and prior.hash == old_hash, "old valid receipt verifies with original algorithm")
	if prior.error == OK:
		var next: Dictionary = TransactionReceipt.initial(base, base.profile_id + ":1", {"ruleset_id":"hash-regression","data_version":1,"clock":small}, prior.receipt)
		var result: Dictionary = journal.append(next, prior.hash)
		_expect(result.error == OK, "actual journal append/readback accepts old minimal counterexample")
		if result.error == OK:
			_expect(result.receipt.rules.clock == small, "disk preserves exact binary64")
			for turn: int in range(10):
				var reread: Dictionary = ReceiptJournal.new(journal.directory).read_all()
				_expect(reread.error == OK and reread.hash == result.hash, "complete mixed chain reread " + str(turn))
			var checkpoint: Dictionary = result.receipt.duplicate(true)
			checkpoint.revision += 1
			checkpoint.phase = "IN_PROGRESS"
			checkpoint.health[0].health -= 1.0
			var continued: Dictionary = journal.append(checkpoint, result.hash)
			_expect(continued.error == OK, "append after exact readback preserves previous_hash")
			var protected: String = FileAccess.get_sha256(journal.directory.path_join("00000002/record.json"))
			_expect(journal.append(checkpoint, result.hash).error != OK and protected == FileAccess.get_sha256(journal.directory.path_join("00000002/record.json")), "stale head refuses overwrite")
			var new_path: String = journal.directory.path_join("00000002/record.json")
			var original: String = FileAccess.get_file_as_string(new_path)
			var raw: Dictionary = JSON.parse_string(original)
			raw.sha256 = "0".repeat(64)
			_write(_output.path_join("bad-hash.json"), JSON.stringify(raw))
			_expect(journal._read_record(_output.path_join("bad-hash.json")).error != OK, "new corrupted hash rejected")
			_write(_output.path_join("truncated.json"), original.left(original.length()/2))
			_expect(journal._read_record(_output.path_join("truncated.json")).error != OK, "truncated record rejected")
			DirAccess.rename_absolute(journal.directory.path_join("00000003"),journal.directory.path_join("00000004"))
			_expect(journal.read_all().get("reason") == "GENERATION_GAP", "generation gap rejected")
	_expect(old_bytes == FileAccess.get_sha256(old_path), "legacy original byte SHA unchanged")
	var failed_receipt: Dictionary = TransactionReceipt.initial(base,base.profile_id+":1",{"ruleset_id":"old-failure","data_version":1,"clock":small},registration)
	failed_receipt.previous_hash = old_hash
	var failed_path: String = _output.path_join("legacy-cycle.json")
	_write(failed_path,JSON.stringify({"payload":failed_receipt,"sha256":TransactionReceipt.legacy_fingerprint(failed_receipt)},"",true,true))
	var failed_sha: String = FileAccess.get_sha256(failed_path)
	_expect(journal._read_record(failed_path).get("reason") == "RECORD_HASH" and FileAccess.get_sha256(failed_path) == failed_sha,"old cycle-invalid record remains refused and byte preserved")
	var legacy_bad: Dictionary = {"payload":registration,"sha256":"0".repeat(64)}
	_write(_output.path_join("legacy-bad.json"), JSON.stringify(legacy_bad, "", true, true))
	_expect(journal._read_record(_output.path_join("legacy-bad.json")).error != OK, "legacy bad receipt never accepted by new algorithm fallback")
	legacy_bad.sha256 = TransactionReceipt.fingerprint(registration)
	_write(_output.path_join("legacy-new-hash.json"),JSON.stringify(legacy_bad,"",true,true))
	_expect(journal._read_record(_output.path_join("legacy-new-hash.json")).error != OK,"new hash cannot relabel an unversioned legacy record")
	main.audio.shutdown()
	var failed: int = _rows.filter(func(row: Dictionary) -> bool: return not row.pass).size()
	_write(_output.path_join("result.json"),JSON.stringify({"pid":OS.get_process_id(),"layer":"macOS headless real files","checks":_rows,"failures":failed},"\t"))
	print("RECORD_HASH_REGRESSION checks=",_rows.size()," failures=",failed)
	quit(0 if failed == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	_rows.append({"case":label,"pass":condition})
	if not condition:
		print("FAILED ",label)


func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
