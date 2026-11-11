extends SceneTree
## Read-only same-byte journal timing. Never modifies the original profile.
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var folder: String = ""
	var source: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--flow-output="): folder = argument.trim_prefix("--flow-output=")
		if argument.begins_with("--journal="): source = argument.trim_prefix("--journal=")
	var local: String = ProjectSettings.globalize_path("res://.local/")
	assert(folder.begins_with(local) and source.begins_with(local))
	DirAccess.make_dir_recursive_absolute(folder)
	assert(not "--probe-before" in OS.get_cmdline_user_args(), "Historical baseline needs its recorded source snapshot; this runner measures current code only")
	var journal: ReceiptJournal = ReceiptJournal.new(source)
	var checks: Array[Dictionary] = []
	var failed: int = 0
	for index: int in range(2):
		FreezeProfile.enabled = true
		FreezeProfile.start({"scope":"READ_ONLY_REAL_JOURNAL","iteration":index})
		var began: int = Time.get_ticks_usec()
		var result: Dictionary = journal.read_all()
		var elapsed: int = Time.get_ticks_usec()-began
		FreezeProfile.finish()
		var row: Dictionary = {"wall_usec":elapsed,"error":result.error,"hash":result.get("hash",""),"bytes":result.get("bytes",0),"profile":FreezeProfile.latest}
		var file: FileAccess = FileAccess.open(folder.path_join("read-%d.json" % index),FileAccess.WRITE)
		file.store_string(JSON.stringify(row,"\t"))
		file.close()
		checks.append({"ok":result.error == OK,"label":"complete real journal read %d" % index})
		if result.error != OK: failed += 1
		print("JOURNAL_TIMING ",index," ",elapsed," ",result.get("bytes",0)," ",JSON.stringify(FreezeProfile.latest.metadata))
	var report: FileAccess = FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"pid":OS.get_process_id(),"failures":failed,"checks":checks}))
	report.close()
	quit(failed)
