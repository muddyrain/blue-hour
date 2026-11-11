class_name M48RecordTransport
extends RefCounted
## Lossless M48-only receipt transport. Business, chain, source, and ACK owners remain unchanged.

const GZIP_VERSION: String = "BH_M48_GZIP_EXACT_JSON_V1"
const VERSION: String = "BH_M48_ZSTD_EXACT_JSON_V1"
const MAX_UNPACKED_BYTES: int = 4_194_304 # The original journal single-record bound, never increased.
const KEYS: Array[String] = ["record_encoding", "sha256", "unpacked_bytes", "compressed_bytes", "compressed_sha256", "data"]


static func supported(value: Variant) -> bool:
	return value is String and value in [GZIP_VERSION, VERSION]


static func eligible(value: Dictionary) -> bool:
	# These are transport routing markers, not a substitute for TransactionReceipt.problem.
	if not value.has_all(TransactionReceipt.KEYS) or not SurvivalContracts.integer(value.get("receipt_version"), TransactionReceipt.VERSION, TransactionReceipt.VERSION) \
			or not SurvivalContracts.integer(value.get("revision"), 1, 4096) or value.get("phase") not in TransactionReceipt.PHASES \
			or not value.get("base") is Dictionary or not value.get("rules") is Dictionary or not value.get("envelope") is Dictionary:
		return false
	var base: Dictionary = value.base
	var journey: Variant = base.get("journey")
	if not SurvivalContracts.integer(base.get("schema_version"), 111, 111) or not journey is Dictionary \
			or not journey.get("campaign") is Dictionary or not journey.get("build") is Dictionary:
		return false
	var economy: Variant = journey.campaign.get("economy")
	var progression: Variant = journey.build.get("progression")
	var powers: Variant = journey.build.get("powers")
	return economy is Dictionary and SurvivalContracts.integer(economy.get("version"), 1, 1) \
		and progression is Dictionary and SurvivalContracts.integer(progression.get("version"), 1, 1) \
		and powers is Dictionary and SurvivalContracts.integer(powers.get("version"), 5, 5)


static func pack(value: Dictionary, canonical_v1: Dictionary, encoding: String = VERSION) -> Dictionary:
	if not supported(encoding) or not eligible(value) or not canonical_v1.get("text") is String or not _hash(canonical_v1.get("hash")):
		return {}
	var raw: PackedByteArray = String(canonical_v1.text).to_utf8_buffer()
	if raw.is_empty() or raw.size() > MAX_UNPACKED_BYTES: return {}
	var compressed: PackedByteArray = raw.compress(_mode(encoding))
	if compressed.size() < (18 if encoding == GZIP_VERSION else 9) or compressed.size() > MAX_UNPACKED_BYTES: return {}
	if encoding == VERSION and not zstd_frame(compressed, raw.size()): return {}
	var record: Dictionary = {"record_encoding":encoding, "sha256":canonical_v1.hash,
		"unpacked_bytes":raw.size(), "compressed_bytes":compressed.size(),
		"compressed_sha256":_bytes_hash(compressed), "data":Marshalls.raw_to_base64(compressed)}
	var text: String = JSON.stringify(record, "", true, true) + "\n"
	if text.to_utf8_buffer().size() > MAX_UNPACKED_BYTES: return {}
	return {"hash":canonical_v1.hash, "text":text}


static func unpack(record: Dictionary) -> Dictionary:
	var stamp: int = FreezeProfile.enter("m48_transport.unpack")
	var result: Dictionary = _unpack(record)
	FreezeProfile.leave("m48_transport.unpack", stamp)
	return result


