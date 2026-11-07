class_name RecordEncoding
extends RefCounted
## Versioned journal transport: no JSON numeric conversion at the storage boundary.

const VERSION: String = "BH_EXACT_JSON_V1"


static func fingerprint(value: Dictionary) -> String:
	var stamp: int = FreezeProfile.enter("exact.fingerprint")
	var result: String = _profiled_fingerprint(value)
	FreezeProfile.leave("exact.fingerprint", stamp)
	return result


static func _profiled_fingerprint(value: Dictionary) -> String:
	var proof: Dictionary=ValueProofCache.lookup("exact-fingerprint",value)
	if proof.hit:
		return proof.result
	if not SurvivalContracts.json_value(value, -2):
		return ""
	var digest: String=_digest(_encode(value))
	ValueProofCache.remember(proof,digest)
	return digest


static func stringify(value: Dictionary) -> String:
	return pack(value).get("text", "")


static func pack(value: Dictionary) -> Dictionary:
	var stamp: int = FreezeProfile.enter("exact.stringify")
	var result: Dictionary = _profiled_pack(value)
	FreezeProfile.leave("exact.stringify", stamp)
	return result


static func _profiled_pack(value: Dictionary) -> Dictionary:
	var proof: Dictionary=ValueProofCache.lookup("exact-stringify",value)
	if proof.hit:
		return proof.result
	if not SurvivalContracts.json_value(value, -2):
		return {}
	var payload: String = JSON.stringify(_encode(value), "", true, true)
	var digest: String = (VERSION + "\n" + payload).sha256_text()
	# Preserve the existing sorted envelope while using the same canonical payload for both outputs.
	var result: Dictionary = {"hash":digest, "text":"{\"payload\":%s,\"record_encoding\":\"%s\",\"sha256\":\"%s\"}\n" % [payload, VERSION, digest]}
	ValueProofCache.remember(proof,result)
	return result


static func unpack(record: Dictionary) -> Dictionary:
	var stamp: int = FreezeProfile.enter("exact.unpack")
	var result: Dictionary = _profiled_unpack(record)
	FreezeProfile.leave("exact.unpack", stamp)
	return result


static func _profiled_unpack(record: Dictionary) -> Dictionary:
	if record.size() != 3 or record.get("record_encoding") != VERSION or not record.get("sha256") is String:
		return {"error":ERR_FILE_CORRUPT, "reason":"RECORD_ENCODING"}
	var decoded: Dictionary = _decode(record.get("payload"), -2)
	if not decoded.ok or not decoded.value is Dictionary:
		return {"error":ERR_FILE_CORRUPT, "reason":"RECORD_ENCODING_VALUE"}
	if _digest(record.payload) != record.sha256:
		return {"error":ERR_FILE_CORRUPT, "reason":"RECORD_HASH"}
	return {"error":OK, "payload":decoded.value, "hash":record.sha256}


static func _digest(encoded: Array) -> String:
	return (VERSION + "\n" + JSON.stringify(encoded, "", true, true)).sha256_text()


static func _number_hex(value: float) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	# JSON business values have always treated int/float and both zero signs equally.
	bytes.encode_double(0, 0.0 if value == 0.0 else value)
	return bytes.hex_encode()


static func _encode(value: Variant) -> Array:
	if value == null:
		return ["null"]
	if value is bool:
		return ["bool", value]
	if value is String or value is StringName:
		return ["string", String(value)]
	if value is int or value is float:
		return ["number", _number_hex(float(value))]
	var rows: Array = []
	if value is Array:
		for item: Variant in value:
			rows.append(_encode(item))
		return ["array", rows]
	var keys: Array[String] = []
	for key: Variant in value:
		keys.append(String(key))
	keys.sort()
	for key: String in keys:
		rows.append([key, _encode(value[key])])
	return ["object", rows]


static func _decode(encoded: Variant, depth: int) -> Dictionary:
	var invalid: Dictionary = {"ok":false, "value":null}
	if depth > 64 or not encoded is Array or encoded.is_empty() or not encoded[0] is String:
		return invalid
	var tag: String = encoded[0]
	if tag == "null":
		return {"ok":true, "value":null} if encoded.size() == 1 else invalid
	if encoded.size() != 2:
		return invalid
	var value: Variant = encoded[1]
	if tag == "bool" or tag == "string":
		return {"ok":true, "value":value} if (value is bool if tag == "bool" else value is String) else invalid
	if tag == "number":
		if not value is String or value.length() != 16 or not value.is_valid_hex_number(false) or value != value.to_lower():
			return invalid
		var number: float = value.hex_decode().decode_double(0)
		return {"ok":true, "value":number} if is_finite(number) and _number_hex(number) == value else invalid
	if tag not in ["array", "object"] or not value is Array:
		return invalid
	var items: Array = []
	var object: Dictionary = {}
	var previous: String = ""
	for item: Variant in value:
		if tag == "object":
			if not item is Array or item.size() != 2 or not item[0] is String or (not object.is_empty() and item[0] <= previous):
				return invalid
			previous = item[0]
		var child: Dictionary = _decode(item[1] if tag == "object" else item, depth + 1)
		if not child.ok:
			return invalid
		if tag == "object":
			object[item[0]] = child.value
		else:
			items.append(child.value)
	return {"ok":true, "value":object if tag == "object" else items}
