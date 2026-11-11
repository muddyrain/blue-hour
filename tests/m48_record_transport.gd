extends SceneTree
## Isolated normal registration/edit chain plus pure transport negatives.
## --transport-receipt=/absolute/repo/.local/.../record.json (repeatable, read only)
## --transport-require-partial requires a real supplied SUSPEND_READY partial reload.

var failures: Array[String] = []
var rows: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var output: String
var saw_partial: bool = false


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	rows.append({"pass":ok, "label":label})
	if not ok:
		failures.append(label)
		printerr("M48_RECORD_TRANSPORT_FAIL ", label)


func _stage(label: String) -> void:
	print("M48_RECORD_TRANSPORT_STAGE ", Time.get_ticks_usec(), " ", label)


func _run() -> void:
	_stage("run begin")
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	output = OS.get_user_data_dir().path_join("m48-record-transport-evidence")
	if DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._new_game("scavenge", {"version":CatalogProgress.VERSION, "unlock":""},
		{"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	_stage("ordinary registration returned")
	var transaction: RunTransaction = app.progress_session._transaction
	_check(transaction != null and not app._progress_blocked, "ordinary isolated M48 registration completes its real readback")
	if transaction != null:
		var journal: ReceiptJournal = transaction._journal
		var head: Dictionary = journal.read_all()
		_stage("first journal read returned")
		_check(head.error == OK and head.receipt.phase == "CAMP_REGISTERED", "new receipt authenticates through original complete journal validation")
		if head.error == OK:
			var receipt: Dictionary = head.receipt
			_roundtrip(receipt, "ordinary-M48-registration")
			_stage("registration roundtrip returned")
			_legacy_cases(receipt)
			_stage("legacy cases returned")
			_negative_cases(receipt)
			_stage("negative cases returned")
			_cache_case(journal)
			_stage("cache case returned")
			_business_case(receipt)
			_stage("business case returned")
			_mixed_case(transaction, head)
			_stage("mixed case returned")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--transport-receipt="):
			_real_receipt(argument.trim_prefix("--transport-receipt="), isolated)
	if "--transport-require-partial" in OS.get_cmdline_user_args():
		_check(saw_partial, "a real complete supplied SUSPEND_READY receipt contains an incomplete magazine reload")
	_check(M48RecordTransport.MAX_UNPACKED_BYTES == ReceiptJournal.MAX_BYTES and ReceiptJournal.MAX_BYTES == 4_194_304
		and ReceiptJournal.MAX_TOTAL_BYTES == 67_108_864 and RunSave.MAX_BYTES == 1_048_576,
		"all existing record, journal and camp size limits remain unchanged")
	app.audio.shutdown()
	app.queue_free()
	await process_frame
	var report: Dictionary = {"scope":"normal-isolated-registration-and-edits; supplied-records-read-only; negative-transport-fixtures",
		"record_encoding":M48RecordTransport.VERSION, "checks":rows.size(), "failures":failures,
		"rows":rows, "samples":samples, "real_partial_reload":saw_partial}
	_write(output.path_join("report.json"), JSON.stringify(report, "\t", true, true))
	print("M48_RECORD_TRANSPORT ", JSON.stringify(report, "", true, true))
	quit(0 if failures.is_empty() else 1)


func _roundtrip(receipt: Dictionary, label: String) -> void:
	_stage("roundtrip begin " + label)
	var began: int = Time.get_ticks_usec()
	var original: Dictionary = RecordEncoding.pack_v1(receipt)
	var packed: Dictionary = RecordEncoding.pack(receipt)
	_stage("roundtrip packs returned " + label)
	_check(not original.is_empty() and not packed.is_empty(), label + " packs within the unchanged bound")
	if original.is_empty() or packed.is_empty(): return
	var outer: Dictionary = JSON.parse_string(packed.text)
	var decoded: Dictionary = RecordEncoding.unpack(outer)
	_stage("roundtrip unpack returned " + label)
	_check(M48RecordTransport.eligible(receipt) and outer.get("record_encoding") == M48RecordTransport.VERSION,
		label + " selects the explicit M48-only transport")
	_check(decoded.error == OK and decoded.hash == original.hash and packed.hash == original.hash
		and RecordEncoding.fingerprint(decoded.get("payload", {})) == original.hash,
		label + " preserves the original V1 semantic hash and every binary64 value")
	_check(decoded.error == OK and RecordEncoding.pack_v1(decoded.payload).text == original.text,
		label + " reconstructs the identical complete canonical V1 packet bytes")
	_check(RecordEncoding.pack(receipt).text == packed.text,
		label + " has deterministic compressed bytes")
	_check(RecordEncoding.unpack(JSON.parse_string(original.text)).get("hash") == original.hash,
		label + " keeps the original uncompressed V1 readable")
	var gzip: Dictionary = M48RecordTransport.pack(receipt, original, M48RecordTransport.GZIP_VERSION)
	var gzip_decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(gzip.text)) if not gzip.is_empty() else {"error":ERR_FILE_CORRUPT}
	_check(gzip_decoded.error == OK and gzip_decoded.hash == original.hash
		and RecordEncoding.pack_v1(gzip_decoded.payload).text == original.text,
		label + " keeps complete earlier M48 GZIP bytes readable with the same exact content")
	var issue: String = TransactionReceipt.problem(decoded.get("payload", {}))
	_stage("roundtrip business validation returned " + label)
	_check(issue.is_empty(), label + " still passes the original full business and source validator: " + issue)
	samples.append({"label":label, "phase":receipt.get("phase"), "revision":receipt.get("revision"),
		"hash":original.hash, "original_v1_bytes":String(original.text).to_utf8_buffer().size(),
		"physical_bytes":String(packed.text).to_utf8_buffer().size(), "compressed_bytes":outer.get("compressed_bytes"),
		"gzip_physical_bytes":String(gzip.get("text", "")).to_utf8_buffer().size(),
		"encode_decode_validate_usec":Time.get_ticks_usec()-began})


func _legacy_cases(receipt: Dictionary) -> void:
	_stage("legacy begin")
	# A pure historical registration fixture; no saved camp or earned resources are changed.
	var camp: Dictionary = receipt.base.duplicate(true)
	camp.journey.campaign.erase("economy")
	camp.journey.build.erase("progression")
	camp.journey.build.powers = PowerState.initial_progression(SpecialPowers.M47_VERSION)
	var legacy: Dictionary = TransactionReceipt.registration(camp, camp.journey.root_id)
	var issue: String = TransactionReceipt.problem(legacy)
	_stage("legacy business validation returned")
	_check(issue.is_empty(), "explicit M47 registration fixture passes its original rules: " + issue)
	var original: Dictionary = RecordEncoding.pack_v1(legacy)
	var packed: Dictionary = RecordEncoding.pack(legacy)
	_check(not M48RecordTransport.eligible(legacy) and packed == original,
		"historical M47 pack remains byte-for-byte original V1")
	_check(RecordEncoding.unpack(JSON.parse_string(original.text)).error == OK,
		"historical M47 V1 remains readable")
	_reject(_wrap(String(original.text).to_utf8_buffer(), original.hash), "M47 receipt cannot use the M48 transport tag")
	_reject(_wrap(String(original.text).to_utf8_buffer(), original.hash, M48RecordTransport.GZIP_VERSION), "M47 receipt cannot use the historical M48 GZIP tag")
	var ordinary: Dictionary = {"ordinary":[1.234567890123456e-200, -0.0, true, "精确"]}
	_check(RecordEncoding.pack(ordinary) == RecordEncoding.pack_v1(ordinary),
		"ordinary dictionaries and economy source actions retain original V1 bytes")
	var fake: Dictionary = {"base":receipt.base}
	var fake_v1: Dictionary = RecordEncoding.pack_v1(fake)
	_reject(_wrap(String(fake_v1.text).to_utf8_buffer(), fake_v1.hash), "coincidental M48 base markers do not make a receipt")
	_reject(_wrap(String(fake_v1.text).to_utf8_buffer(), fake_v1.hash, M48RecordTransport.GZIP_VERSION), "coincidental M48 base markers do not make a GZIP receipt")


func _negative_cases(receipt: Dictionary) -> void:
	for encoding: String in [M48RecordTransport.GZIP_VERSION, M48RecordTransport.VERSION]:
		_negative_encoding(receipt, encoding)


func _negative_encoding(receipt: Dictionary, encoding: String) -> void:
	_stage("negative begin " + encoding)
	var original: Dictionary = RecordEncoding.pack_v1(receipt)
	var packed: Dictionary = M48RecordTransport.pack(receipt, original, encoding)
	_check(not packed.is_empty(), "negative fixture has a valid " + encoding + " writer packet")
	if packed.is_empty(): return
	var good: Dictionary = JSON.parse_string(packed.text)
	var bad: Dictionary = good.duplicate(true)
	bad.record_encoding = "BH_M48_GZIP_EXACT_JSON_V999"
	_reject(bad, "unknown transport version")
	bad = good.duplicate(true)
	bad.extra = true
	_reject(bad, "unexpected transport field")
	for key: String in M48RecordTransport.KEYS:
		bad = good.duplicate(true)
		bad.erase(key)
		_reject(bad, "missing transport field " + key)
	for key: String in ["sha256", "compressed_sha256"]:
		bad = good.duplicate(true)
		bad[key] = "0".repeat(64)
		_reject(bad, "changed " + key)
		bad[key] = "A".repeat(64)
		_reject(bad, "noncanonical " + key)
	for key: String in ["unpacked_bytes", "compressed_bytes"]:
		for value: Variant in [-1, 0, 1.5, M48RecordTransport.MAX_UNPACKED_BYTES + 1, "128", null]:
			bad = good.duplicate(true)
			bad[key] = value
			_reject(bad, "invalid " + key + ":" + str(value))
		bad = good.duplicate(true)
		bad[key] += 1
		_reject(bad, "mismatched " + key)
	bad = good.duplicate(true)
	bad.data = "!" + String(bad.data).substr(1)
	_reject(bad, "invalid base64 alphabet")
	bad = good.duplicate(true)
	bad.data = "=" + String(bad.data).substr(1)
	_reject(bad, "base64 padding in the middle")
	bad = good.duplicate(true)
	bad.data = String(bad.data).left(String(bad.data).length() - 4)
	_reject(bad, "base64 EOF")
	if encoding == M48RecordTransport.GZIP_VERSION:
		var gzip: PackedByteArray = Marshalls.base64_to_raw(good.data)
		var bytes: PackedByteArray = gzip.duplicate()
		bytes[bytes.size() / 2] ^= 1
		bad = good.duplicate(true)
		bad.data = Marshalls.raw_to_base64(bytes)
		_reject(bad, "modified deflate bytes fail the compressed digest")
		bytes = gzip.duplicate()
		bytes[bytes.size() - 8] ^= 1
		bad = good.duplicate(true)
		bad.data = Marshalls.raw_to_base64(bytes)
		_reject(bad, "modified CRC trailer fails the compressed digest")
		bytes = gzip.slice(0, gzip.size() - 4)
		_reject(_replace_gzip(good, bytes), "GZIP footer EOF even with a matching compressed digest")
		bytes = gzip.duplicate()
		bytes[3] = 4
		_reject(_replace_gzip(good, bytes), "GZIP optional flags even with matching compressed digest")
		bytes = gzip.duplicate()
		bytes[4] ^= 1
		_reject(_replace_gzip(good, bytes), "noncanonical valid GZIP header timestamp")
		bytes = gzip.duplicate()
		bytes.append_array(gzip.slice(gzip.size() - 4))
		_reject(_replace_gzip(good, bytes), "trailing bytes with a plausible final ISIZE")
		bytes = gzip.duplicate()
		bytes.append_array(gzip)
		_reject(_replace_gzip(good, bytes), "a second GZIP member cannot become a hidden receipt")
	else:
		_zstd_negative_cases(good)
	_reject(_wrap(String(packed.text).to_utf8_buffer(), original.hash, encoding), "nested compressed record is forbidden")
	_reject(_wrap("{}".to_utf8_buffer(), original.hash, encoding), "inner record requires original V1")
	_reject(_wrap((String(original.text) + "\n").to_utf8_buffer(), original.hash, encoding), "noncanonical inner packet whitespace")
	var inner: Dictionary = JSON.parse_string(original.text)
	inner.sha256 = "0".repeat(64)
	_reject(_wrap(JSON.stringify(inner, "", true, true).to_utf8_buffer(), original.hash, encoding), "inner V1 hash is independently checked")
	var oversized: String = "x".repeat(M48RecordTransport.MAX_UNPACKED_BYTES + 1)
	_stage("negative oversized fixture constructed")
	_reject(_wrap(oversized.to_utf8_buffer(), original.hash, encoding), "high-ratio oversized output is rejected before decompression")
	_check(M48RecordTransport.pack(receipt, {"text":oversized,"hash":original.hash}, encoding).is_empty(),
		"writer rejects an oversized canonical packet without increasing the bound")


func _zstd_negative_cases(good: Dictionary) -> void:
	var zstd: PackedByteArray = Marshalls.base64_to_raw(good.data)
	var bytes: PackedByteArray = zstd.duplicate()
	bytes[bytes.size() / 2] ^= 1
	var bad: Dictionary = good.duplicate(true)
	bad.data = Marshalls.raw_to_base64(bytes)
	_reject(bad, "modified ZSTD bytes fail the compressed digest")
	bytes = zstd.duplicate()
	bytes[0] ^= 1
	_reject(_replace_gzip(good, bytes), "ZSTD magic with a matching transport digest")
	bytes = zstd.duplicate()
	bytes[4] |= 8
	_reject(_replace_gzip(good, bytes), "ZSTD reserved frame bit")
	bytes = zstd.duplicate()
	bytes[4] |= 4
	_reject(_replace_gzip(good, bytes), "noncanonical ZSTD checksum flag")
	bytes = zstd.duplicate()
	bytes[4] |= 1
	_reject(_replace_gzip(good, bytes), "ZSTD dictionary frame is forbidden")
	var descriptor: int = zstd[4]
	var size_offset: int = 5 + (0 if (descriptor & 0x20) != 0 else 1)
	bytes = zstd.duplicate()
	bytes[size_offset] ^= 1
	_reject(_replace_gzip(good, bytes), "ZSTD declared content size mismatch")
	var size_flag: int = descriptor >> 6
	var content_size_bytes: int = (1 if (descriptor & 0x20) != 0 else 0) if size_flag == 0 else [0,2,4,8][size_flag]
	var block_offset: int = size_offset + content_size_bytes
	bytes = zstd.slice(0, block_offset - 1)
	_reject(_replace_gzip(good, bytes), "ZSTD header EOF")
	bytes = zstd.slice(0, zstd.size() - 1)
	_reject(_replace_gzip(good, bytes), "ZSTD final block EOF")
	bytes = zstd.duplicate()
	bytes[block_offset] = (int(bytes[block_offset]) & 0xf9) | 6
	_reject(_replace_gzip(good, bytes), "ZSTD reserved block type")
	bytes = zstd.duplicate()
	bytes.append(0)
	_reject(_replace_gzip(good, bytes), "ZSTD trailing byte")
	bytes = zstd.duplicate()
	bytes.append_array(zstd)
	_reject(_replace_gzip(good, bytes), "ZSTD second frame")
	bytes = zstd.duplicate()
	bytes.append_array(PackedByteArray([0x50,0x2a,0x4d,0x18,0,0,0,0]))
	_reject(_replace_gzip(good, bytes), "ZSTD trailing skippable frame")


func _business_case(receipt: Dictionary) -> void:
	var invalid: Dictionary = receipt.duplicate(true)
	invalid.base.cash = -1
	var packed: Dictionary = RecordEncoding.pack(invalid)
	_check(not packed.is_empty(), "transport routing does not claim to authenticate business values")
	if packed.is_empty(): return
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(packed.text))
	_check(decoded.error == OK and not TransactionReceipt.problem(decoded.payload).is_empty(),
		"a correctly hashed invalid business value remains rejected by the complete receipt validator")
	var path: String = output.path_join("invalid-business-record.json")
	_write(path, packed.text)
	_check(ReceiptJournal.new(output)._read_record(path).error != OK,
		"the production journal cannot accept a recompressed rehashed invalid business value")


