extends SceneTree
## Lossless source transport fixtures. Optional real camp checks never write a profile.

var checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _run() -> void:
	var action: Dictionary = {"version":9, "id":"synthetic-only", "economy_source":{"version":1}, "tiny":1.234567890123456e-200, "nested":{"values":[0, -0.0, 1.23456789012345, true, "源字段"]}}
	var original: String = RecordEncoding.fingerprint(action)
	var packed: Dictionary = EconomyBuildV1.compact_action(action)
	_check(packed.get("encoding") == EconomyBuildV1.SOURCE_ENCODING, "new sources use an explicit compact encoding")
	_check(int(packed.get("unpacked_bytes", 0)) <= RunSave.MAX_BYTES, "uncompressed source bound uses existing save limit")
	var roundtrip: Dictionary = EconomyBuildV1.source_action({"action":packed})
	_check(RecordEncoding.fingerprint(roundtrip) == original and TransactionReceipt.same(roundtrip, action), "gzip and ExactJSON preserve the full source fingerprint including tiny binary64")
	var disk_encoded: Dictionary = JSON.parse_string(JSON.stringify({"action":packed}, "", true, true))
	_check(RecordEncoding.fingerprint(EconomyBuildV1.source_action(disk_encoded)) == original, "ordinary camp JSON numeric conversion preserves compact metadata")
	_check(RecordEncoding.fingerprint(EconomyBuildV1.source_action({"action":action})) == original, "unpublished raw debug sources remain explicitly readable")
	var raw_ledger: Dictionary = EconomyBuildV1.initial()
	raw_ledger.sources = [{"action":action, "sortie":1, "transaction_id":"fixture:1", "completed":[]}]
	var compact_ledger: Dictionary = raw_ledger.duplicate(true)
	compact_ledger.sources[0].action = packed
	_check(TransactionReceipt.same(EconomyBuildV1.source_comparison(raw_ledger), EconomyBuildV1.source_comparison(compact_ledger)), "full-source receipt comparison accepts lossless raw and compact representations")
	roundtrip.id = "mutated-return"
	_check(EconomyBuildV1.source_action({"action":packed}).id == action.id, "decoded cache does not expose its private source object")
	var variants: Dictionary = {}
	var bad: Dictionary = packed.duplicate(true)
	bad.encoding = "unknown"
	variants["unknown encoding"] = bad
	bad = packed.duplicate(true)
	bad.sha256 = "0".repeat(64)
	variants["unpacked digest"] = bad
	bad = packed.duplicate(true)
	bad.compressed_sha256 = "0".repeat(64)
	variants["compressed digest"] = bad
	bad = packed.duplicate(true)
	bad.unpacked_bytes += 1
	variants["declared output length"] = bad
	bad = packed.duplicate(true)
	bad.unpacked_bytes = RunSave.MAX_BYTES + 1
	variants["oversized output"] = bad
	bad = packed.duplicate(true)
	bad.compressed_bytes += 1
	variants["declared compressed length"] = bad
	bad = packed.duplicate(true)
	bad.data = "!" + String(bad.data).substr(1)
	variants["invalid base64"] = bad
	bad = packed.duplicate(true)
	bad.data = String(bad.data).left(String(bad.data).length() - 4)
	variants["truncated transport"] = bad
	bad = packed.duplicate(true)
	var compressed: PackedByteArray = Marshalls.base64_to_raw(bad.data)
	compressed[compressed.size() / 2] ^= 1
	bad.data = Marshalls.raw_to_base64(compressed)
	variants["corrupted gzip bytes"] = bad
	bad = packed.duplicate(true)
	compressed = Marshalls.base64_to_raw(bad.data)
	compressed[0] = 0
	bad.data = Marshalls.raw_to_base64(compressed)
	bad.compressed_sha256 = EconomyBuildV1._source_bytes_hash(compressed)
	variants["invalid gzip header with matching transport hash"] = bad
	var original_gzip: PackedByteArray = Marshalls.base64_to_raw(packed.data)
	for label: String in ["gzip trailing bytes with plausible ISIZE", "gzip second member"]:
		bad = packed.duplicate(true)
		compressed = original_gzip.duplicate()
		compressed.append_array(original_gzip.slice(original_gzip.size() - 4) if label.contains("trailing") else original_gzip)
		bad.data = Marshalls.raw_to_base64(compressed)
		bad.compressed_bytes = compressed.size()
		bad.compressed_sha256 = EconomyBuildV1._source_bytes_hash(compressed)
		variants[label] = bad
	variants["missing ExactJSON envelope"] = _text_transport("{}")
	var inner: Dictionary = JSON.parse_string(RecordEncoding.stringify(action))
	inner.sha256 = "0".repeat(64)
	variants["inner ExactJSON digest"] = _text_transport(JSON.stringify(inner))
	bad = packed.duplicate(true)
	bad.extra = true
	variants["unexpected metadata"] = bad
	for label: String in variants:
		_check(EconomyBuildV1.source_action({"action":variants[label]}).is_empty(), "reject " + label)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--codec-camp="):
			_real_camp(arg.trim_prefix("--codec-camp="))
	print("M48_SOURCE_CODEC " + JSON.stringify({"checks":checks, "failures":failures, "samples":samples}))
	quit(0 if failures.is_empty() else 1)

func _text_transport(text: String) -> Dictionary:
	var raw: PackedByteArray = text.to_utf8_buffer()
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)
	return {"encoding":EconomyBuildV1.SOURCE_ENCODING, "sha256":text.sha256_text(), "unpacked_bytes":raw.size(), "compressed_sha256":EconomyBuildV1._source_bytes_hash(compressed), "compressed_bytes":compressed.size(), "data":Marshalls.raw_to_base64(compressed)}

func _real_camp(path: String) -> void:
	_check(path.is_absolute_path() and "/.local/" in path, "real codec sample uses an isolated artifact")
	if not path.is_absolute_path() or "/.local/" not in path: return
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		_check(false, "real isolated camp JSON decodes")
		return
	var camp: Dictionary = parser.data
	for source: Dictionary in EconomyBuildV1.state(camp).get("sources", []):
		var action: Dictionary = EconomyBuildV1.source_action(source)
		var started: int = Time.get_ticks_usec()
		var packed: Dictionary = EconomyBuildV1.compact_action(action)
		var decoded: Dictionary = EconomyBuildV1.source_action({"action":packed})
		var elapsed: float = float(Time.get_ticks_usec() - started) / 1000.0
		_check(not packed.is_empty() and RecordEncoding.fingerprint(decoded) == RecordEncoding.fingerprint(action), "real complete action fingerprint survives compaction")
		_check(EconomyActions.problem(decoded, true).is_empty(), "real decoded action still passes the full original source authentication")
		samples.append({"action_id":action.get("id", ""), "original_fingerprint":RecordEncoding.fingerprint(action), "decoded_fingerprint":RecordEncoding.fingerprint(decoded), "unpacked_bytes":packed.get("unpacked_bytes", 0), "compressed_bytes":packed.get("compressed_bytes", 0), "base64_bytes":String(packed.get("data", "")).length(), "encode_decode_ms":elapsed})
