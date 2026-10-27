extends SceneTree
## Identity is immutable definition data; old call signs have no provenance bit to migrate.

const MAIN: PackedScene = preload("res://src/app/main.tscn")
var _path: String
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
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var app: Node = MAIN.instantiate()
	root.add_child(app)
	await process_frame
	_expect(app.crew[0].call_sign == "顾予安" and app.crew[1].call_sign == "夏之遥", "fresh call signs use formal Chinese defaults")
	_expect(app.camp_snapshot().schema_version == RunSave.SCHEMA_VERSION and app.crew[0].size() == 7, "fixed identity remains definition data; current schema has independent unknown growth")
	app.open_roster()
	await _inspect_profile(app, 1, "顾予安", "♂ 男", GenderBadge.MALE_ICON)
	await _inspect_profile(app, 2, "夏之遥", "♀ 女", GenderBadge.FEMALE_ICON)
	app.rename_survivor(1, "Azure")
	app.rename_survivor(2, "Amber")
	var english: Dictionary = app.camp_snapshot()
	var english_bytes: PackedByteArray = FileAccess.get_file_as_bytes(_path)
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	app = MAIN.instantiate()
	root.add_child(app)
	await process_frame
	_expect(app._pending_save == english and FileAccess.get_file_as_bytes(_path) == english_bytes, "Azure/Amber v4 aliases stay byte-exact before Continue")
	app.continue_game()
	_expect(app.camp_snapshot() == english and FileAccess.get_file_as_bytes(_path) == english_bytes, "Continue never guesses whether matching English names were custom")
	app.open_roster()
	await _inspect_profile(app, 1, "Azure", "♂ 男", GenderBadge.MALE_ICON)
	await _inspect_profile(app, 2, "Amber", "♀ 女", GenderBadge.FEMALE_ICON)
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	var archived: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/m4-02/market/saved-run.json")
	var backup: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/m4-02/scavenge/saved-run.json")
	_write(_path, archived)
	_write(_path + ".bak", backup)
	var store: RunSave = RunSave.new(_path)
	_expect(store.load_save() == OK and store.migrated_from == 4, "actual M402 v4 archive migrates only new unknown growth in memory")
	var historical: Dictionary = store.snapshot.duplicate(true)
	app = MAIN.instantiate()
	root.add_child(app)
	app.continue_game()
	_expect(app.camp_snapshot() == historical and FileAccess.get_file_as_bytes(_path) == archived and FileAccess.get_file_as_bytes(_path + ".bak") == backup,
		"actual old v4 retains names, life, service, loot ownership and both byte streams")
	app.open_roster()
	var long_chinese: String = "蓝时归航观察员一号同行者"
	var long_english: String = "NorthStar_02"
	app.rename_survivor(1, long_chinese)
	app.rename_survivor(2, long_english)
	var expected: Dictionary = historical.duplicate(true)
	expected.crew[0].call_sign = long_chinese
	expected.crew[1].call_sign = long_english
	_expect(long_chinese.length() == 12 and long_english.length() == 12 and app.camp_snapshot() == expected,
		"12-character Chinese/English changes only exact call_sign fields")
	await _inspect_profile(app, 1, long_chinese, "♂ 男", GenderBadge.MALE_ICON)
	await _inspect_profile(app, 2, long_english, "♀ 女", GenderBadge.FEMALE_ICON)
	_expect(app.run_save.load_save() == OK and app.run_save.snapshot == expected, "custom aliases persist with existing v4 validation")
	app.close_roster()
	app.open_expedition()
	app.expedition.set_physics_process(false)
	_expect(app.expedition.survivors[0].call_sign == long_chinese and app.expedition.survivors[1].call_sign == long_english
		and app.expedition.crew_snapshot == expected.crew, "actual field retains custom aliases and stable snapshots")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	var old_sources: Array[String] = ["m3-01/final-second", "worktree-return/day1", "m3-03/first"]
	for version: int in range(1, 4):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/" + old_sources[version - 1] + "/saved-run.json")
		var path: String = _path + "-v%d" % version
		_write(path, bytes)
		var legacy: RunSave = RunSave.new(path)
		_expect(legacy.load_save() == OK and legacy.migrated_from == version and legacy.snapshot.crew[0].call_sign == "顾予安" and legacy.snapshot.crew[1].call_sign == "夏之遥",
			"v%d missing alias metadata receives Chinese initialization, not guessed history" % version)
		_expect(FileAccess.get_file_as_bytes(path) == bytes, "v%d initialization never rewrites original file" % version)
	var file: FileAccess = FileAccess.open(_path.get_base_dir().path_join("character-identity-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_results.size(),"failures":_failures,"results":_results}, "\t"))
	file.close()
	print("BH_CHARACTER_IDENTITY checks=%d failures=%d" % [_results.size(), _failures])
	quit(0 if _failures == 0 else 1)


func _inspect_profile(app: Node, member_id: int, alias: String, gender: String, icon: Texture2D) -> void:
	var panel: RosterPanel = app.roster_panel
	panel.selected_member_id = member_id
	panel.refresh(app.camp_snapshot())
	await process_frame
	await process_frame
	var base: SurvivorDefinition = SurvivorRoster.definition(member_id)
	_expect(panel._identity.text == base.default_display_name and panel._call_sign.text == "呼号：" + alias, "formal name and mutable alias remain separate")
	_expect(base.gender_text() == gender and panel._gender_title._icon.texture == icon and panel._gender_detail.tooltip_text == "性别：" + gender,
		"fixed-ID gender appears as native vector and explicit final detail row")
	_expect(panel._gender_detail.get_index() == panel._service.get_index() + 1, "gender is the final informational row after real service")
	for control: Control in [panel._identity, panel._call_sign, panel._condition, panel._gender_title, panel._gender_detail, panel.back_button]:
		var rect: Rect2 = control.get_global_rect()
		_expect(Rect2(0, 0, 1280, 720).encloses(rect), "profile identity, gender and navigation stay in viewport")
	for index: int in range(2):
		_expect(panel.member_buttons[index].get_global_rect().encloses(panel._member_genders[index].get_global_rect()), "gender badge stays within its actual roster button")


func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _expect(value: bool, label: String) -> void:
	_results.append({"passed":value,"label":label})
	if not value:
		_failures += 1
		push_error("BH_CHARACTER_IDENTITY " + label)