func _cache_case(journal: ReceiptJournal) -> void:
	var path: String = journal.directory.path_join("00000001/record.json")
	var content: String = FileAccess.get_file_as_string(path)
	var outer: Dictionary = JSON.parse_string(content)
	ReceiptJournal._record_cache.clear()
	ReceiptJournal._cached_bytes = 0
	var record: Dictionary = journal._read_record(path)
	_check(record.error == OK and record.bytes == content.to_utf8_buffer().size(),
		"journal bytes continue to report actual physical file bytes")
	if record.error != OK: return
	var cached: Dictionary = ReceiptJournal._record_cache.get(record.raw_identity, {})
	var prefix: Dictionary = journal._prefix_snapshot()
	var aliases: bool = false
	for original: PackedByteArray in prefix.get("raw_records", []):
		if is_same(cached.raw, original) and cached.raw == original: aliases = true
	var expected: int = (0 if cached.raw_shared else int(record.bytes)) + cached.get("dto", PackedByteArray()).size() + ReceiptJournal.CACHE_METADATA_BYTES
	_check(outer.get("record_encoding") == M48RecordTransport.VERSION and cached.has("dto")
		and cached.raw_shared and aliases
		and ReceiptJournal._cached_bytes == expected and ReceiptJournal._cached_bytes <= ReceiptJournal.MAX_CACHED_BYTES,
		"native DTO budget counts true prefix raw aliases once and charges DTO plus explicit metadata within its old budget")


