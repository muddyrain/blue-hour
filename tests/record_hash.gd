extends SceneTree
## Exact numeric transport, strict legacy authentication and mixed-generation regression.

var _rows: Array[Dictionary] = []
var _output: String


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--record-output="):
			_output = arg.trim_prefix("--record-output=")
	_output = _output.replace("\\", "/").simplify_path()
	if not _output.is_absolute_path() or "/.local/" not in _output or DirAccess.dir_exists_absolute(_output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	_run.call_deferred()


func _run() -> void:
	var small: float = JSON.parse_string("9.714451465470121e-17")
	var minimum: float = "0100000000000000".hex_decode().decode_double(0)
	var maximum: float = "ffffffffffffef7f".hex_decode().decode_double(0)
	var adjacent: PackedByteArray = RecordEncoding._number_hex(small).hex_decode()
	adjacent[0] += 1
	var values: Array = [small, -small, minimum, -minimum, maximum, -maximum, 0, -0.0, 2, 2.0,
		SurvivalContracts.MAX_JSON_INTEGER, -SurvivalContracts.MAX_JSON_INTEGER, 0.0333333333333333, 199.99999999999997,
		adjacent.decode_double(0), -adjacent.decode_double(0), 1.0e-300, -1.0e-300, 200.0, 1.0, -1.0]
	for index: int in range(values.size()):
		var value: Dictionary = {"nested":[null, true, "中文", {"x":values[index]}]}
		var hash: String = TransactionReceipt.fingerprint(value)
		var stable: bool = not hash.is_empty()
		for turn: int in range(10):
			var path: String = _output.path_join("numbers/%02d-%02d.json" % [index,turn])
			_write(path,RecordEncoding.stringify(value))
			var parsed: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(path)))
			stable = stable and parsed.error == OK
			if parsed.error != OK:
				break
			value = parsed.payload
			stable = stable and hash == TransactionReceipt.fingerprint(value) and RecordEncoding._number_hex(value.nested[3].x) == RecordEncoding._number_hex(values[index])
		_expect(stable, "ten actual disk roundtrips preserve binary64 numeric case " + str(index))
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
	for bad: Variant in [[],["null",1],["bool",1],["string",false],["unknown",[]],["array",null],["object",[[1,["null"]]]],["number","00"],["number","000000000000F03F"],["number","000000000000f87f"],["number","000000000000f0ff"],null,{},[42]]:
		_expect(not RecordEncoding._decode(bad,-2).ok,"malformed typed tree rejected: "+str(bad))
	var nested: Array = ["null"]
	for depth: int in range(68): nested = ["array",[nested]]
	_expect(not RecordEncoding._decode(nested,-2).ok,"encoded depth overflow rejected")
	var excessive: Dictionary = {"leaf":null}
	for depth: int in range(68): excessive = {"nested":excessive}
	_expect(RecordEncoding.stringify(excessive).is_empty(),"input depth overflow rejected before encoding")
	for key: String in ["payload","record_encoding","sha256"]:
		packet = JSON.parse_string(RecordEncoding.stringify({"x":small}))
		packet.erase(key)
		_expect(RecordEncoding.unpack(packet).error != OK,"missing outer field rejected: "+key)
	packet = JSON.parse_string(RecordEncoding.stringify({"x":small}))
	packet.extra = true
	_expect(RecordEncoding.unpack(packet).error != OK,"additional outer field rejected")
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
			for revision: int in range(1,4):
				_write(_output.path_join("mixed-valid/%08d/record.json" % revision),FileAccess.get_file_as_string(journal.directory.path_join("%08d/record.json" % revision)))
			var raw: Dictionary = JSON.parse_string(original)
			raw.sha256 = "0".repeat(64)
			_write(_output.path_join("bad-hash.json"), JSON.stringify(raw))
			_expect(journal._read_record(_output.path_join("bad-hash.json")).error != OK, "new corrupted hash rejected")
			_write(_output.path_join("truncated.json"), original.left(original.length()/2))
			_expect(journal._read_record(_output.path_join("truncated.json")).error != OK, "truncated record rejected")
			DirAccess.rename_absolute(journal.directory.path_join("00000003"),journal.directory.path_join("00000004"))
			_expect(journal.read_all().get("reason") == "GENERATION_GAP", "generation gap rejected")
	_expect(old_bytes == FileAccess.get_sha256(old_path), "legacy original byte SHA unchanged")
	var full: Dictionary = TransactionReceipt.initial(base,base.profile_id+":1",{"ruleset_id":"capacity-regression","data_version":1,"text":"x".repeat(ReceiptJournal.MAX_BYTES)},registration)
	var capacity: Dictionary = ReceiptJournal.new(_output.path_join("capacity" )).append(registration,"")
	var capacity_journal: ReceiptJournal = ReceiptJournal.new(_output.path_join("capacity"))
	var capacity_before: String = FileAccess.get_sha256(capacity_journal.directory.path_join("00000001/record.json"))
	_expect(capacity_journal.append(full,capacity.hash).get("reason") == "JOURNAL_COMPLETION_BYTE_RESERVE" and capacity_before == FileAccess.get_sha256(capacity_journal.directory.path_join("00000001/record.json")),"actual encoded byte capacity rejects before publishing or altering original")
	_expect(ReceiptJournal.capacity_problem(4094,"SUSPEND_READY",100,0,0) == "JOURNAL_COMPLETION_REVISION_RESERVE","suspend retains claim result commit revision reserve")
	_expect(ReceiptJournal.capacity_problem(2,"STARTED",100,0,32) == "UNPUBLISHED_STAGE_LIMIT","stage count limit preserved")
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
	_write(_output.path_join("result.json"),JSON.stringify({"pid":OS.get_process_id(),"layer":OS.get_name()+" headless real files","checks":_rows,"failures":failed},"\t"))
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
