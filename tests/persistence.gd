extends SceneTree
## Isolated disk fixtures. Not evidence of player input or native rendering.

const MainScene: PackedScene = preload("res://src/app/main.tscn")

var _checks: int = 0
var _failures: int = 0
var _path: String = ""
var _results: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			_path = argument.trim_prefix("--bh-progress=")
	if not _path.contains(".local") or FileAccess.file_exists(_path):
		quit(1)
		return
	var store: RunSave = RunSave.new(_path)
	var first: Dictionary = _state(1)
	var second: Dictionary = _state(2)
	_expect(store.load_save() == ERR_FILE_NOT_FOUND and not store.has_files(), "empty load does not create save")
	_expect(store.save(first) == OK and store.load_save() == OK and store.snapshot == first, "first snapshot round trip")
	_expect(store.save(second) == OK and store.load_save(true) == OK and store.snapshot == first, "next save keeps last valid camp as backup")
	var good_main: String = FileAccess.get_file_as_string(_path)
	var good_backup: String = FileAccess.get_file_as_string(_path + ".bak")
	var samples: Array[Dictionary] = []
	for change: String in ["version", "duplicate", "unknown_id", "nan", "negative", "fraction", "missing", "identity", "settlement", "unknown_field"]:
		var sample: Dictionary = second.duplicate(true)
		match change:
			"version": sample.schema_version = 99
			"duplicate": sample.crew[1].id = 1
			"unknown_id": sample.crew[1].id = 77
			"nan": sample.crew[0].health = NAN
			"negative": sample.cash = -1
			"fraction": sample.day = 4.5
			"missing": sample.erase("crew")
			"identity": sample.profile_id = "unknown"
			"settlement": sample.last_settlement_id = first.last_settlement_id
			"unknown_field": sample.inventory = 10
		samples.append(sample)
		_expect(store.save(sample) != OK and FileAccess.get_file_as_string(_path) == good_main and FileAccess.get_file_as_string(_path + ".bak") == good_backup,
			"invalid write rejected without touching current/backup: " + change)
	var malformed: Array[String] = [good_main.left(30), "{invalid json", JSON.stringify(samples[0]), JSON.stringify(samples[1]), JSON.stringify(samples[2]),
		good_main.replace('"health": 200.0', '"health": 1e999'), "", "[]"]
	for index: int in range(malformed.size()):
		_write(_path, malformed[index])
		var error: Error = store.load_save()
		_expect(error != OK and store.snapshot.is_empty(), "bad read rejected: %d %s" % [index, store.diagnostic])
		_expect(store.save(second) != OK and FileAccess.get_file_as_string(_path) == malformed[index] and FileAccess.get_file_as_string(_path + ".bak") == good_backup,
			"bad source and good backup preserved, no implicit replacement: %d" % index)
		_expect(store.load_save(true) == OK and store.snapshot == first, "backup independently validates: %d" % index)
		_expect(store.save(second, true) == OK and _contains_rejected(malformed[index]), "explicit recovery archives exact rejected bytes: %d" % index)
	_write(_path, good_main)
	_write(_path + ".bak", "{bad backup")
	_expect(store.save(_state(3)) == OK and _contains_rejected("{bad backup"), "corrupt backup also preserved rather than silently deleted")
	_write(_path, good_main)
	_write(_path + ".bak", good_backup)
	var reordered: Dictionary = second.duplicate(true)
	reordered.crew.reverse()
	reordered.crew[0].health = 195.1234567890123
	var order_store: RunSave = RunSave.new(_path + "-reordered")
	_expect(order_store.save(reordered) == OK and order_store.load_save() == OK and order_store.snapshot == reordered,
		"stable IDs are independent of array order; full precision fractional health round trips")
	var fresh: Dictionary = _state(1)
	fresh.profile_id = RunSave.new_profile_id()
	fresh.last_settlement_id = "%s:1" % fresh.profile_id
	WeaponInventory.initialize(fresh, "initial")
	_expect(store.save(fresh) == OK and store.load_save(true) == OK and store.snapshot == second,
		"new profile replacement retains previous valid profile as backup")
	_write(_path, good_main)
	_write(_path + ".bak", good_backup)
	await _app_checks(first, second)
	var report: FileAccess = FileAccess.open(_path.get_base_dir().path_join("fixture-report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"results":_results,"scope":"isolated headless disk and app fixtures"}, "\t"))
	report.close()
	print("BH_PERSISTENCE checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _app_checks(first: Dictionary, second: Dictionary) -> void:
	root.size = Vector2i(1280, 720)
	var app: Node = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	_expect(app._requires_continue and app.day == 2, "valid file awaits Continue, does not silently start new camp")
	app.open_expedition()
	_expect(app.expedition == null, "sortie gated before Continue")
	app.continue_game()
	_expect(app.camp_snapshot() == second, "Continue maps stable crew IDs to exact live camp")
	app.reset_demo()
	_expect(app._new_game_confirmation.visible and app.camp_snapshot() == second, "New Game waits for confirmation")
	app._new_game_confirmation.hide()
	app.open_expedition()
	app.expedition.set_physics_process(false)
	var stale: Callable = app._finish_callback
	var original_id: String = app._active_sortie_id
	var report: Dictionary = {"loot":4,"health":[180.0,172.0],"kills":1,"searched":true,"evacuated":true}
	app._on_expedition_finished(report, original_id)
	app._on_expedition_finished(report, original_id)
	_expect(app.day == 4 and app.cash == 61 and app.settled_sorties == 2 and app._pending_settlement.cash == 65, "duplicate report only prepares one preview; no resource changes before camp")
	var saved_before: String = FileAccess.get_sha256(_path)
	_expect(not app._progress_dirty and app.run_save.load_save() == OK and app.run_save.snapshot == second, "result screen does not write before camp boundary")
	# A real parent-file obstruction exercises filesystem failure, without a production fail switch.
	var blocker: String = _path.get_base_dir().path_join("blocked-parent")
	_write(blocker, "not a directory")
	app.run_save = RunSave.new(blocker.path_join("run.json"))
	app.return_to_title()
	_expect(app._progress_dirty and app._status.text.begins_with("保存失败") and app.cash == 65 and FileAccess.get_sha256(_path) == saved_before,
		"write failure visible, in-memory settlement and previous disk bytes retained")
	app.run_save = RunSave.new(_path)
	app.save_camp()
	_expect(not app._progress_dirty and app.run_save.load_save() == OK and app.run_save.snapshot == app.camp_snapshot(), "retry saves same settlement without granting again")
	app.open_expedition()
	app.expedition.set_physics_process(false)
	stale.call(report)
	_expect(app.phase == app.Phase.EXPEDITION and app.settled_sorties == 3 and app.cash == 65, "stale old sortie callback rejected during new sortie")
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	_write(_path, "{bad primary")
	_write(_path + ".bak", "{bad backup")
	app = MainScene.instantiate()
	root.add_child(app)
	_expect(app._progress_blocked and not app._backup_button.visible, "both invalid files block normal sortie without offering an unchecked backup")
	app.open_expedition()
	_expect(app.expedition == null, "no valid camp cannot enter normal sortie")
	app.open_practice()
	app.expedition.set_physics_process(false)
	app.expedition.request_extraction()
	app.return_to_title()
	_expect(FileAccess.get_file_as_string(_path) == "{bad primary" and FileAccess.get_file_as_string(_path + ".bak") == "{bad backup",
		"practice remains available but never overwrites either invalid progress file")
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	_write(_path, "{truncated camp")
	_write(_path + ".bak", JSON.stringify(first))
	app = MainScene.instantiate()
	root.add_child(app)
	_expect(app._progress_blocked and app._status.text.contains("读取失败") and app._backup_button.visible, "bad primary visibly blocks sortie and offers checked backup")
	app.use_backup()
	_expect(app.camp_snapshot() == first and FileAccess.get_file_as_string(_path) == "{truncated camp", "explicit backup loads valid memory without overwriting rejected bytes")
	app.reset_demo()
	app._new_game_confirmation.confirmed.emit()
	app._new_game_confirmation.hide()
	_expect(app.day == 2 and app.cash == 53 and app.last_settlement_id.is_empty() and FileAccess.get_file_as_string(_path) == "{truncated camp", "confirmed new game resets memory only until next settlement")
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout


func _state(count: int) -> Dictionary:
	var identity: String = "0123456789abcdef0123456789abcdef"
	var data: Dictionary = {"schema_version":RunSave.SCHEMA_VERSION,"profile_id":identity,"day":count+2,"cash":53+count*4,"food":2,"last_day":{},
		"settled_sorties":count,"last_settlement_id":"%s:%d" % [identity,count],
		"crew":[{"id":1,"health":200.0},{"id":2,"health":196.0}]}
	WeaponInventory.initialize(data, "initial")
	SurvivorRoster.initialize(data.crew)
	return data


func _write(target: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _contains_rejected(content: String) -> bool:
	for name: String in DirAccess.get_files_at(_path.get_base_dir()):
		if name.contains(".rejected-") and FileAccess.get_file_as_string(_path.get_base_dir().path_join(name)) == content:
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	_results.append({"passed":condition,"label":label})
	if not condition:
		_failures += 1
		push_error("FAIL persistence: " + label)
	else:
		print("PASS persistence: " + label)