static func _unpack(record: Dictionary) -> Dictionary:
	if record.size() != KEYS.size() or not record.has_all(KEYS) or not supported(record.get("record_encoding")) \
			or not _hash(record.get("sha256")) or not _hash(record.get("compressed_sha256")) \
			or not SurvivalContracts.integer(record.get("unpacked_bytes"), 1, MAX_UNPACKED_BYTES) \
			or not SurvivalContracts.integer(record.get("compressed_bytes"), 9, MAX_UNPACKED_BYTES) \
			or not record.get("data") is String:
		return _reject("M48_RECORD_FIELDS")
	var encoded: String = record.data
	if encoded.length() != 4 * ceili(float(record.compressed_bytes) / 3.0) or not _base64(encoded):
		return _reject("M48_RECORD_BASE64")
	var compressed: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if compressed.size() != int(record.compressed_bytes) or Marshalls.raw_to_base64(compressed) != encoded \
			or _bytes_hash(compressed) != record.compressed_sha256:
		return _reject("M48_RECORD_COMPRESSED_HASH")
	var encoding: String = record.record_encoding
	if encoding == GZIP_VERSION:
		# The fixed engine emits one GZIP member with no optional header sections.
		if compressed.size() < 18 or compressed[0] != 0x1f or compressed[1] != 0x8b or compressed[2] != 8 or compressed[3] != 0 \
				or compressed.decode_u32(compressed.size() - 4) != int(record.unpacked_bytes):
			return _reject("M48_RECORD_GZIP_HEADER_OR_LENGTH")
	elif not zstd_frame(compressed, int(record.unpacked_bytes)):
		return _reject("M48_RECORD_ZSTD_FRAME_OR_LENGTH")
	# Fixed output avoids the engine dynamic inflater's STREAM_END loop on suffixes.
	# The declared allocation has already been bounded and checked against frame content size.
	var raw: PackedByteArray = compressed.decompress(int(record.unpacked_bytes), _mode(encoding))
	if raw.size() != int(record.unpacked_bytes): return _reject("M48_RECORD_DECOMPRESSED_LENGTH")
	# Recompression binds every header/block/trailer byte to the fixed engine writer.
	if raw.compress(_mode(encoding)) != compressed: return _reject("M48_RECORD_COMPRESSED_CANONICAL")
	var text: String = raw.get_string_from_utf8()
	if text.to_utf8_buffer() != raw: return _reject("M48_RECORD_UTF8")
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return _reject("M48_RECORD_INNER_JSON")
	var inner: Dictionary = parser.data
	if inner.get("record_encoding") != RecordEncoding.VERSION: return _reject("M48_RECORD_INNER_V1_REQUIRED")
	var decoded: Dictionary = RecordEncoding.unpack_v1(inner)
	if decoded.get("error") != OK: return decoded
	if decoded.hash != record.sha256: return _reject("M48_RECORD_SEMANTIC_HASH")
	if not eligible(decoded.payload): return _reject("M48_RECORD_RECEIPT_REQUIRED")
	var canonical: Dictionary = RecordEncoding.pack_v1(decoded.payload)
	if canonical.get("text") != text or canonical.get("hash") != record.sha256: return _reject("M48_RECORD_INNER_CANONICAL")
	# Callers still apply their original complete receipt, transition, and source validation.
	return decoded


static func _mode(encoding: String) -> int:
	return FileAccess.COMPRESSION_GZIP if encoding == GZIP_VERSION else FileAccess.COMPRESSION_ZSTD


static func zstd_frame(bytes: PackedByteArray, unpacked_bytes: int) -> bool:
	# Canonical fixed-writer ZSTD: one frame, explicit content size, no dictionary or
	# checksum. Parse its bounded header and all block extents before native inflate.
	if bytes.size() < 9 or bytes.decode_u32(0) != 0xfd2fb528: return false
	var descriptor: int = bytes[4]
	if (descriptor & 0x1f) != 0: return false # reserved/unused bits, checksum and dictionary flags
	var single: bool = (descriptor & 0x20) != 0
	var cursor: int = 5
	var window_bytes: int = unpacked_bytes
	if not single:
		if cursor >= bytes.size(): return false
		var window_descriptor: int = bytes[cursor]
		cursor += 1
		var window_base: int = 1 << (10 + (window_descriptor >> 3))
		window_bytes = window_base + (window_base / 8) * (window_descriptor & 7)
		if window_bytes > MAX_UNPACKED_BYTES: return false
	var size_flag: int = descriptor >> 6
	var size_bytes: int = (1 if single else 0) if size_flag == 0 else [0, 2, 4, 8][size_flag]
	if size_bytes == 0 or cursor + size_bytes > bytes.size(): return false
	var content_bytes: int = 0
	match size_bytes:
		1: content_bytes = bytes[cursor]
		2: content_bytes = bytes.decode_u16(cursor) + 256
		4: content_bytes = bytes.decode_u32(cursor)
		8:
			if bytes.decode_u32(cursor + 4) != 0: return false
			content_bytes = bytes.decode_u32(cursor)
	if content_bytes != unpacked_bytes: return false
	cursor += size_bytes
	var known_output: int = 0
	var compressed_blocks: bool = false
	while cursor + 3 <= bytes.size():
		var block: int = int(bytes[cursor]) | (int(bytes[cursor + 1]) << 8) | (int(bytes[cursor + 2]) << 16)
		cursor += 3
		var kind: int = (block >> 1) & 3
		var size: int = block >> 3
		if kind == 3 or size > mini(131_072, window_bytes): return false
		var stored_size: int = 1 if kind == 1 else size
		if cursor + stored_size > bytes.size(): return false
		if kind != 2:
			known_output += size
			if known_output > unpacked_bytes: return false
		else:
			if size < 2: return false
			compressed_blocks = true
		cursor += stored_size
		if (block & 1) != 0: return cursor == bytes.size() and (compressed_blocks or known_output == unpacked_bytes)
	return false


static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false) and value == value.to_lower()


static func _base64(value: String) -> bool:
	if value.is_empty() or value.length() % 4 != 0: return false
	var ending: int = value.length()
	var padding: int = 0
	while ending > 0 and value.unicode_at(ending - 1) == 61:
		ending -= 1
		padding += 1
	if padding > 2: return false
	for index: int in range(ending):
		var code: int = value.unicode_at(index)
		if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 43 or code == 47): return false
	return true


static func _bytes_hash(value: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


static func _reject(reason: String) -> Dictionary:
	return {"error":ERR_FILE_CORRUPT, "reason":reason}
