extends SceneTree
## Minimal diagnostic for the inherited hash-cycle refusal; a reproducer, not a fix.

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
		rows.append({"json": JSON.stringify(value, "", true, true), "fingerprint": TransactionReceipt.fingerprint(value)})
		value = JSON.parse_string(JSON.stringify(value, "", true, true))
	var control: Dictionary = {"x": 0.0333333333333333}
	var stable: bool = TransactionReceipt.fingerprint(control) == TransactionReceipt.fingerprint(JSON.parse_string(JSON.stringify(control, "", true, true)))
	var reproduced: bool = rows[0].fingerprint != rows[1].fingerprint and rows[0].fingerprint == rows[2].fingerprint and rows[1].fingerprint == rows[3].fingerprint
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "single_float_cycle_reproduced": reproduced, "ordinary_control_stable": stable}, "\t"))
	file.close()
	print("MINIMAL_HASH_CYCLE=", reproduced, " control_stable=", stable)
	quit(1 if reproduced else 0)
