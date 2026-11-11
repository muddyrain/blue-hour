extends SceneTree
## Same-process memo comparison, NOT an old-binary performance comparison.
## The copied immutable history is read only; its original binding determines the catalog slot identity.

var output: String = ""
var folder: String = ""
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--catalog-history="): folder = arg.trim_prefix("--catalog-history=")
		if arg.begins_with("--catalog-output="): output = arg.trim_prefix("--catalog-output=")
	folder = folder.replace("\\", "/").simplify_path()
	output = output.replace("\\", "/").simplify_path()
	if not folder.is_absolute_path() or "/.local/" not in folder or not output.is_absolute_path() or "/.local/" not in output or DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var binding: Dictionary = RunTransaction.read_binding(folder.path_join("binding.json"))
	_check(binding.get("error") == OK, "copied original binding authenticates")
	if binding.get("error") != OK:
		_finish({})
		return
	var original_journal: String = String(binding.payload.get("journal", "")).replace("\\", "/").simplify_path()
	_check(original_journal.ends_with(".txn/journal"), "binding names the original progress slot")
	_check(folder != original_journal.get_base_dir(), "benchmark uses a copied history instead of the active bound profile")
	if not original_journal.ends_with(".txn/journal") or folder == original_journal.get_base_dir():
		_finish({})
		return
	var slot: String = original_journal.trim_suffix(".txn/journal")
	var before_sources: Dictionary = _source_manifest(folder)
	var reader: CatalogProgress = CatalogProgress.new(slot)
	FreezeProfile.enabled = true
	FreezeProfile.start({"variant":"shared-precondition", "operation":"complete copied history authentication"})
	var history: Dictionary = reader._history(folder)
	FreezeProfile.finish()
	_write("history-authentication.json", {"mode":"same-process memo comparison", "profile":FreezeProfile.latest, "slot_from_original_binding":slot, "source":folder, "binding":binding.payload, "pid":OS.get_process_id()})
	_check(not history.has("reason") and history.has("journal"), "copied complete source and original binding authenticate before comparison")
	if history.has("reason") or not history.has("journal"):
		_finish({"history_error":history})
		return
	var journal: ReceiptJournal = history.journal
	var preserved_prefix: Dictionary = journal._prefix_snapshot()
	_check(not preserved_prefix.is_empty(), "shared full-byte prefix proof is available")
	var baseline: Dictionary = _three_scans(reader, history, {}, "prefix-only-path")
	var improved: Dictionary = _three_scans(reader, history, preserved_prefix, "witnessed-record-path")
	_check(RecordEncoding.fingerprint(baseline) == RecordEncoding.fingerprint(improved), "all unlock, discovery, and specialty results are identical")
	var after_sources: Dictionary = _source_manifest(folder)
	_check(RecordEncoding.fingerprint(before_sources) == RecordEncoding.fingerprint(after_sources), "every copied source path and SHA256 remains unchanged")
	_finish({"mode":"same-process pure memo control; not an old-binary run", "slot_from_original_binding":slot, "source":folder,
		"through":history.through, "pid":OS.get_process_id(), "before":baseline, "after":improved, "source_manifest_before":before_sources, "source_manifest_after":after_sources,
		"source_sha_unchanged":RecordEncoding.fingerprint(before_sources) == RecordEncoding.fingerprint(after_sources)})

func _three_scans(reader: CatalogProgress, history: Dictionary, prefix: Dictionary, variant: String) -> Dictionary:
	var journal: ReceiptJournal = history.journal
	journal._replace_prefix(prefix)
	ReceiptJournal._record_cache.clear()
	ReceiptJournal._cached_bytes = 0
	var result: Dictionary = {}
	result.unlock = _measure(variant, "unlock", func() -> Dictionary: return reader._derive(history, "unlock", ""), int(history.through))
	var unlock_hash: String = RecordEncoding.fingerprint(result.unlock) if not result.unlock.is_empty() else String(history.tip.base.journey.build.catalog.get("unlock", ""))
	result.discovery = _measure(variant, "discovery", func() -> Dictionary: return reader._derive(history, "discovery", unlock_hash), int(history.through))
	var verified: Dictionary[String, bool] = {}
	result.specialty = _measure(variant, "specialty", func() -> Dictionary: return SpecializationProgress.derive(history, reader._slot_hash, verified), int(history.through))
	for kind: String in result:
		_check(not result[kind].has("reason"), variant + " derives " + kind + " from the original complete source")
	return result

func _measure(variant: String, operation: String, work: Callable, through: int) -> Dictionary:
	FreezeProfile.start({"variant":variant, "operation":operation, "through":through, "memo_control":"same process; only prefix proof and decoded-record cache are controlled"})
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = work.call()
	var elapsed: int = Time.get_ticks_usec() - started
	FreezeProfile.finish()
	var sample: Dictionary = {"variant":variant, "operation":operation, "pid":OS.get_process_id(), "wall_usec":elapsed, "profile":FreezeProfile.latest.duplicate(true), "result":result, "result_fingerprint":RecordEncoding.fingerprint(result)}
	samples.append(sample)
	_check(int(sample.profile.get("metadata", {}).get("journal_record_bytes_reads", 0)) == through, variant + " " + operation + " rereads every source generation")
	_write(variant + "-" + operation + ".json", sample)
	print("M48_CATALOG_SCAN " + JSON.stringify({"variant":variant, "operation":operation, "wall_usec":elapsed, "result":sample.result_fingerprint}))
	return result

func _source_manifest(root_path: String) -> Dictionary:
	var result: Dictionary = {}
	_manifest_walk(root_path, "", result)
	return result

func _manifest_walk(root_path: String, relative: String, result: Dictionary) -> void:
	var access: DirAccess = DirAccess.open(root_path.path_join(relative))
	if access == null:
		result[relative] = "UNREADABLE"
		return
	access.include_hidden = true
	access.list_dir_begin()
	var name: String = access.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			var path: String = relative.path_join(name)
			if access.is_link(name): result[path] = "LINK"
			elif access.current_is_dir():
				result[path + "/"] = "DIRECTORY"
				_manifest_walk(root_path, path, result)
			else: result[path] = FileAccess.get_sha256(root_path.path_join(path))
		name = access.get_next()
	access.list_dir_end()

func _write(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output.path_join(name), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()

func _finish(value: Dictionary) -> void:
	value.samples = samples
	value.failures = failures
	_write("report.json", value)
	print("M48_CATALOG_TIMING " + JSON.stringify({"failures":failures, "output":output}))
	quit(0 if failures.is_empty() else 1)
