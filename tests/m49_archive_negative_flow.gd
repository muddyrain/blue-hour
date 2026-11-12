extends "res://tests/m49_scale_flow.gd"
## Real distinct archived roots, warmed rejection followed by an independent cold process.

func _measure_archives() -> void:
	var reader: CatalogProgress = CatalogProgress.new(app.progress_session._path)
	var mode: String = _argument("--archive-negative=")
	var proof: Dictionary
	if mode == "swap":
		var folders: Array[String] = _archives()
		_check(folders.size() >= 2 and reader.refresh(Callable()).get("error") == OK, "complete original archive projection warms its pure proofs")
		if folders.size() < 2:
			return
		proof = {"a":folders[0], "b":folders[1], "slot":app.progress_session._path, "pid":OS.get_process_id(),
			"a_binding":FileAccess.get_sha256(folders[0].path_join("binding.json")),
			"b_binding":FileAccess.get_sha256(folders[1].path_join("binding.json"))}
		_check(_swap(proof.a, proof.b), "isolated original directories are exchanged without rewriting a receipt")
		var rejected: Dictionary = reader.refresh(Callable())
		_check(rejected.get("error") != OK, "warmed proofs reject the exchanged real run/root identities")
		proof.warm_reason = rejected.get("reason", "")
		_write("archive-swap-proof.json", proof)
	else:
		var source: String = _argument("--archive-negative-proof=")
		_check(source.is_absolute_path() and "/.local/" in source, "cold negative uses a retained task-local proof")
		proof = JSON.parse_string(FileAccess.get_file_as_string(source))
		_check(proof.slot == app.progress_session._path and int(proof.pid) != OS.get_process_id(), "cold process retains the same original bound slot")
		var rejected: Dictionary = reader.refresh(Callable())
		_check(rejected.get("error") != OK, "independent cold verification also rejects the exchanged archives")
		_check(_swap(proof.a, proof.b), "original directory names are restored without changing the source bytes")
		_check(FileAccess.get_sha256(proof.a.path_join("binding.json")) == proof.a_binding \
			and FileAccess.get_sha256(proof.b.path_join("binding.json")) == proof.b_binding,
			"both original bindings remain byte identical")
		var restored: Dictionary = reader.refresh(Callable())
		_check(restored.get("error") == OK, "restored exact archives fully authenticate again")
		_write("archive-swap-cold-restored.json", {"source_pid":proof.pid, "pid":OS.get_process_id(),
			"warm_reason":proof.warm_reason, "cold_reason":rejected.get("reason", ""), "restored_error":restored.get("error")})


func _swap(a: String, b: String) -> bool:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not a.begins_with(isolated) or not b.begins_with(isolated) or a.get_base_dir() != b.get_base_dir():
		return false
	var temporary: String = a.get_base_dir().path_join("m49-swap-" + RunSave.new_profile_id())
	if DirAccess.rename_absolute(a, temporary) != OK:
		return false
	if DirAccess.rename_absolute(b, a) != OK:
		DirAccess.rename_absolute(temporary, a)
		return false
	if DirAccess.rename_absolute(temporary, b) != OK:
		DirAccess.rename_absolute(a, b)
		DirAccess.rename_absolute(temporary, a)
		return false
	return true