func _mixed_case(transaction: RunTransaction, head: Dictionary) -> void:
	var journal: ReceiptJournal = transaction._journal
	var path: String = journal.directory.path_join("00000001/record.json")
	# Representation-only fixture: semantic receipt, hash and binding remain identical.
	_write(path, RecordEncoding.pack_v1(head.receipt).text)
	var old: Dictionary = journal.read_all()
	_check(old.error == OK and old.hash == head.hash, "original V1 representation retains the exact registered chain hash")
	var before: Dictionary = TransactionReceipt.camp(head.receipt)
	var identity: String = before.profile_id + ":edit:" + RunSave.new_profile_id()
	var ready: Dictionary = transaction.prepare_edit(head.hash, identity, {"kind":"rename", "member_id":1, "value":"混合传输验收"})
	var committed: Dictionary = transaction.commit_edit(identity) if ready.error == OK else ready
	_check(committed.error == OK, "normal edit and commit append compressed receipts after an original V1 prefix")
	if committed.error == OK:
		var gzip_path: String = journal.directory.path_join("00000002/record.json")
		var middle: Dictionary = RecordEncoding.unpack(JSON.parse_string(FileAccess.get_file_as_string(gzip_path)))
		if middle.error == OK:
			_write(gzip_path, M48RecordTransport.pack(middle.payload, RecordEncoding.pack_v1(middle.payload), M48RecordTransport.GZIP_VERSION).text)
	var final: Dictionary = ReceiptJournal.new(journal.directory).read_all()
	_check(final.error == OK and final.receipt.phase == "EDIT_COMMITTED" and final.receipt.revision == 3,
		"fresh journal reader authenticates the complete mixed V1, GZIP and ZSTD chain")
	if final.error == OK:
		for revision: int in range(1, int(final.receipt.revision) + 1):
			var record_path: String = journal.directory.path_join("%08d/record.json" % revision)
			var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(record_path))
			_check(packet.record_encoding == [RecordEncoding.VERSION, M48RecordTransport.GZIP_VERSION, M48RecordTransport.VERSION][revision - 1],
				"mixed chain generation %d has its expected explicit transport version" % revision)


