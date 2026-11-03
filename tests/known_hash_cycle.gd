extends SceneTree
## Preserve the legacy counterexample and verify the versioned storage fix.

func _initialize() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cycle-output="):
			output = arg.trim_prefix("--cycle-output=")
	if "/.local/public-checks/" not in output.replace("\\", "/") or FileAccess.file_exists(output):
		quit(2)
		return
	var value: Dictionary = {"x": JSON.parse_string("9.714451465470121e-17")}
	var rows: Array[Dictionary] = []
	for index: int in range(4):
		rows.append({"json": JSON.stringify(value, "", true, true), "fingerprint": TransactionReceipt.legacy_fingerprint(value)})
		value = JSON.parse_string(JSON.stringify(value, "", true, true))
	var control: Dictionary = {"x": 0.0333333333333333}
	var stable: bool = TransactionReceipt.legacy_fingerprint(control) == TransactionReceipt.legacy_fingerprint(JSON.parse_string(JSON.stringify(control, "", true, true)))
	var reproduced: bool = rows[0].fingerprint != rows[1].fingerprint and rows[0].fingerprint == rows[2].fingerprint and rows[1].fingerprint == rows[3].fingerprint
	var exact_hash: String = TransactionReceipt.fingerprint(value)
	var exact_stable: bool = true
	for turn: int in range(10):
		var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(value)))
		exact_stable = exact_stable and decoded.error == OK
		if decoded.error != OK:
			break
		value = decoded.payload
		exact_stable = exact_stable and TransactionReceipt.fingerprint(value) == exact_hash
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"legacy_rows": rows, "legacy_cycle_reproduced": reproduced, "ordinary_control_stable": stable, "exact_record_roundtrip_stable":exact_stable}, "\t"))
	file.close()
	print("MINIMAL_HASH_CYCLE=", reproduced, " control_stable=", stable)
	print("EXACT_RECORD_ROUNDTRIP=", exact_stable)
	quit(0 if reproduced and stable and exact_stable else 1)
