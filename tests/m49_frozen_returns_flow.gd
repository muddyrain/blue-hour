extends "res://tests/m49_comparison_flow.gd"
## Retain the actual RESULT_READY bytes before the ordinary native confirmation.

func _measure_native(operation: String, button: BaseButton, complete: Callable) -> Dictionary:
	if operation == "return":
		var ready: Dictionary = app.progress_session.inspect()
		_check(ready.error == OK and ready.receipt.phase == "RESULT_READY", "frozen return source is the real authoritative ready receipt")
		var profile: String = OS.get_environment("APPDATA").replace("\\", "/").get_base_dir()
		var snapshot: String = output.path_join("pre-return-profile")
		_check("/.local/m49/" in profile and _copy_tree(profile, snapshot), "complete immutable return source is retained before confirmation")
		_write("pre-return-binding.json", {"original_profile":profile, "slot":app.progress_path,
			"ready_hash":ready.hash, "revision":ready.receipt.revision, "pid":OS.get_process_id()})
		var file: FileAccess = FileAccess.open(output.path_join("pre-return-expected.json"), FileAccess.WRITE)
		file.store_string(RecordEncoding.stringify({"camp":ready.receipt.envelope.result.camp, "ready_hash":ready.hash}))
		file.close()
	return await super._measure_native(operation, button, complete)


func _copy_tree(source: String, target: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return false
	for name: String in DirAccess.get_files_at(source):
		var from: String = source.path_join(name)
		var to: String = target.path_join(name)
		if DirAccess.copy_absolute(from, to) != OK or FileAccess.get_sha256(from) != FileAccess.get_sha256(to):
			return false
	for name: String in DirAccess.get_directories_at(source):
		# Open diagnostic logs are not save authority and cannot be a stable snapshot.
		if name != "logs" and not _copy_tree(source.path_join(name), target.path_join(name)):
			return false
	return true
