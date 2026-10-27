extends SceneTree
## Headless resource/migration fixtures; native play is verified separately.

const MainScene: PackedScene = preload("res://src/app/main.tscn")
const SortieScene: PackedScene = preload("res://src/features/expedition/expedition.tscn")
const Rules: CampRules = preload("res://src/features/camp/camp_rules.tres")

var _path: String = ""
var _results: Array[Dictionary] = []
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			_path = argument.trim_prefix("--bh-progress=")
	if not _path.contains(".local") or FileAccess.file_exists(_path):
		quit(1)
		return
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	_check_days()
	await _check_migration()
	await _check_searches()
	var file: FileAccess = FileAccess.open(_path.get_base_dir().path_join("food-fixture-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_results.size(),"failures":_failures,"results":_results,"scope":"isolated headless fixtures, not native play"},"\t"))
	file.close()
	print("BH_FOOD_FIXTURES checks=%d failures=%d" % [_results.size(),_failures])
	quit(0 if _failures == 0 else 1)


func _check_days() -> void:
	var current: Dictionary = {"schema_version":2,"profile_id":"0123456789abcdef0123456789abcdef",
		"day":2,"cash":53,"food":Rules.initial_food,"crew":[{"id":1,"health":200.0},{"id":2,"health":196.0}],
		"settled_sorties":0,"last_settlement_id":"","last_day":{}}
	var expected_food: Array[int] = [3,1,0,1]
	for index: int in range(4):
		var report: Dictionary = {"evacuated":true,"loot":4 if index < 3 else 0,
			"food":3 if index == 0 or index == 3 else 0,"health":[200.0,196.0]}
		var old: Dictionary = current.duplicate(true)
		var token: String = "%s:%d" % [current.profile_id,index+1]
		var after: Dictionary = CampEconomy.preview(current,report,token,Rules)
		_expect(not after.is_empty() and after.food == expected_food[index] and after.day == index+3, "multi-day exact resource outcome %d" % index)
		_expect(current == old and after.crew == current.crew, "proposal does not mutate camp or apply hunger damage %d" % index)
		_expect(after.last_day.food_required == 2 and after.last_day.food_shortage == (1 if index == 2 else 0), "exact demand and shortage %d" % index)
		_expect(CampEconomy.preview(after,report,token,Rules).is_empty(), "same settlement ID cannot be applied to updated camp %d" % index)
		current = after
	var failed: Dictionary = CampEconomy.preview(current,{"evacuated":false,"loot":4,"food":3,"health":[200.0,196.0]},"%s:5" % current.profile_id,Rules)
	_expect(failed.last_day.food_found == 0 and failed.last_day.cash_gained == 0, "failed extraction cannot bank either carried resource")
	var view: Dictionary = CampEconomy.rations(6,[{"id":2,"health":0.0},{"id":1,"health":120.0}],0,Rules)
	_expect(view.member_ids == [1] and view.day == 6 and view.required == 1, "daily demand uses stable living departure identities and actual day")
	var full: Dictionary = current.duplicate(true)
	full.food = CampRules.FOOD_LIMIT
	full.last_day = {}
	var capped: Dictionary = CampEconomy.preview(full,{"evacuated":true,"loot":0,"food":3,"health":[200.0,196.0]},"%s:5" % current.profile_id,Rules)
	_expect(capped.last_day.food_stored == 0 and capped.last_day.food_overflow == 3 and capped.food == CampRules.FOOD_LIMIT-2,
		"configured integer ceiling is explicit in ledger, no hidden overflow")
	for invalid: Variant in [-1, 1.5, NAN, INF, CampRules.FOOD_LIMIT+1, "3", true]:
		var broken: Dictionary = current.duplicate(true)
		broken.food = invalid
		_expect(not RunSave.validate(broken).is_empty(), "reject invalid food " + str(invalid))
	for field: String in ["food_consumed","food_required","food_before","food_after","cash_after","cash_gained","food_shortage"]:
		var broken: Dictionary = current.duplicate(true)
		broken.last_day[field] += 1
		_expect(not RunSave.validate(broken).is_empty(), "reject inconsistent transaction " + field)
	var shortage: Dictionary = current.last_day.duplicate(true)
	shortage.food_shortage = 1
	var candidate: Dictionary = HungerOutcome.candidate(shortage)
	_expect(candidate.loss_count == 1 and candidate.victim_ids.is_empty() and not candidate.applied,
		"historical shortage candidate counts losses but never invents victims or changes saved health")
	shortage.food_shortage = 10
	_expect(HungerOutcome.candidate(shortage).loss_count == 2, "candidate cannot lose more members than eligible roster")
	shortage.food_shortage = 0
	_expect(HungerOutcome.candidate(shortage).loss_count == 0, "enough food produces no loss candidate")
	var normal: MissionSupply = preload("res://src/features/camp/scavenge.tres")
	var market: MissionSupply = preload("res://src/features/camp/supermarket.tres")
	_expect(normal.supports(&"cash") and not normal.supports(&"food") and market.supports(&"food"), "source config distinguishes ordinary and guaranteed-food sample missions")
	var changed: MissionSupply = market.duplicate() as MissionSupply
	changed.food_reward = 7
	_expect(changed.reward(&"food") == 7 and market.reward(&"food") == 3, "food rewards come from independent replaceable source data")
	current.last_day.ration_member_ids = [1,1]
	_expect(not RunSave.validate(current).is_empty(), "reject duplicate ration identities")


func _check_migration() -> void:
	var original: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/m3-01/final-second/saved-run.json")
	var old_backup: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/m3-01/final-first/saved-run.json")
	_write(_path,original)
	_write(_path+".bak",old_backup)
	var old_data: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	var store: RunSave = RunSave.new(_path)
	_expect(store.load_save() == OK and store.migrated_from == 1 and store.snapshot.schema_version == RunSave.SCHEMA_VERSION, "actual archived M3-01 v1 file reads through explicit migration to v3")
	_expect(store.snapshot.food == Rules.v1_migration_food and store.snapshot.last_day.is_empty(), "migration default is explicit and does not invent history")
	_expect(store.snapshot.profile_id == old_data.profile_id and store.snapshot.last_settlement_id == old_data.last_settlement_id and store.snapshot.cash == old_data.cash,
		"migration retains profile, unique settlement identity and currency")
	_expect(FileAccess.get_file_as_bytes(_path) == original and FileAccess.get_file_as_bytes(_path+".bak") == old_backup,
		"first load preserves both original byte streams")
	var app: Node = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	_expect(app._requires_continue and app._status.text.contains("迁移默认值"), "real app visibly discloses v1 food initialization before Continue")
	app.continue_game()
	var before: Dictionary = app.camp_snapshot()
	_expect(before == store.snapshot and FileAccess.get_file_as_bytes(_path) == original, "Continue restores migrated state without rewriting old file")
	app.open_expedition()
	app.expedition.set_physics_process(false)
	var report: Dictionary = {"evacuated":true,"loot":4,"food":3,"health":[200.0,192.0],"searched":true,"sites_searched":2,"kills":0}
	var callback: Callable = app._finish_callback
	callback.call(report)
	callback.call(report)
	var proposal: Dictionary = app._pending_settlement.duplicate(true)
	_expect(app.camp_snapshot() == before and proposal.food == 3, "repeated result callback prepares one transaction but keeps pre-camp inventory")
	var blocker: String = _path.get_base_dir().path_join("blocked")
	_write(blocker,"file instead of directory".to_utf8_buffer())
	app.run_save = RunSave.new(blocker.path_join("run.json"))
	app.return_to_title()
	callback.call(report)
	app.return_to_title()
	_expect(app.camp_snapshot() == proposal and app._progress_dirty and app._retry_button.visible and app._status.text.contains("保存失败"),
		"camp commits exactly once even when actual filesystem write fails")
	_expect(FileAccess.get_file_as_bytes(_path) == original and FileAccess.get_file_as_bytes(_path+".bak") == old_backup,
		"failed write keeps v1 primary and backup unchanged")
	app.run_save = RunSave.new(_path)
	app.save_camp()
	app.save_camp()
	_expect(not app._progress_dirty and app.camp_snapshot() == proposal and app.run_save.load_save() == OK and app.run_save.snapshot == proposal,
		"retry writes one v3 snapshot without another reward or ration deduction")
	_expect(FileAccess.get_file_as_bytes(_path+".bak") == original, "first v2 save keeps exact old primary as backup")
	_expect(FileAccess.get_file_as_bytes(_path+".v1-"+_sha(original)+".json") == original
		and FileAccess.get_file_as_bytes(_path+".v1-"+_sha(old_backup)+".json") == old_backup,
		"both previous v1 originals have immutable content-addressed migration copies")
	app.open_expedition()
	app.expedition.set_physics_process(false)
	callback.call(report)
	_expect(app.camp_snapshot() == proposal and app.phase == app.Phase.EXPEDITION, "old callback cannot modify food during next sortie")
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	_write(_path,"{truncated v2".to_utf8_buffer())
	app = MainScene.instantiate()
	root.add_child(app)
	_expect(app._progress_blocked and app._backup_button.visible, "corrupt new primary offers independently checked v1 backup")
	app.use_backup()
	_expect(app.camp_snapshot() == before and app._status.text.contains("迁移默认值") and FileAccess.get_file_as_string(_path) == "{truncated v2",
		"explicit backup choice migrates in memory, preserving corrupt bytes")
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout


func _check_searches() -> void:
	var sortie: Expedition = SortieScene.instantiate() as Expedition
	root.add_child(sortie)
	sortie.set_physics_process(false)
	# Isolated rule fixture only; final native games retain ordinary enemy damage.
	sortie.tuning.enemy_damage = 0.0
	var rewards: Array[int] = []
	sortie.search_completed.connect(func(reward: int) -> void: rewards.append(reward))
	sortie.command_move(Vector2(928,650))
	sortie.request_search(&"food")
	var worker: FieldActor = sortie.search_actor
	sortie.command_move(Vector2(928,650))
	_expect(sortie.search_actor == worker, "food worker retains intent under ground replacement order")
	for tick: int in range(1600):
		sortie.step(0.025)
		if worker.activity == FieldActor.Activity.SEARCHING:
			break
	_expect(worker.activity == FieldActor.Activity.SEARCHING and not worker.visible, "food worker reaches actual second building entrance")
	for tick: int in range(40):
		sortie.step(0.025)
	sortie.toggle_pause()
	var partial: float = sortie.search_site(&"food").progress
	sortie.step(100.0)
	_expect(sortie.search_site(&"food").progress == partial and sortie.food_loot == 0, "pause freezes food work and cannot reward")
	sortie.request_search(&"food")
	_expect(sortie.search_actor == null and worker.visible and sortie.food_loot == 0, "same food building cancels and reveals worker without reward")
	sortie.request_search()
	sortie.request_search(&"food")
	_expect(sortie.search_site(&"food").progress == partial and sortie.search_progress == 0.0, "switching targets preserves each point's own TMP progress")
	sortie.toggle_pause()
	for tick: int in range(2200):
		sortie.step(0.025)
		if sortie.elapsed >= sortie.tuning.bus_ready_seconds and sortie.phase == Expedition.Phase.ACTIVE:
			sortie.request_extraction()
		if sortie.search_site(&"food").searched:
			break
	_expect(sortie.food_loot == 3 and sortie.loot == 0 and not sortie.searched and rewards == [3], "food point pays once to carried food, independent of money")
	sortie.request_search(&"food")
	_expect(sortie.food_loot == 3 and rewards.size() == 1, "completed food point cannot pay or emit collect again")
	sortie.request_search()
	for tick: int in range(2400):
		sortie.step(0.025)
		if sortie.searched:
			break
	_expect(sortie.loot == 4 and sortie.food_loot == 3 and rewards == [3,4] and sortie.phase == Expedition.Phase.BOARDING,
		"second search completes while bus waits, two typed resources and two collect events")
	_expect(sortie._hud.view._currency.text.contains("食物 2（携带+3）") and sortie._hud.view._progress.text.contains("2 / 2"), "C adapter shows actual bank stock and carried resources separately")
	sortie.command_move(sortie.layout.bus_door)
	for tick: int in range(1600):
		sortie.step(0.025)
		if sortie.phase == Expedition.Phase.FINISHED:
			break
	_expect(sortie.phase == Expedition.Phase.FINISHED and not sortie._hud.view.visible, "both searches still support normal gathering and frozen extraction")
	sortie.request_search(&"food")
	sortie.step(100.0)
	_expect(sortie.food_loot == 3 and sortie.loot == 4 and rewards.size() == 2, "finished world cannot create more resources")
	sortie.queue_free()
	await process_frame


func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _sha(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _expect(condition: bool, label: String) -> void:
	_results.append({"passed":condition,"label":label})
	if not condition:
		_failures += 1
		push_error("FAIL camp food: " + label)
	else:
		print("PASS camp food: " + label)