func _real_receipt(path: String, isolated: String) -> void:
	_check(path.is_absolute_path() and path.replace("\\", "/").begins_with(isolated), "supplied receipt belongs to isolated evidence")
	if not path.is_absolute_path() or not path.replace("\\", "/").begins_with(isolated): return
	var source_hash: String = FileAccess.get_sha256(path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "real complete receipt source parses: " + path)
	if not parsed is Dictionary: return
	var decoded: Dictionary = RecordEncoding.unpack(parsed)
	_check(decoded.error == OK, "real complete receipt source exact-decodes: " + path)
	if decoded.error != OK: return
	_roundtrip(decoded.payload, "read-only:" + path)
	var partial: bool = decoded.payload.get("phase") == "SUSPEND_READY" and _partial(decoded.payload.get("envelope", {}))
	saw_partial = saw_partial or partial
	samples.append({"source":path, "source_sha256":source_hash, "phase":decoded.payload.get("phase"), "partial_reload":partial})
	_check(FileAccess.get_sha256(path) == source_hash, "supplied real receipt bytes remain unchanged")


func _partial(value: Variant) -> bool:
	if value is Dictionary:
		if value.get("reloading") == true and SurvivalContracts.number(value.get("remaining")) and value.remaining > 0.0:
			return true
		for child: Variant in value.values():
			if _partial(child): return true
	elif value is Array:
		for child: Variant in value:
			if _partial(child): return true
	return false


func _reject(record: Dictionary, label: String) -> void:
	_stage("reject begin " + label)
	var result: Dictionary = RecordEncoding.unpack(record)
	_stage("reject returned " + label + ":" + str(result.get("error")) + ":" + str(result.get("reason", "")))
	_check(result.get("error") != OK, "reject " + label)


func _wrap(raw: PackedByteArray, semantic_hash: String, encoding: String = M48RecordTransport.VERSION) -> Dictionary:
	var gzip: PackedByteArray = raw.compress(M48RecordTransport._mode(encoding))
	return {"record_encoding":encoding, "sha256":semantic_hash, "unpacked_bytes":raw.size(),
		"compressed_bytes":gzip.size(), "compressed_sha256":M48RecordTransport._bytes_hash(gzip), "data":Marshalls.raw_to_base64(gzip)}


func _replace_gzip(record: Dictionary, gzip: PackedByteArray) -> Dictionary:
	var result: Dictionary = record.duplicate(true)
	result.data = Marshalls.raw_to_base64(gzip)
	result.compressed_bytes = gzip.size()
	result.compressed_sha256 = M48RecordTransport._bytes_hash(gzip)
	return result


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
