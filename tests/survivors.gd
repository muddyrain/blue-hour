extends SceneTree
## Isolated v4 identity, migration and settlement failures. Not native gameplay.

const MainScene: PackedScene = preload("res://src/app/main.tscn")
const Rules: CampRules = preload("res://src/features/camp/camp_rules.tres")
var _path: String = ""
var _results: Array[Dictionary] = []
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bh-progress="):
			_path = arg.trim_prefix("--bh-progress=")
	if not _path.contains(".local") or FileAccess.file_exists(_path):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	root.size = Vector2i(1280, 720)
	var app: Node = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	var before: Dictionary = app.camp_snapshot()
	_expect(RunSave.validate(before).is_empty() and before.schema_version == RunSave.SCHEMA_VERSION, "current camp retains stable identities with separate unknown growth")
	app.open_roster()
	_expect(app.roster_panel.visible and not app._title.visible, "real camp roster is a modal management view")
	app.open_expedition()
	_expect(app.expedition == null, "roster prevents underlying sortie start")
	for bad: String in ["", " leading", "trailing ", "1234567890123", "A\nB"]:
		app.rename_survivor(1, bad)
		_expect(app.camp_snapshot() == before and not app._progress_dirty, "invalid call sign cannot dirty campaign: " + bad.c_escape())
	app.rename_survivor(1, "蓝时")
	var renamed: Dictionary = app.camp_snapshot()
	_expect(renamed.crew[0].call_sign == "蓝时" and app.run_save.load_save() == OK and app.run_save.snapshot == renamed, "rename persists through real app command")
	var digest: String = FileAccess.get_sha256(_path)
	app.rename_survivor(1, "蓝时")
	_expect(FileAccess.get_sha256(_path) == digest and not app._progress_dirty, "same call sign does not rotate saves")
	app.close_roster()
	app.open_expedition()
	app.expedition.set_physics_process(false)
	_expect(app.expedition.survivors[0].call_sign == "蓝时" and app.expedition.crew_snapshot == renamed.crew, "next sortie receives saved call sign and detached roster")
	app.expedition.crew_snapshot[0].call_sign = "snapshot only"
	_expect(app.crew[0].call_sign == "蓝时", "sortie snapshot cannot mutate campaign")
	var report: Dictionary = {"evacuated":true,"loot":4,"food":3,"health":[192.0,196.0],"kills":3,
		"member_records":[{"id":2,"kills":1,"damage_received":4.0},{"id":1,"kills":2,"damage_received":8.0}]}
	var callback: Callable = app._finish_callback
	callback.call(report)
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	_expect(app.camp_snapshot() == renamed and proposal.crew[0].service.kills == 2 and proposal.crew[1].service.kills == 1, "stable IDs attribute reordered personal records before camp commit")
	callback.call(report)
	_expect(app._pending_settlement == proposal, "repeated finish cannot count a second outing")
	app.return_to_title()
	callback.call(report)
	app.return_to_title()
	_expect(app.camp_snapshot() == proposal and app.settled_sorties == 1 and app.crew[0].service.damage_received == 8.0, "camp applies one real record transaction")
	_expect(app.run_save.load_save() == OK and app.run_save.snapshot == proposal, "v4 round trip preserves records, health and equipment")
	for mutation: String in ["duplicate_id","definition","health","condition","permanent","level","name","service","negative","future","false_history"]:
		var bad: Dictionary = proposal.duplicate(true)
		match mutation:
			"duplicate_id": bad.crew[1].id = 1
			"definition": bad.crew[0].definition_id = "unknown"
			"health": bad.crew[0].health = INF
			"condition": bad.crew[0].condition = "down"
			"permanent": bad.crew[0].condition = "departed"
			"level": bad.crew[0].level = 99
			"name": bad.crew[0].call_sign = ""
			"service": bad.crew[0].service.extra = 1
			"negative": bad.crew[0].service.kills = -1
			"future": bad.crew[0].service.last_settlement_id = bad.profile_id + ":99"
			"false_history": bad.crew[0].service.sorties = 0
		_expect(not RunSave.validate(bad).is_empty(), "reject invalid survivor data: " + mutation)
	for mutation: String in ["missing","duplicate","wrong_damage","wrong_kills","unknown"]:
		var bad: Dictionary = report.duplicate(true)
		match mutation:
			"missing": bad.member_records.pop_back()
			"duplicate": bad.member_records[0].id = 1
			"wrong_damage": bad.member_records[1].damage_received = 100.0
			"wrong_kills": bad.kills = 4
			"unknown": bad.member_records[0].id = 3
		_expect(CampEconomy.preview(renamed, bad, renamed.profile_id + ":1", Rules).is_empty(), "reject mismatched event record: " + mutation)
	var next: Dictionary = report.duplicate(true)
	next.health = [0.0,196.0]
	next.kills = 0
	next.member_records = [{"id":1,"kills":0,"damage_received":192.0},{"id":2,"kills":0,"damage_received":0.0}]
	var down: Dictionary = CampEconomy.preview(proposal, next, proposal.profile_id + ":2", Rules)
	_expect(down.crew[0].condition == "down" and down.crew[0].health == 0 and down.loadout.size() == 1, "zero health becomes down with equipment idle, no permanent deletion")
	_expect(SurvivorRoster.member(down.crew,1).service.sorties == 2 and not down.crew[0].has("level"), "records never grant invented level stats")
	app.open_roster()
	var blocked: String = _path.get_base_dir().path_join("blocker")
	_write(blocked, "file".to_utf8_buffer())
	var store_path: String = app.run_save.path
	app.run_save.path = blocked.path_join("run.json")
	app.rename_survivor(2, "琥珀")
	_expect(app._progress_dirty and app.crew[1].call_sign == "琥珀" and FileAccess.get_sha256(_path) != "", "failed name write keeps new identity in memory")
	var pending: Dictionary = app.camp_snapshot()
	app.run_save.path = store_path
	app.save_camp()
	_expect(not app._progress_dirty and app.run_save.snapshot == pending, "retry saves identity without another settlement or record")
	app.close_roster()
	app.open_practice()
	app.expedition.set_physics_process(false)
	app._finish_callback.call(report)
	app.return_to_title()
	_expect(app.camp_snapshot() == pending, "practice cannot change formal records or campaign")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	_migrations()
	var file: FileAccess = FileAccess.open(_path.get_base_dir().path_join("survivor-fixture-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_results.size(),"failures":_failures,"results":_results},"\t"))
	file.close()
	print("BH_SURVIVOR_FIXTURES checks=%d failures=%d" % [_results.size(),_failures])
	quit(0 if _failures == 0 else 1)


func _migrations() -> void:
	var sources: Array[String] = ["m3-01/final-second", "worktree-return/day1", "m3-03/first"]
	var backups: Array[String] = ["m3-01/final-first", "m3-02/day2", "m3-03/second"]
	for version: int in [1,2,3]:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/" + sources[version-1] + "/saved-run.json")
		var backup: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/" + backups[version-1] + "/saved-run.json")
		var old: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		if version == 3:
			for entry: Dictionary in old.loadout:
				entry.member_id = int(entry.member_id)
		var target: String = _path + "-v%d" % version
		_write(target, bytes)
		_write(target + ".bak", backup)
		var digest: String = FileAccess.get_sha256(target)
		var backup_digest: String = FileAccess.get_sha256(target + ".bak")
		var store: RunSave = RunSave.new(target)
		_expect(store.load_save() == OK and store.migrated_from == version, "actual archived v%d loads as v4" % version)
		_expect(store.snapshot.day == old.day and store.snapshot.cash == old.cash and store.snapshot.last_settlement_id == old.last_settlement_id
			and store.snapshot.crew[0].health == old.crew[0].health and store.snapshot.crew[1].health == old.crew[1].health, "v%d retains identity, resources, date and life" % version)
		_expect(store.snapshot.crew[0].service.sorties == 0 and store.snapshot.crew[1].service.kills == 0, "v%d initializes no fictitious historical combat or experience" % version)
		if version == 3:
			_expect(store.snapshot.weapons == old.weapons and store.snapshot.loadout == old.loadout and store.snapshot.camp_spending == 10 and store.snapshot.food == old.food, "v3 preserves actual loot identities, repair spending and ownership")
		_expect(FileAccess.get_file_as_bytes(target) == bytes and FileAccess.get_file_as_bytes(target + ".bak") == backup, "v%d read does not rewrite either old file" % version)
		_expect(store.save(store.snapshot) == OK and FileAccess.get_file_as_bytes(target + ".v%d-" % version + digest + ".json") == bytes
			and FileAccess.get_file_as_bytes(target + ".v%d-" % version + backup_digest + ".json") == backup, "v%d first save archives both distinct byte-exact originals" % version)
		_write(target, "{invalid".to_utf8_buffer())
		_expect(store.load_save() != OK and store.load_save(true) == OK and FileAccess.get_file_as_string(target) == "{invalid", "v%d bad primary offers valid backup without silent replacement" % version)


func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _expect(condition: bool, label: String) -> void:
	_results.append({"passed":condition,"label":label})
	if not condition:
		_failures += 1
		push_error("FAIL survivor: " + label)
	else:
		print("PASS survivor: " + label)
